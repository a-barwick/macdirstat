import Darwin
import Foundation

/// Fast, parallel directory scanner built on `getattrlistbulk(2)`, which returns names, types and
/// sizes for a whole directory in a handful of syscalls instead of one `lstat` per entry.
///
/// A fixed pool of workers pulls directories off a shared LIFO stack (depth-first keeps memory low),
/// so a lopsided tree still spreads across every core.
final class DiskScanner: @unchecked Sendable {
    struct Snapshot {
        var files = 0
        var dirs = 0
        var bytes: Int64 = 0
        var unreadable = 0
        var currentPath = ""
    }

    /// Paths never descended into when they're encountered inside a scan (volume mounts,
    /// the Data-volume mirror that would double count everything, virtual filesystems).
    static let defaultSkipPaths: Set<String> = [
        "/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/.vol", "/.nofollow", "/.resolve",
    ]

    private let cond = NSCondition()
    private var stack: [(FileNode, String)] = []
    private var pending = 0
    private var cancelled = false
    private var snap = Snapshot()

    private let inodeLock = NSLock()
    private var seenHardLinks = Set<UInt64>()

    private let skipPaths: Set<String>
    private let registry = ExtensionRegistry.shared

    init(skipPaths: Set<String> = DiskScanner.defaultSkipPaths) {
        self.skipPaths = skipPaths
    }

    var snapshot: Snapshot {
        cond.lock()
        defer { cond.unlock() }
        return snap
    }

    var isCancelled: Bool {
        cond.lock()
        defer { cond.unlock() }
        return cancelled
    }

    func cancel() {
        cond.lock()
        cancelled = true
        cond.broadcast()
        cond.unlock()
    }

    /// Scans `path` synchronously (call it off the main thread). Returns nil if cancelled or unreadable.
    func scan(path rawPath: String) -> FileNode? {
        let path = rawPath.count > 1 && rawPath.hasSuffix("/") ? String(rawPath.dropLast()) : rawPath
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }

        guard (st.st_mode & S_IFMT) == S_IFDIR else {
            let node = FileNode(name: path, kind: .file, parent: nil)
            node.size = Int64(st.st_blocks) * 512
            node.logicalSize = Int64(st.st_size)
            node.fileCount = 1
            node.modified = st.st_mtimespec.tv_sec
            node.extID = registry.id(for: ExtensionRegistry.extensionString(of: path))
            return node
        }

        let root = FileNode(name: path, kind: .directory, parent: nil)
        root.modified = st.st_mtimespec.tv_sec

        cond.lock()
        stack = [(root, path)]
        pending = 1
        cond.unlock()

        let workerCount = max(4, min(24, ProcessInfo.processInfo.activeProcessorCount * 2))
        let group = DispatchGroup()
        for _ in 0..<workerCount {
            group.enter()
            let thread = Thread { [self] in
                workerLoop()
                group.leave()
            }
            thread.stackSize = 1 << 20
            thread.qualityOfService = .userInitiated
            thread.start()
        }
        group.wait()

