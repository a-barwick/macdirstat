import Foundation

/// One entry in the scanned file tree. Directories aggregate the totals of their subtree.
///
/// Nodes are built concurrently by `DiskScanner` (each directory node is only ever written by the
/// worker that scans it), then handed to the main thread, which is the only place they're mutated afterwards.
final class FileNode {
    enum Kind: UInt8 {
        case directory
        case file
        case symlink
        case other
    }

    let name: String
    weak var parent: FileNode?
    var children: [FileNode] = []

    /// Bytes allocated on disk (what actually costs you space).
    var size: Int64 = 0
    /// Logical file length.
    var logicalSize: Int64 = 0
    /// Number of files (non-directories) in this subtree. 1 for a file.
    var fileCount: Int = 0
    /// Number of directories below this node.
    var dirCount: Int = 0
    /// Last modification, seconds since 1970. For directories: newest in the subtree.
    var modified: Int = 0
    let kind: Kind
    /// Inode number at scan time; used to make sure we act on the same object later.
    var fileID: UInt64 = 0
    var extID: UInt16 = 0
    /// Couldn't list this directory (permissions, usually).
    var unreadable = false

    init(name: String, kind: Kind, parent: FileNode?) {
        self.name = name
        self.kind = kind
        self.parent = parent
    }

    var isDirectory: Bool { kind == .directory }

    /// Total items shown in the "Items" column.
    var itemCount: Int { isDirectory ? fileCount + dirCount : 1 }

    /// Absolute path. The root node's name is its full path.
    var path: String {
        var parts: [String] = []
        var node: FileNode? = self
        while let n = node {
            parts.append(n.name)
            node = n.parent
        }
        parts.reverse()
        guard var result = parts.first else { return "/" }
        for part in parts.dropFirst() {
            if !result.hasSuffix("/") { result += "/" }
            result += part
        }
        return result
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }

    var isRoot: Bool { parent == nil }

    var displayName: String {
        guard parent == nil else { return name }
        if name == "/" { return "Macintosh HD" }
        if name == NSHomeDirectory() { return "Home (\((name as NSString).lastPathComponent))" }
        return (name as NSString).lastPathComponent
    }

    var depth: Int {
        var d = 0
        var node = parent
        while let n = node { d += 1; node = n.parent }
        return d
    }

    func isDescendant(of other: FileNode) -> Bool {
        var node: FileNode? = self
        while let n = node {
            if n === other { return true }
            node = n.parent
        }
        return false
    }

    /// Chain from the root down to (and including) this node.
    var ancestry: [FileNode] {
        var chain: [FileNode] = []
        var node: FileNode? = self
        while let n = node { chain.append(n); node = n.parent }
        return chain.reversed()
    }

    /// True if this node is still part of the tree rooted at `root`: every link on the way up is a
    /// real parent→child membership, not a stale back-pointer.
    func isAttached(to root: FileNode) -> Bool {
        var node = self
        while node !== root {
            guard let p = node.parent, p.children.contains(where: { $0 === node }) else { return false }
            node = p
        }
        return true
    }

    /// Detaches `child` (clearing its parent link) and subtracts its totals from every ancestor.
    func removeChild(_ child: FileNode) {
        guard let idx = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: idx)
        child.parent = nil
        let removedDirs = child.isDirectory ? child.dirCount + 1 : 0
        propagate(size: -child.size, logical: -child.logicalSize, files: -child.fileCount, dirs: -removedDirs)
    }

    /// Swaps `old` for `new` (e.g. after rescanning a subtree), detaching `old`, and fixes up ancestor totals.
    func replaceChild(_ old: FileNode, with new: FileNode) {
        guard let idx = children.firstIndex(where: { $0 === old }) else { return }
        children[idx] = new
        old.parent = nil
        new.parent = self
        children.sort { $0.size > $1.size }
        propagate(size: new.size - old.size, logical: new.logicalSize - old.logicalSize,
                  files: new.fileCount - old.fileCount, dirs: new.dirCount - old.dirCount)
    }

    /// Changes this file's allocated size (hard-link reconciliation) and fixes up ancestors.
    func adjustSize(by delta: Int64) {
        guard delta != 0 else { return }
        size += delta
        parent?.children.sort { $0.size > $1.size }
        parent?.propagate(size: delta, logical: 0, files: 0, dirs: 0)
    }

    /// Applies deltas to this node and every ancestor, re-sorting each level whose child changed size
    /// (the treemap layout relies on biggest-first order).
    private func propagate(size dSize: Int64, logical dLogical: Int64, files dFiles: Int, dirs dDirs: Int) {
        var node: FileNode? = self
        while let n = node {
            n.size += dSize
            n.logicalSize += dLogical
            n.fileCount += dFiles
            n.dirCount += dDirs
            if let p = n.parent, dSize != 0 { p.children.sort { $0.size > $1.size } }
            node = n.parent
        }
    }
}

// Safe by convention (see the type's doc comment): workers only write nodes they own during a scan,
// and after the hand-off every read and write happens on the main thread.
extension FileNode: @unchecked Sendable {}

extension FileNode: Hashable {
    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
