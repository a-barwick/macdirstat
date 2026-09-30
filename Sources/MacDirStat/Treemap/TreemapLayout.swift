import CoreGraphics
import Foundation

/// Van Wijk cushion coefficients: z(x) = x2·x² + x1·x (same for y).
struct Surface {
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    mutating func addRidge(_ r: CGRect, height h: Double) {
        let w = Double(r.width), ht = Double(r.height)
        if w > 0 {
            x1 += 4 * h * Double(r.maxX + r.minX) / w
            x2 -= 4 * h / w
        }
        if ht > 0 {
            y1 += 4 * h * Double(r.maxY + r.minY) / ht
            y2 -= 4 * h / ht
        }
    }
}

/// Squarified treemap in *pixel* space (top-left origin). Built on the main thread — it only walks
/// as deep as there are pixels to show, so it's cheap even for millions of files — and the pixel
/// work is handed to `TreemapRenderer` as plain values.
final class TreemapLayout {
    struct Item {
        let node: FileNode
        var rect: CGRect
        let parent: Int32
        var firstChild: Int32 = -1
        var childCount: Int32 = 0
        let depth: Int16
    }

    struct Leaf {
        var x0: Int32, y0: Int32, x1: Int32, y1: Int32
        var color: RGB
        var surface: Surface
        var extID: UInt16
        var isFile: Bool
    }

    private(set) var items: [Item] = []
    private(set) var leaves: [Leaf] = []
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: CGFloat

    private let height: Double
    private let falloff: Double
    private let colorFor: (FileNode) -> RGB
    /// Children smaller than this many pixels² get lumped into their parent.
    private let minArea: CGFloat

