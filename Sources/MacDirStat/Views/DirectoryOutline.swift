import AppKit
import SwiftUI

/// The directory tree. NSOutlineView rather than SwiftUI's List so folders with 100k entries stay snappy.
struct DirectoryOutline: NSViewRepresentable {
    @ObservedObject var state: AppState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = SketchOutlineView()
        outline.headerView = NSTableHeaderView()
        outline.usesAlternatingRowBackgroundColors = false
        outline.rowHeight = 24
        outline.intercellSpacing = NSSize(width: 6, height: 0)
        outline.indentationPerLevel = 14
        outline.autoresizesOutlineColumn = false
        outline.allowsMultipleSelection = false
        outline.style = .fullWidth
        outline.gridStyleMask = []
        outline.focusRingType = .none
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        func column(_ id: Coordinator.Column, _ title: String, width: CGFloat, min: CGFloat, sort: String?, ascending: Bool = false) {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id.rawValue))
            c.title = title
            c.width = width
            c.minWidth = min
            if let sort { c.sortDescriptorPrototype = NSSortDescriptor(key: sort, ascending: ascending) }
            outline.addTableColumn(c)
        }
        column(.name, "Name", width: 300, min: 140, sort: "name", ascending: true)
        column(.share, "Share", width: 120, min: 60, sort: "size")
        column(.percent, "%", width: 54, min: 44, sort: "size")
        column(.size, "Size", width: 82, min: 64, sort: "size")
        column(.items, "Items", width: 70, min: 50, sort: "items")
        column(.modified, "Last Change", width: 104, min: 70, sort: "modified")
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]

        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked(_:))
        outline.menuProvider = { [weak coordinator = context.coordinator] row in coordinator?.menu(forRow: row) }
        outline.onDelete = { [weak coordinator = context.coordinator] in coordinator?.trashSelection() }
        context.coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.state = state
        context.coordinator.sync(scroll: scroll)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        enum Column: String {
            case name, share, percent, size, items, modified
        }

        var state: AppState
        weak var outline: SketchOutlineView?

        private var lastRoot: FileNode?
        private var lastVersion = -1
        private var lastTheme = ""
        private var sortKey = AppState.SortKey.size
        private var ascending = false
        private var sortedCache: [ObjectIdentifier: [FileNode]] = [:]
        private var syncingSelection = false

        init(state: AppState) { self.state = state }

        func sync(scroll: NSScrollView) {
            guard let outline else { return }
            let theme = state.theme
            if theme.id != lastTheme {
                lastTheme = theme.id
                outline.theme = theme
                outline.backgroundColor = theme.paper.nsColor
                scroll.backgroundColor = theme.paper.nsColor
                outline.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
                scroll.appearance = outline.appearance
                reloadPreservingExpansion()
            }

            if state.root !== lastRoot {
                lastRoot = state.root
                lastVersion = state.treeVersion
                sortedCache.removeAll()
                outline.reloadData()
                if let root = state.root {
                    outline.expandItem(root)
                    // Pop open the biggest folder too, as a friendly start.
                    if let first = root.children.first, first.isDirectory { outline.expandItem(first) }
                }
            } else if state.treeVersion != lastVersion {
                lastVersion = state.treeVersion
                sortedCache.removeAll()
                reloadPreservingExpansion()
            }

            if let sel = state.selection {
                let row = outline.selectedRow
                let current = row >= 0 ? outline.item(atRow: row) as? FileNode : nil
                if current !== sel { reveal(sel) }
            } else if outline.selectedRow >= 0 {
                syncingSelection = true
                outline.deselectAll(nil)
                syncingSelection = false
            }
        }

        private func reloadPreservingExpansion() {
            guard let outline else { return }
            var expanded: [FileNode] = []
            for row in 0..<outline.numberOfRows {
                if let item = outline.item(atRow: row) as? FileNode, outline.isItemExpanded(item) {
                    expanded.append(item)
                }
            }
            let visible = outline.enclosingScrollView?.contentView.bounds.origin
            outline.reloadData()
            for item in expanded where state.root.map({ item.isDescendant(of: $0) }) == true {
                outline.expandItem(item)
            }
            if let visible { outline.scroll(visible) }
            if let sel = state.selection { reveal(sel, scroll: false) }
        }

        private func reveal(_ node: FileNode, scroll: Bool = true) {
            guard let outline else { return }
            for ancestor in node.ancestry.dropLast() {
                outline.expandItem(ancestor)
            }
            let row = outline.row(forItem: node)
            guard row >= 0 else { return }
            syncingSelection = true
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            syncingSelection = false
            if scroll {
                // Defer until expansion has settled the row geometry.
                DispatchQueue.main.async { [weak outline] in
                    guard let outline, outline.row(forItem: node) == row else { return }
                    outline.scrollRowToVisible(row)
                }
            }
        }

        private func children(of node: FileNode) -> [FileNode] {
            if sortKey == .size && !ascending { return node.children }
            let key = ObjectIdentifier(node)
            if let cached = sortedCache[key] { return cached }
            let asc = ascending
            let sorted: [FileNode]
            switch sortKey {
            case .size: sorted = node.children.sorted { asc ? $0.size < $1.size : $0.size > $1.size }
            case .name: sorted = node.children.sorted {
                let r = $0.name.localizedStandardCompare($1.name)
                return asc ? r == .orderedAscending : r == .orderedDescending
            }
            case .items: sorted = node.children.sorted { asc ? $0.itemCount < $1.itemCount : $0.itemCount > $1.itemCount }
            case .modified: sorted = node.children.sorted { asc ? $0.modified < $1.modified : $0.modified > $1.modified }
            }
            sortedCache[key] = sorted
            return sorted
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? FileNode else { return state.root == nil ? 0 : 1 }
            return node.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? FileNode else { return state.root! }
            return children(of: node)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? FileNode else { return false }
            return node.isDirectory && !node.children.isEmpty
        }

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let d = outlineView.sortDescriptors.first, let key = d.key.flatMap(AppState.SortKey.init(rawValue:)) else { return }
            sortKey = key
            ascending = d.ascending
            sortedCache.removeAll()
            reloadPreservingExpansion()
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let row = SketchRowView()
            row.theme = state.theme
            return row
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode, let tableColumn,
                  let column = Column(rawValue: tableColumn.identifier.rawValue) else { return nil }
            let theme = state.theme
            let parentSize = node.parent?.size ?? node.size

            switch column {
            case .name:
                let cell = outlineView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? NameCell ?? NameCell()
                cell.identifier = tableColumn.identifier
                cell.configure(node: node, theme: theme, extColor: state.color(for: node))
                return cell
            case .share:
                let cell = outlineView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? ShareBarCell ?? ShareBarCell()
                cell.identifier = tableColumn.identifier
                cell.configure(fraction: parentSize > 0 ? Double(node.size) / Double(parentSize) : 0,
                               depth: node.depth, seed: UInt64(UInt(bitPattern: ObjectIdentifier(node).hashValue)), theme: theme)
                return cell
            case .percent:
                return textCell(outlineView, tableColumn, Format.percent(node.size, of: parentSize), theme: theme, soft: true)
            case .size:
                return textCell(outlineView, tableColumn, Format.bytes(node.size), theme: theme, soft: false)
            case .items:
                return textCell(outlineView, tableColumn, node.isDirectory ? Format.count(node.itemCount) : "", theme: theme, soft: true)
            case .modified:
                return textCell(outlineView, tableColumn, Format.date(node.modified), theme: theme, soft: true)
            }
        }

        private func textCell(_ outlineView: NSOutlineView, _ column: NSTableColumn, _ text: String, theme: Theme, soft: Bool) -> NSView {
            let cell = outlineView.makeView(withIdentifier: column.identifier, owner: nil) as? TextCell ?? TextCell()
            cell.identifier = column.identifier
            cell.configure(text: text, color: (soft ? theme.inkSoft : theme.ink).nsColor)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !syncingSelection, let outline else { return }
            let row = outline.selectedRow
            let node = row >= 0 ? outline.item(atRow: row) as? FileNode : nil
            if node !== state.selection { state.select(node) }
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let outline, outline.clickedRow >= 0, let node = outline.item(atRow: outline.clickedRow) as? FileNode else { return }
            if node.isDirectory {
                state.zoom(into: node)
            } else {
                state.revealInFinder(node)
            }
        }

        func menu(forRow row: Int) -> NSMenu? {
            guard let outline, row >= 0, let node = outline.item(atRow: row) as? FileNode else { return nil }
            state.select(node)
            return state.contextMenu(for: node)
        }

        func trashSelection() {
            guard let sel = state.selection else { return }
            state.moveToTrash(sel)
        }
    }
}

