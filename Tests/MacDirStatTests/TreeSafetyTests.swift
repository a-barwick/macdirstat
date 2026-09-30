import Darwin
import Foundation
import Testing
@testable import MacDirStat

// MARK: - Helpers

/// A scratch directory that cleans up after itself (restoring permissions first).
final class Fixture {
    let root: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("macdirstat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = DiskScanner.realPath(base.path)!
    }

    deinit {
        _ = try? FileManager.default.subpathsOfDirectory(atPath: root).forEach {
            chmod(root + "/" + $0, 0o755)
        }
        try? FileManager.default.removeItem(atPath: root)
    }

    func dir(_ rel: String) throws {
        try FileManager.default.createDirectory(atPath: root + "/" + rel, withIntermediateDirectories: true)
    }

    func file(_ rel: String, bytes: Int) throws {
        try Data(repeating: 7, count: bytes).write(to: URL(fileURLWithPath: root + "/" + rel))
    }

    func allocated(_ rel: String) -> Int64 {
        var st = stat()
        lstat(root + "/" + rel, &st)
        return Int64(st.st_blocks) * 512
    }
}

func file(_ name: String, _ size: Int64, in parent: FileNode) -> FileNode {
    let n = FileNode(name: name, kind: .file, parent: parent)
    n.size = size
    n.fileCount = 1
    parent.children.append(n)
    return n
}

func dir(_ name: String, in parent: FileNode?) -> FileNode {
    let n = FileNode(name: name, kind: .directory, parent: parent)
    parent?.children.append(n)
    return n
}

func child(_ node: FileNode, _ name: String) -> FileNode { node.children.first { $0.name == name }! }

// MARK: - Tree edits

@Test func removalKeepsChildrenSortedSoTheMapStillDrawsThem() {
    // [A:100, B:90] → trash A's only file → A:0 must sort after B.
    let root = dir("/r", in: nil)
    let a = dir("A", in: root)
    let b = dir("B", in: root)
    let big = file("big", 100, in: a)
    _ = file("keep", 90, in: b)
    DiskScanner.finalize(root)

    #expect(TreeEdit.remove(big, root: root, links: HardLinkRegistry()))
    #expect(root.size == 90)
    #expect(root.children.map(\.name) == ["B", "A"])

    let layout = TreemapLayout.build(root: root, pixelWidth: 200, pixelHeight: 100, scale: 1, style: .sketch) { _ in Palette.clay }
    #expect(layout.leaves.contains { $0.isFile })
}

@Test func removedNodesAreDetachedAndStaleRescansAreRejected() {
    let root = dir("/r", in: nil)
    let sub = dir("sub", in: root)
    let inner = dir("inner", in: sub)
    _ = file("x", 30, in: inner)
    _ = file("y", 10, in: sub)
    _ = file("z", 60, in: root)
    DiskScanner.finalize(root)
    #expect(root.size == 100)

    #expect(TreeEdit.remove(sub, root: root, links: HardLinkRegistry()))
    #expect(root.size == 60)
    #expect(sub.parent == nil)
    #expect(!inner.isAttached(to: root))

    // A rescan of `inner` that finishes late must not touch the live tree.
    let fresh = dir("inner", in: nil)
    _ = file("x", 40, in: fresh)
    DiskScanner.finalize(fresh)
    let result = TreeEdit.splice(fresh, freshLinks: [], replacing: inner, root: root, links: HardLinkRegistry())
    #expect(result == .staleTarget)
    #expect(root.size == 60)
}

// MARK: - Scanner on real files

@Test func scannerTotalsMatchAllocatedBytes() throws {
    let fx = try Fixture()
    try fx.dir("a/b")
    try fx.file("a/one.bin", bytes: 10_000)
    try fx.file("a/b/two.txt", bytes: 70_000)
    try fx.file("three", bytes: 1)

    let root = try #require(DiskScanner().scan(path: fx.root))
    #expect(root.size == fx.allocated("a/one.bin") + fx.allocated("a/b/two.txt") + fx.allocated("three"))
    #expect(root.fileCount == 3)
    #expect(root.dirCount == 2)
    #expect(root.fileID != 0 && child(root, "a").fileID != 0)
}