    private init(pixelWidth: Int, pixelHeight: Int, scale: CGFloat, style: TreemapStyle, colorFor: @escaping (FileNode) -> RGB) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
        self.colorFor = colorFor
        self.minArea = max(2, scale * scale * 1.2)
        switch style {
        case .cushion:
            height = 0.36
            falloff = 0.8
        case .sketch:
            height = 0.1
            falloff = 0.7
        }
    }

    static func build(root: FileNode, pixelWidth: Int, pixelHeight: Int, scale: CGFloat,
                      style: TreemapStyle, colorFor: @escaping (FileNode) -> RGB) -> TreemapLayout {
        let layout = TreemapLayout(pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale, style: style, colorFor: colorFor)
        let full = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        layout.items.reserveCapacity(4096)
        layout.items.append(Item(node: root, rect: full, parent: -1, depth: 0))
        layout.process(0, surface: Surface())
        return layout
    }

    private func process(_ index: Int, surface parentSurface: Surface) {
        let item = items[index]
        var surface = parentSurface
        surface.addRidge(item.rect, height: height * pow(falloff, Double(item.depth)))

        let node = item.node
        let rect = item.rect
        guard node.isDirectory, node.size > 0, rect.width >= 2, rect.height >= 2,
              let first = node.children.first, first.size > 0 else {
            addLeaf(rect, color: node.isDirectory ? Palette.directoryLeaf : colorFor(node),
                    surface: surface, extID: node.extID, isFile: !node.isDirectory)
            return
        }

        var placed: [(FileNode, CGRect)] = []
        let remainder = squarify(node.children, total: node.size, in: rect, into: &placed)

        if placed.isEmpty {
            addLeaf(rect, color: Palette.directoryLeaf, surface: surface, extID: 0, isFile: false)
            return
        }

        let firstChild = items.count
        let depth = item.depth + 1
        for (child, r) in placed {
            items.append(Item(node: child, rect: r, parent: Int32(index), depth: depth))
        }
        items[index].firstChild = Int32(firstChild)
        items[index].childCount = Int32(placed.count)

        if let rest = remainder, rest.width > 0, rest.height > 0 {
            addLeaf(rest, color: Palette.directoryLeaf, surface: surface, extID: 0, isFile: false)
        }
        for i in firstChild..<(firstChild + placed.count) {
            process(i, surface: surface)
        }
    }

    private func addLeaf(_ r: CGRect, color: RGB, surface: Surface, extID: UInt16, isFile: Bool) {
        let x0 = Int32(max(0, min(pixelWidth, Int(r.minX.rounded()))))
        let x1 = Int32(max(0, min(pixelWidth, Int(r.maxX.rounded()))))
        let y0 = Int32(max(0, min(pixelHeight, Int(r.minY.rounded()))))
        let y1 = Int32(max(0, min(pixelHeight, Int(r.maxY.rounded()))))
        guard x1 > x0, y1 > y0 else { return }
        leaves.append(Leaf(x0: x0, y0: y0, x1: x1, y1: y1, color: color, surface: surface, extID: extID, isFile: isFile))
    }

    /// Classic squarify (Bruls, Huizing, van Wijk). `children` must be sorted biggest-first.
    /// Returns the leftover area when the tail was too small to draw individually.
    private func squarify(_ children: [FileNode], total: Int64, in rect: CGRect,
                          into placed: inout [(FileNode, CGRect)]) -> CGRect? {
        var r = rect
        var start = 0
        var remaining = Double(total)
        let n = children.count
        while start < n {
            if r.width < 1 || r.height < 1 || remaining <= 0 { return r }
            let areaScale = Double(r.width * r.height) / remaining
            // Everything left is too small to see: hand it back as a lump.
            if Double(children[start].size) * areaScale < Double(minArea) || children[start].size <= 0 {
                return r
            }

            let wide = r.width >= r.height
            let side = Double(wide ? r.height : r.width)
            let side2 = side * side
            let maxArea = Double(children[start].size) * areaScale

            var end = start
            var rowSum = 0.0
            var worst = Double.infinity
            while end < n {
                let s = Double(children[end].size)
                if s <= 0 { break }
                let sumArea = (rowSum + s) * areaScale
                let minArea = s * areaScale
                let ratio = max(side2 * maxArea / (sumArea * sumArea), (sumArea * sumArea) / (side2 * minArea))
                if end > start && ratio > worst { break }
                worst = ratio
                rowSum += s
                end += 1
            }

            let isLastRow = end >= n || Double(children[end].size) <= 0
            let rowArea = rowSum * areaScale
            var thickness = CGFloat(rowArea / side)
            if isLastRow { thickness = wide ? r.width : r.height }

            var offset: CGFloat = 0
            let span = CGFloat(side)
            for i in start..<end {
                let s = Double(children[i].size)
                var len = CGFloat(s / rowSum) * span
                if i == end - 1 { len = span - offset }
                let childRect = wide
                    ? CGRect(x: r.minX, y: r.minY + offset, width: thickness, height: len)
                    : CGRect(x: r.minX + offset, y: r.minY, width: len, height: thickness)
                placed.append((children[i], childRect))
                offset += len
            }

            if wide {
                r = CGRect(x: r.minX + thickness, y: r.minY, width: max(0, r.width - thickness), height: r.height)
            } else {
                r = CGRect(x: r.minX, y: r.minY + thickness, width: r.width, height: max(0, r.height - thickness))
            }
            remaining -= rowSum
            start = end
        }
        return nil
    }

    // MARK: - Queries

    /// Deepest item under a pixel-space point.
    func hitTest(_ p: CGPoint) -> Int? {
        guard !items.isEmpty, items[0].rect.contains(p) else { return nil }
        var current = 0
        while true {
            let item = items[current]
            guard item.childCount > 0 else { return current }
            var next: Int?
            let start = Int(item.firstChild)
            for i in start..<(start + Int(item.childCount)) where items[i].rect.contains(p) {
                next = i
                break
            }
            guard let n = next else { return current }
            current = n
        }
    }

    /// Item for `node`, or its nearest ancestor that made it into the layout.
    func index(of node: FileNode) -> Int? {
        guard let rootNode = items.first?.node, node.isDescendant(of: rootNode) else { return nil }
        var chain: [FileNode] = []
        var n: FileNode? = node
        while let c = n, c !== rootNode { chain.append(c); n = c.parent }
        var current = 0
        for target in chain.reversed() {
            let item = items[current]
            guard item.childCount > 0 else { return current }
            let start = Int(item.firstChild)
            guard let found = (start..<(start + Int(item.childCount))).first(where: { items[$0].node === target }) else {
                return current
            }
            current = found
        }
        return current
    }

    func item(_ i: Int) -> Item { items[i] }
}
