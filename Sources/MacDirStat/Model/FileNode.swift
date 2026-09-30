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

    /// Detaches `child` and subtracts its totals from every ancestor.
    func removeChild(_ child: FileNode) {
        guard let idx = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: idx)
        let removedDirs = child.isDirectory ? child.dirCount + 1 : 0
        var node: FileNode? = self
        while let n = node {
            n.size -= child.size
            n.logicalSize -= child.logicalSize
            n.fileCount -= child.fileCount
            n.dirCount -= removedDirs
            node = n.parent
        }
    }

    /// Swaps `old` for `new` (e.g. after rescanning a subtree) and fixes up ancestor totals.
    func replaceChild(_ old: FileNode, with new: FileNode) {
        guard let idx = children.firstIndex(where: { $0 === old }) else { return }
        children[idx] = new
        new.parent = self
        let dSize = new.size - old.size
        let dLogical = new.logicalSize - old.logicalSize
        let dFiles = new.fileCount - old.fileCount
        let dDirs = new.dirCount - old.dirCount
        var node: FileNode? = self
        while let n = node {
            n.size += dSize
            n.logicalSize += dLogical
            n.fileCount += dFiles
            n.dirCount += dDirs
            n.children.sort { $0.size > $1.size }
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