// MARK: - Views

final class SketchOutlineView: NSOutlineView {
    var theme: Theme = .ivory
    var menuProvider: ((Int) -> NSMenu?)?
    var onDelete: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        return menuProvider?(row)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.keyCode == 51 { // ⌘⌫
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }

    override func drawBackground(inClipRect clipRect: NSRect) {
        theme.paper.nsColor.setFill()
        clipRect.fill()
    }
}

/// Selected rows get a soft clay wash with a pencil outline instead of system blue.
final class SketchRowView: NSTableRowView {
    var theme: Theme = .ivory

    override func drawSelection(in dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds.insetBy(dx: 4, dy: 2)
        ctx.setFillColor(theme.accent.cgColor.copy(alpha: theme.isDark ? 0.32 : 0.22)!)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(theme.accent.cgColor.copy(alpha: 0.9)!)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)
        ctx.addPath(Sketch.roughRect(r, roughness: 1.1, seed: UInt64(max(0, Int(frame.minY))), passes: 1))
        ctx.strokePath()
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

final class TextCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, color: NSColor) {
        label.stringValue = text
        label.textColor = color
    }
}

final class NameCell: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 12.5)
        addSubview(icon)
        addSubview(label)
        imageView = icon
        textField = label
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(node: FileNode, theme: Theme, extColor: RGB) {
        let symbol: String
        let tint: NSColor
        switch node.kind {
        case .directory:
            symbol = node.isRoot ? "internaldrive.fill" : (node.unreadable ? "lock.fill" : "folder.fill")
            tint = node.unreadable ? theme.inkSoft.nsColor : theme.accent.nsColor
        case .symlink:
            symbol = "arrowshape.turn.up.right.fill"
            tint = theme.inkSoft.nsColor
        default:
            symbol = "doc.fill"
            tint = extColor.nsColor
        }
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = tint
        label.stringValue = node.isRoot ? node.path : node.name
        label.textColor = theme.ink.nsColor
        label.font = node.isRoot ? .systemFont(ofSize: 12.5, weight: .semibold) : .systemFont(ofSize: 12.5)
        toolTip = node.unreadable ? "Couldn't peek inside — permission denied" : nil
    }
}

