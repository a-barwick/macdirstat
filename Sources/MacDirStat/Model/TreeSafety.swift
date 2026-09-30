import Darwin
import Foundation

struct HardLinkEntry {
    let fileID: UInt64
    /// The blocks this inode really occupies (recorded even for links that were counted as 0).
    let allocSize: Int64
    let node: FileNode
}

/// Remembers every link of every multiply-linked file so that, after trashing or rescanning part of
/// the tree, exactly one link that is still in the tree carries the file's allocation.
final class HardLinkRegistry {
    private struct Group {
        var allocSize: Int64
        var nodes: [FileNode]
    }

    private var groups: [UInt64: Group] = [:]

    init(_ entries: [HardLinkEntry] = []) {
        add(entries)
    }

    func add(_ entries: [HardLinkEntry]) {
        for e in entries {
            if groups[e.fileID] == nil {
                groups[e.fileID] = Group(allocSize: e.allocSize, nodes: [e.node])
            } else {
                groups[e.fileID]!.allocSize = e.allocSize // freshest measurement wins
                groups[e.fileID]!.nodes.append(e.node)
            }
        }
    }

    /// IDs of the hard-linked files inside `subtree`.
    func ids(in subtree: FileNode) -> Set<UInt64> {
        guard !groups.isEmpty else { return [] }
        var ids = Set<UInt64>()
        var stack = [subtree]
        while let n = stack.popLast() {
            if n.isDirectory {
                stack.append(contentsOf: n.children)
            } else if groups[n.fileID] != nil {
                ids.insert(n.fileID)
            }
        }
        return ids
    }

    /// Drops links that left the tree and makes sure exactly one remaining link pays for the blocks.
    func reconcile(_ ids: Set<UInt64>, root: FileNode) {
        for id in ids {
            guard var group = groups[id] else { continue }
            group.nodes.removeAll { !$0.isAttached(to: root) }
            guard let first = group.nodes.first else {
                groups[id] = nil
                continue
            }
            groups[id] = group
            var owner: FileNode?
            for node in group.nodes where node.size > 0 {
                if owner == nil { owner = node } else { node.adjustSize(by: -node.size) }
            }
            if let owner {
                owner.adjustSize(by: group.allocSize - owner.size)
            } else {
                first.adjustSize(by: group.allocSize)
            }
        }
    }
}

/// Makes sure a node's path still leads to the object we scanned before anything touches the disk.
enum FileIdentity {
    enum Failure: Error, Equatable {
        case unknownIdentity
        case missing
        case pathRedirected
        case replaced

        var explanation: String {
            switch self {
            case .unknownIdentity: return "we don't know enough about it to act safely"
            case .missing: return "it isn't there any more"
            case .pathRedirected: return "a folder on its path was moved or swapped for a link since the scan"
            case .replaced: return "a different item now sits at that path"
            }
        }
    }

    /// Returns the URL to act on, or why it isn't safe. The scan root is symlink-free (see
    /// `DiskScanner.realPath`), so a stored path whose parent no longer resolves to itself means an
    /// ancestor was replaced; and the inode must match what the scanner saw.
    static func verify(_ node: FileNode) -> Result<URL, Failure> {
        guard node.fileID != 0 else { return .failure(.unknownIdentity) }
        let path = node.path
        let parentPath = (path as NSString).deletingLastPathComponent
        let directoryToCheck = node.parent == nil ? path : parentPath
        guard let resolved = DiskScanner.realPath(directoryToCheck) else { return .failure(.missing) }
        guard resolved == directoryToCheck else { return .failure(.pathRedirected) }

        var st = stat()
        guard lstat(path, &st) == 0 else { return .failure(.missing) }
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        guard UInt64(st.st_ino) == node.fileID, isDir == node.isDirectory else { return .failure(.replaced) }
        return .success(URL(fileURLWithPath: path, isDirectory: isDir))
    }
}

/// Tree edits that keep totals, ordering and hard-link ownership consistent. UI-free so it can be tested.
enum TreeEdit {
    enum SpliceOutcome: Equatable {
        case spliced
        case staleTarget      // the node left the tree (or the tree was replaced) while we were scanning
        case unreadable       // couldn't list the folder at all; keep what we had
    }

    /// Removes `node` from the tree under `root`. Returns false if it isn't attached any more.
    @discardableResult
    static func remove(_ node: FileNode, root: FileNode, links: HardLinkRegistry) -> Bool {
        guard node !== root, let parent = node.parent, node.isAttached(to: root) else { return false }
        let affected = links.ids(in: node)
        parent.removeChild(node)
        links.reconcile(affected, root: root)
        return true
    }

    /// Replaces `old` with a freshly scanned subtree (whose root must already carry `old.name`).
    static func splice(_ fresh: FileNode, freshLinks: [HardLinkEntry], replacing old: FileNode,
                       root: FileNode, links: HardLinkRegistry) -> SpliceOutcome {
        guard let parent = old.parent, old.isAttached(to: root) else { return .staleTarget }
        if fresh.unreadable && fresh.children.isEmpty { return .unreadable }
        let affected = links.ids(in: old).union(freshLinks.map(\.fileID))
        parent.replaceChild(old, with: fresh)
        links.add(freshLinks)
        links.reconcile(affected, root: root)
        return .spliced
    }

    static func unreadableCount(in subtree: FileNode) -> Int {
        var count = 0
        var stack = [subtree]
        while let n = stack.popLast() {
            guard n.isDirectory else { continue }
            if n.unreadable { count += 1 }
            stack.append(contentsOf: n.children.lazy.filter(\.isDirectory))
        }
        return count
    }
}