        if isCancelled { return nil }
        DiskScanner.finalize(root)
        return root
    }

    // MARK: - Workers

    private struct LocalCounts {
        var files = 0
        var dirs = 0
        var bytes: Int64 = 0
        var unreadable = 0
    }

    private func workerLoop() {
        let bufferSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        var extCache: [String: UInt16] = [:]

        while true {
            cond.lock()
            while stack.isEmpty && pending > 0 && !cancelled {
                cond.wait()
            }
            if cancelled || stack.isEmpty {
                cond.unlock()
                return
            }
            let (node, path) = stack.removeLast()
            snap.currentPath = path
            cond.unlock()

            var counts = LocalCounts()
            let subdirs = scanDirectory(node, path: path, buffer: buffer, bufferSize: bufferSize,
                                        extCache: &extCache, counts: &counts)

            cond.lock()
            stack.append(contentsOf: subdirs)
            pending += subdirs.count - 1
            snap.files += counts.files
            snap.dirs += counts.dirs
            snap.bytes += counts.bytes
            snap.unreadable += counts.unreadable
            if pending == 0 || !subdirs.isEmpty { cond.broadcast() }
            cond.unlock()
        }
    }

    // Attribute bits (sys/attr.h), spelled out to avoid C-macro type juggling.
    private static let ATTR_CMN_NAME: UInt32 = 0x0000_0001
    private static let ATTR_CMN_OBJTYPE: UInt32 = 0x0000_0008
    private static let ATTR_CMN_MODTIME: UInt32 = 0x0000_0400
    private static let ATTR_CMN_FILEID: UInt32 = 0x0200_0000
    private static let ATTR_CMN_ERROR: UInt32 = 0x2000_0000
    private static let ATTR_CMN_RETURNED_ATTRS: UInt32 = 0x8000_0000
    private static let ATTR_FILE_LINKCOUNT: UInt32 = 0x0000_0001
    private static let ATTR_FILE_TOTALSIZE: UInt32 = 0x0000_0002
    private static let ATTR_FILE_ALLOCSIZE: UInt32 = 0x0000_0004

    private static let VREG: UInt32 = 1
    private static let VDIR: UInt32 = 2
    private static let VLNK: UInt32 = 5

    private func scanDirectory(_ node: FileNode, path: String,
                               buffer: UnsafeMutableRawPointer, bufferSize: Int,
                               extCache: inout [String: UInt16],
                               counts: inout LocalCounts) -> [(FileNode, String)] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            node.unreadable = true
            counts.unreadable += 1
            return []
        }
        defer { close(fd) }

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = Self.ATTR_CMN_RETURNED_ATTRS | Self.ATTR_CMN_NAME | Self.ATTR_CMN_ERROR
            | Self.ATTR_CMN_OBJTYPE | Self.ATTR_CMN_MODTIME | Self.ATTR_CMN_FILEID
        attrs.fileattr = Self.ATTR_FILE_LINKCOUNT | Self.ATTR_FILE_TOTALSIZE | Self.ATTR_FILE_ALLOCSIZE

        var kids: [FileNode] = []
        var subdirs: [(FileNode, String)] = []
        let prefix = path == "/" ? "/" : path + "/"

        while true {
            let count = getattrlistbulk(fd, &attrs, buffer, bufferSize, 0)
            if count <= 0 {
                if count < 0 && kids.isEmpty {
                    node.unreadable = true
                    counts.unreadable += 1
                }
                break
            }

            var entry = buffer
            for _ in 0..<Int(count) {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                defer { entry += length }
                var p = entry + 4

                let returned = p.loadUnaligned(as: attribute_set_t.self)
                p += MemoryLayout<attribute_set_t>.size

                if returned.commonattr & Self.ATTR_CMN_ERROR != 0 {
                    let err = p.loadUnaligned(as: UInt32.self)
                    p += 4
                    if err != 0 { continue }
                }

                guard returned.commonattr & Self.ATTR_CMN_NAME != 0 else { continue }
                let nameRef = p.loadUnaligned(as: attrreference_t.self)
                let namePtr = (p + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                let name = String(cString: namePtr)
                p += MemoryLayout<attrreference_t>.size

                var objType: UInt32 = 0
                if returned.commonattr & Self.ATTR_CMN_OBJTYPE != 0 {
                    objType = p.loadUnaligned(as: UInt32.self)
                    p += 4
                }
                var mtime = 0
                if returned.commonattr & Self.ATTR_CMN_MODTIME != 0 {
                    mtime = p.loadUnaligned(as: timespec.self).tv_sec
                    p += MemoryLayout<timespec>.size
                }
                var fileID: UInt64 = 0
                if returned.commonattr & Self.ATTR_CMN_FILEID != 0 {
                    fileID = p.loadUnaligned(as: UInt64.self)
                    p += 8
                }

                if objType == Self.VDIR {
                    let childPath = prefix + name
                    if skipPaths.contains(childPath) { continue }
                    let child = FileNode(name: name, kind: .directory, parent: node)
                    child.modified = mtime
                    kids.append(child)
                    subdirs.append((child, childPath))
                    counts.dirs += 1
                    continue
                }

                var linkCount: UInt32 = 1
                var totalSize: Int64 = 0
                var allocSize: Int64 = 0
                if returned.fileattr & Self.ATTR_FILE_LINKCOUNT != 0 {
                    linkCount = p.loadUnaligned(as: UInt32.self)
                    p += 4
                }
                if returned.fileattr & Self.ATTR_FILE_TOTALSIZE != 0 {
                    totalSize = p.loadUnaligned(as: Int64.self)
                    p += 8
                }
                if returned.fileattr & Self.ATTR_FILE_ALLOCSIZE != 0 {
                    allocSize = p.loadUnaligned(as: Int64.self)
                    p += 8
                }

                // Hard links: only the first link we meet pays for the blocks.
                if linkCount > 1 && fileID != 0 {
                    inodeLock.lock()
                    let isNew = seenHardLinks.insert(fileID).inserted
                    inodeLock.unlock()
                    if !isNew { allocSize = 0 }
                }

                let kind: FileNode.Kind = objType == Self.VREG ? .file : (objType == Self.VLNK ? .symlink : .other)
                let child = FileNode(name: name, kind: kind, parent: node)
                child.size = max(0, allocSize)
                child.logicalSize = max(0, totalSize)
                child.fileCount = 1
                child.modified = mtime
                if kind == .file {
                    let ext = ExtensionRegistry.extensionString(of: name)
                    if let id = extCache[ext] {
                        child.extID = id
                    } else {
                        let id = registry.id(for: ext)
                        extCache[ext] = id
                        child.extID = id
                    }
                }
                kids.append(child)
                counts.files += 1
                counts.bytes += child.size
            }
        }

        node.children = kids
        return subdirs
    }

    // MARK: - Totals

    /// Rolls sizes/counts up the tree and sorts each directory biggest-first.
    static func finalize(_ root: FileNode) {
        // Some system files carry nonsense future timestamps; don't let them win "Last Change".
        let latestPlausible = Int(Date().timeIntervalSince1970) + 86_400
        // Iterative post-order so pathological depths can't blow the stack.
        var stack: [(FileNode, Bool)] = [(root, false)]
        while let (node, visited) = stack.popLast() {
            guard node.isDirectory else { continue }
            if !visited {
                stack.append((node, true))
                for child in node.children where child.isDirectory {
                    stack.append((child, false))
                }
                continue
            }
            var size: Int64 = 0
            var logical: Int64 = 0
            var files = 0
            var dirs = 0
            var modified = node.modified <= latestPlausible ? node.modified : 0
            for child in node.children {
                size += child.size
                logical += child.logicalSize
                files += child.fileCount
                if child.isDirectory { dirs += 1 + child.dirCount }
                if child.modified > modified && child.modified <= latestPlausible { modified = child.modified }
            }
            node.size = size
            node.logicalSize = logical
            node.fileCount = files
            node.dirCount = dirs
            node.modified = modified
            node.children.sort { $0.size > $1.size }
        }
    }
}