/// Hand-drawn progress-bar-ish share of the parent, hatched like a pencil sketch.
final class ShareBarCell: NSTableCellView {
    private var fraction = 0.0
    private var depth = 0
    private var seed: UInt64 = 0
    private var theme: Theme = .ivory

    private static let depthColors: [RGB] = [Palette.clay, Palette.olive, Palette.sky, Palette.kraft, Palette.fig]

    func configure(fraction: Double, depth: Int, seed: UInt64, theme: Theme) {
        self.fraction = max(0, min(1, fraction))
        self.depth = depth
        self.seed = seed
        self.theme = theme
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let track = bounds.insetBy(dx: 4, dy: 7)
        guard track.width > 6 else { return }
        let color = Self.depthColors[depth % Self.depthColors.count]

        ctx.setLineCap(.round)
        // Fill
        let fillW = max(fraction > 0 ? 2 : 0, track.width * fraction)
        if fillW > 0 {
            let fill = CGRect(x: track.minX, y: track.minY, width: fillW, height: track.height)
            ctx.setFillColor(color.cgColor.copy(alpha: 0.55)!)
            ctx.fill(fill.insetBy(dx: 0.5, dy: 0.5))
            if fill.width > 6 {
                ctx.saveGState()
                ctx.clip(to: fill)
                ctx.setStrokeColor(color.mixed(with: Palette.slate, 0.35).cgColor.copy(alpha: 0.75)!)
                ctx.setLineWidth(1)
                ctx.addPath(Sketch.hatch(fill, spacing: 3.5, roughness: 0.5, seed: seed))
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
        // Pencil outline
        ctx.setStrokeColor(theme.ink.cgColor.copy(alpha: 0.45)!)
        ctx.setLineWidth(0.9)
        ctx.addPath(Sketch.roughRect(track, roughness: 0.8, seed: seed, passes: 1))
        ctx.strokePath()
    }
}
