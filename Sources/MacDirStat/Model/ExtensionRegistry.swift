import Foundation

/// Interns file extensions into small integer IDs so every file node only carries a UInt16.
final class ExtensionRegistry: @unchecked Sendable {
    static let shared = ExtensionRegistry()

    private let lock = NSLock()
    private var names: [String] = [""]
    private var ids: [String: UInt16] = ["": 0]

    func id(for ext: String) -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        if let id = ids[ext] { return id }
        guard names.count < Int(UInt16.max) else { return 0 }
        let id = UInt16(names.count)
        names.append(ext)
        ids[ext] = id
        return id
    }

    func name(for id: UInt16) -> String {
        lock.lock()
        defer { lock.unlock() }
        return Int(id) < names.count ? names[Int(id)] : ""
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return names.count
    }

    /// Lowercased extension of a file name, or "" when there isn't a sensible one.
    static func extensionString(of name: String) -> String {
        let utf8 = name.utf8
        guard let dot = utf8.lastIndex(of: UInt8(ascii: ".")), dot != utf8.startIndex else { return "" }
        let extStart = utf8.index(after: dot)
        let length = utf8.distance(from: extStart, to: utf8.endIndex)
        guard length > 0, length <= 12 else { return "" }
        return String(name[extStart...]).lowercased()
    }
}

struct ExtensionStat: Identifiable {
    let id: UInt16
    let name: String
    var bytes: Int64
    var count: Int

    var label: String { name.isEmpty ? "(no extension)" : ".\(name)" }
}

enum ExtensionStats {
    /// Walks a tree and totals bytes/files per extension, biggest first.
    static func compute(root: FileNode) -> [ExtensionStat] {
        var bytes: [Int64] = Array(repeating: 0, count: ExtensionRegistry.shared.count)
        var counts: [Int] = Array(repeating: 0, count: bytes.count)
        var stack: [FileNode] = [root]
        while let node = stack.popLast() {
            if node.isDirectory {
                stack.append(contentsOf: node.children)
            } else {
                let i = Int(node.extID)
                if i >= bytes.count {
                    bytes.append(contentsOf: repeatElement(0, count: i - bytes.count + 1))
                    counts.append(contentsOf: repeatElement(0, count: i - counts.count + 1))
                }
                bytes[i] += node.size
                counts[i] += 1
            }
        }
        var stats: [ExtensionStat] = []
        for i in bytes.indices where counts[i] > 0 {
            let id = UInt16(i)
            stats.append(ExtensionStat(id: id, name: ExtensionRegistry.shared.name(for: id), bytes: bytes[i], count: counts[i]))
        }
        stats.sort { $0.bytes > $1.bytes }
        return stats
    }
}