@Test func hardLinksStayCountedOnceAcrossRescanAndRemoval() throws {
    let fx = try Fixture()
    try fx.dir("a")
    try fx.dir("b")
    try fx.file("a/data", bytes: 65_536)
    #expect(link(fx.root + "/a/data", fx.root + "/b/data") == 0)
    let alloc = fx.allocated("a/data")

    let scanner = DiskScanner()
    let root = try #require(scanner.scan(path: fx.root))
    let links = HardLinkRegistry(scanner.hardLinks)
    #expect(root.size == alloc)

    // Rescan whichever folder does *not* own the blocks: total must not double.
    let owner = [child(root, "a"), child(root, "b")].first { $0.size > 0 }!
    let other = owner === child(root, "a") ? child(root, "b") : child(root, "a")
    let rescanner = DiskScanner()
    let fresh = try #require(rescanner.scan(path: other.path, rootName: other.name))
    #expect(TreeEdit.splice(fresh, freshLinks: rescanner.hardLinks, replacing: other, root: root, links: links) == .spliced)
    #expect(root.size == alloc)

    // Remove the owning link: the surviving link must pick up the blocks.
    #expect(TreeEdit.remove(owner, root: root, links: links))
    #expect(root.size == alloc)
    #expect(child(root, fresh.name).size == alloc)
}

@Test func unreadableRescanKeepsPreviousResults() throws {
    let fx = try Fixture()
    try fx.dir("locked")
    try fx.file("locked/f", bytes: 20_000)
    let root = try #require(DiskScanner().scan(path: fx.root))
    let locked = child(root, "locked")
    let before = root.size
    #expect(before > 0)

    chmod(fx.root + "/locked", 0)
    defer { chmod(fx.root + "/locked", 0o755) }
    guard geteuid() != 0 else { return } // root ignores permissions

    let scanner = DiskScanner()
    let fresh = try #require(scanner.scan(path: locked.path, rootName: locked.name))
    #expect(fresh.unreadable)
    #expect(TreeEdit.splice(fresh, freshLinks: [], replacing: locked, root: root, links: HardLinkRegistry()) == .unreadable)
    #expect(root.size == before)
    #expect(child(root, "locked") === locked)
}

@Test func cancelledScanStopsAndReturnsNothing() throws {
    let fx = try Fixture()
    try fx.dir("many")
    for i in 0..<2_000 { try fx.file("many/f\(i)", bytes: 1) }
    let scanner = DiskScanner()
    scanner.cancel()
    #expect(scanner.scan(path: fx.root) == nil)
    #expect(scanner.snapshot.files == 0) // never walked the big directory
}

// MARK: - Identity checks before touching the disk

@Test func identityAcceptsTheScannedObject() throws {
    let fx = try Fixture()
    try fx.dir("keep")
    try fx.file("keep/f", bytes: 10)
    let root = try #require(DiskScanner().scan(path: fx.root))
    let f = child(child(root, "keep"), "f")
    #expect(try FileIdentity.verify(f).get().path == fx.root + "/keep/f")
}

@Test func identityRejectsASymlinkedAncestor() throws {
    let fx = try Fixture()
    try fx.dir("scanned")
    try fx.file("scanned/f", bytes: 10)
    try fx.dir("elsewhere")
    try fx.file("elsewhere/f", bytes: 10)
    let root = try #require(DiskScanner().scan(path: fx.root))
    let f = child(child(root, "scanned"), "f")

    // Swap the scanned folder for a link pointing somewhere else.
    try FileManager.default.moveItem(atPath: fx.root + "/scanned", toPath: fx.root + "/moved")
    #expect(symlink(fx.root + "/elsewhere", fx.root + "/scanned") == 0)

    #expect(FileIdentity.verify(f) == .failure(.pathRedirected))
}

@Test func identityRejectsASameNameReplacement() throws {
    let fx = try Fixture()
    try fx.file("f", bytes: 10)
    let root = try #require(DiskScanner().scan(path: fx.root))
    let f = child(root, "f")

    try FileManager.default.removeItem(atPath: fx.root + "/f")
    try fx.file("spacer", bytes: 1) // make inode reuse unlikely
    try fx.file("f", bytes: 10)

    #expect(FileIdentity.verify(f) == .failure(.replaced))
}

// MARK: - Rendering

@Test func cancelledRenderBailsOutImmediately() {
    let leaf = TreemapLayout.Leaf(x0: 0, y0: 0, x1: 4000, y1: 2000, color: Palette.clay, surface: Surface(), extID: 0, isFile: true)
    let job = TreemapRenderJob(width: 4000, height: 2000, scale: 1, style: .cushion, leaves: [leaf], outlines: [], labels: [],
                               background: Palette.oat, ink: Palette.slate, tagPaper: Palette.ivory, isDark: false)
    let token = RenderToken()
    token.cancel()
    let start = Date()
    #expect(TreemapRenderer.render(job, isCancelled: token.isCancelled) == nil)
    #expect(Date().timeIntervalSince(start) < 0.01)
}
