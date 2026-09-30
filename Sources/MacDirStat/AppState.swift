import AppKit
import SwiftUI

/// Hover lives in its own object so mouse movement only redraws the bits that show it.
@MainActor
final class HoverState: ObservableObject {
    @Published var node: FileNode?
}

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case welcome
        case scanning
        case ready
    }

    enum SortKey: String {
        case name, size, items, modified
    }

    // Tree
    @Published private(set) var phase: Phase = .welcome
    @Published private(set) var root: FileNode?
    @Published var viewRoot: FileNode?
    @Published var selection: FileNode?
    @Published var selectedExtension: UInt16?
    @Published private(set) var extensionStats: [ExtensionStat] = []
    /// Bumped whenever nodes are added/removed so views know to reload.
    @Published private(set) var treeVersion = 0

    // Scanning
    @Published private(set) var progress = DiskScanner.Snapshot()
    @Published private(set) var scanVerb = Whimsy.scanVerbs[0]
    @Published private(set) var scanPath = ""
    @Published private(set) var scanStarted = Date()
    @Published private(set) var lastScanDuration: TimeInterval = 0
    @Published private(set) var unreadableCount = 0
    @Published var toast: String?

    // Appearance
    @Published var theme: Theme { didSet { UserDefaults.standard.set(theme.id, forKey: "theme") } }
    @Published var style: TreemapStyle { didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") } }
    @Published var showLabels: Bool { didSet { UserDefaults.standard.set(showLabels, forKey: "labels") } }

    let hover = HoverState()

    private var scanner: DiskScanner?
    private var hardLinks = HardLinkRegistry()
    /// Bumped per full scan so late subtree rescans can tell their tree is gone.
    private var scanGeneration = 0
    private var progressTimer: Timer?
    private var extensionColors: [RGB] = []
    private var toastWork: DispatchWorkItem?

    init() {
        let defaults = UserDefaults.standard
        theme = Theme.named(defaults.string(forKey: "theme") ?? "ivory")
        style = TreemapStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .sketch
        showLabels = defaults.object(forKey: "labels") as? Bool ?? true
    }

    var isScanning: Bool { phase == .scanning }

    // MARK: - Colours

    func color(forExtension id: UInt16) -> RGB {
        Int(id) < extensionColors.count ? extensionColors[Int(id)] : Palette.fallbackColor(for: id)
    }

    func color(for node: FileNode) -> RGB {
        node.isDirectory ? Palette.directoryLeaf : color(forExtension: node.extID)
    }

    private func assignColors() {
        var colors = (0..<ExtensionRegistry.shared.count).map { Palette.fallbackColor(for: UInt16($0)) }
        for (rank, stat) in extensionStats.prefix(Palette.extensionColors.count).enumerated() where Int(stat.id) < colors.count {
            colors[Int(stat.id)] = Palette.extensionColors[rank]
        }
        extensionColors = colors
    }

    // MARK: - Scanning

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Map it"
        panel.message = "Pick a folder (or a whole disk) to map"
        if panel.runModal() == .OK, let url = panel.url {
            scan(url)
        }
    }

    func scan(_ url: URL) {
        cancelScan(returnToWelcome: false)

        let path = url.standardizedFileURL.path
        let scanner = DiskScanner()
        self.scanner = scanner
        scanPath = path
        scanStarted = Date()
        progress = DiskScanner.Snapshot()
        scanVerb = Whimsy.scanVerbs.randomElement()!
        phase = .scanning

        var ticks = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self, weak scanner] _ in
            MainActor.assumeIsolated {
                guard let self, let scanner, self.scanner === scanner else { return }
                self.progress = scanner.snapshot
                ticks += 1
                if ticks % 22 == 0 { self.scanVerb = Whimsy.scanVerbs.randomElement()! }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let started = Date()
            let result = scanner.scan(path: path)
            let stats = result.map { ExtensionStats.compute(root: $0) } ?? []
            let snapshot = scanner.snapshot
            let links = scanner.hardLinks
            DispatchQueue.main.async {
                guard self.scanner === scanner else { return } // superseded or cancelled
                self.finishScan(result, links: links, stats: stats, snapshot: snapshot,
                                duration: Date().timeIntervalSince(started))
            }
        }
    }

    private func finishScan(_ result: FileNode?, links: [HardLinkEntry], stats: [ExtensionStat], snapshot: DiskScanner.Snapshot, duration: TimeInterval) {
        progressTimer?.invalidate()
        progressTimer = nil
        scanner = nil
        guard let result else {
            phase = root == nil ? .welcome : .ready
            showToast("Couldn't read that folder. Does MacDirStat have access to it?")
            return
        }
        progress = snapshot
        unreadableCount = snapshot.unreadable
        lastScanDuration = duration
        extensionStats = stats
        assignColors()
        hardLinks = HardLinkRegistry(links)
        scanGeneration += 1
        root = result
        viewRoot = result
        selection = nil
        selectedExtension = nil
        hover.node = nil
        treeVersion += 1
        phase = .ready
    }

    func cancelScan(returnToWelcome: Bool = true) {
        scanner?.cancel()
        scanner = nil
        progressTimer?.invalidate()
        progressTimer = nil
        if returnToWelcome && phase == .scanning {
            phase = root == nil ? .welcome : .ready
        }
    }

    func rescan() {
        guard let root else { return }
        scan(URL(fileURLWithPath: root.path))
    }

    func closeScan() {
        cancelScan()
        root = nil
        viewRoot = nil
        selection = nil
        extensionStats = []
        hardLinks = HardLinkRegistry()
        scanGeneration += 1
        treeVersion += 1
        phase = .welcome
    }

    /// Rescan one folder in place and splice the fresh subtree into the tree.
    func rescan(_ node: FileNode) {
        guard let root, node.isDirectory, node !== root else { rescan(); return }
        guard node.isAttached(to: root) else { return }
        let path: String
        switch FileIdentity.verify(node) {
        case .success(let url): path = url.path
        case .failure(let why):
            showToast("Can't rescan \(node.name): \(why.explanation). Try a full rescan (⌘R).")
            return
        }
        let generation = scanGeneration
        let name = node.name
        showToast("Re-reading \(name)…")
        DispatchQueue.global(qos: .userInitiated).async {
            let scanner = DiskScanner()
            let fresh = scanner.scan(path: path, rootName: name)
            let freshLinks = scanner.hardLinks
            let partial = scanner.snapshot.unreadable
            DispatchQueue.main.async {
                self.applyRescan(fresh, links: freshLinks, partial: partial, replacing: node, generation: generation)
            }
        }
    }

    private func applyRescan(_ fresh: FileNode?, links: [HardLinkEntry], partial: Int, replacing node: FileNode, generation: Int) {
        guard generation == scanGeneration, let root else { return }
        guard let fresh else {
            showToast("\(node.name) seems to have vanished. A full rescan (⌘R) will catch up.")
            return
        }
        let oldUnreadable = TreeEdit.unreadableCount(in: node)
        switch TreeEdit.splice(fresh, freshLinks: links, replacing: node, root: root, links: hardLinks) {
        case .staleTarget:
            return // the folder left the tree while we were reading it; nothing to update
        case .unreadable:
            showToast("Couldn't read \(node.name) this time, so I kept the previous numbers.")
            return
        case .spliced:
            break
        }
        unreadableCount += TreeEdit.unreadableCount(in: fresh) - oldUnreadable
        if let v = viewRoot, v.isDescendant(of: node) { viewRoot = fresh }
        if let s = selection, s.isDescendant(of: node) { selection = fresh }
        if let h = hover.node, h.isDescendant(of: node) { hover.node = nil }
        refreshAfterMutation()
        if partial > 0 {
            showToast("Re-read \(fresh.name), but \(partial) folder\(partial == 1 ? "" : "s") inside kept their secrets")
        } else {
            showToast("Fresh as a daisy: \(fresh.name) is \(Format.bytes(fresh.size))")
        }
    }

    private func refreshAfterMutation() {
        if let root {
            extensionStats = ExtensionStats.compute(root: root)
            if extensionColors.count < ExtensionRegistry.shared.count { assignColors() }
        }
        treeVersion += 1
    }

    // MARK: - Navigation

    /// Ignores nodes that have left the tree (e.g. clicked just as they were trashed).
    private func isLive(_ node: FileNode) -> Bool {
        guard let root else { return false }
        return node.isAttached(to: root)
    }

    func select(_ node: FileNode?) {
        guard selection !== node else { return }
        if let node, !isLive(node) { return }
        selection = node
    }

    func zoom(into node: FileNode) {
        let target = node.isDirectory ? node : (node.parent ?? node)
        guard target.isDirectory, target !== viewRoot, isLive(target) else { return }
        viewRoot = target
    }

    func zoomOut() {
        guard let parent = viewRoot?.parent else { return }
        viewRoot = parent
    }

    func zoomToRoot() {
        viewRoot = root
    }

    var canZoomOut: Bool { viewRoot?.parent != nil }

    // MARK: - File actions

    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func open(_ node: FileNode) {
        NSWorkspace.shared.open(node.url)
    }

    func copyPath(_ node: FileNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
        showToast("Path copied to the clipboard")
    }

    func moveToTrash(_ node: FileNode) {
        guard let root, let parent = node.parent else {
            showToast("Let's not trash the whole thing.")
            return
        }
        guard node.isAttached(to: root) else { return }
        let alert = NSAlert()
        alert.messageText = "Move “\(node.name)” to the Trash?"
        alert.informativeText = "Once you empty the Trash, that frees up about \(Format.bytes(node.size))"
            + (node.isDirectory ? " across \(Format.count(node.fileCount)) files." : ".")
            + " Until then you can still put it back."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Keep It")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Re-check right before touching the disk: the path must still lead to the object we scanned.
        let url: URL
        switch FileIdentity.verify(node) {
        case .success(let verified): url = verified
        case .failure(let why):
            showToast("Left \(node.name) alone: \(why.explanation). Rescan (⌘R) to refresh.")
            return
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            showToast("Couldn't trash it: \(error.localizedDescription)")
            return
        }

        if let v = viewRoot, v.isDescendant(of: node) { viewRoot = parent }
        if let s = selection, s.isDescendant(of: node) { selection = parent }
        if let h = hover.node, h.isDescendant(of: node) { hover.node = nil }
        unreadableCount -= TreeEdit.unreadableCount(in: node)
        TreeEdit.remove(node, root: root, links: hardLinks)
        refreshAfterMutation()
        showToast("Moved \(node.name) to the Trash. Empty it to reclaim \(Format.bytes(node.size)) ✦")
    }

    func showToast(_ text: String) {
        toastWork?.cancel()
        withAnimation(.spring(duration: 0.35)) { toast = text }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }

    // MARK: - Context menu shared by tree and treemap

    func contextMenu(for node: FileNode) -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ symbol: String, _ action: @escaping () -> Void) {
            let mi = ClosureMenuItem(title: title, action: action)
            mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(mi)
        }
        if node.isDirectory {
            item("Zoom Into Folder", "plus.magnifyingglass") { [weak self] in self?.zoom(into: node) }
        }
        item("Reveal in Finder", "folder") { [weak self] in self?.revealInFinder(node) }
        item("Open", "arrow.up.forward.app") { [weak self] in self?.open(node) }
        item("Copy Path", "doc.on.doc") { [weak self] in self?.copyPath(node) }
        if node.isDirectory {
            item("Rescan This Folder", "arrow.clockwise") { [weak self] in self?.rescan(node) }
        }
        menu.addItem(.separator())
        item("Move to Trash…", "trash") { [weak self] in self?.moveToTrash(node) }
        return menu
    }
}

/// NSMenuItem that runs a closure — keeps the context menus tiny.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
