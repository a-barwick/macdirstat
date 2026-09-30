import CoreGraphics
import CoreText
import Foundation

/// Everything the background renderer needs, as plain values (no FileNode references).
struct TreemapRenderJob {
    struct Outline {
        var rect: CGRect
        var depth: Int
        var seed: UInt64
    }

    struct Label {
        var rect: CGRect
        var title: String
        var subtitle: String
        var seed: UInt64
        var prominent: Bool
    }

    var width: Int
    var height: Int
    var scale: CGFloat
    var style: TreemapStyle
    var leaves: [TreemapLayout.Leaf]
    var outlines: [Outline]
    var labels: [Label]
    var background: RGB
    var ink: RGB
    var tagPaper: RGB
    var isDark: Bool
}

enum TreemapRenderer {
    static func render(_ job: TreemapRenderJob, isCancelled: () -> Bool = { false }) -> CGImage? {
        let w = job.width, h = job.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }

        let bytesPerRow = ctx.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * h)

        // Background (shows through any hairline gaps).
        let bg = job.background
        let bgBytes = (UInt8(bg.r * 255), UInt8(bg.g * 255), UInt8(bg.b * 255))
        for y in 0..<h {
            var p = pixels + y * bytesPerRow
            for _ in 0..<w {
                p[0] = bgBytes.0; p[1] = bgBytes.1; p[2] = bgBytes.2; p[3] = 255
                p += 4
            }
        }

        shadeLeaves(job, pixels: pixels, bytesPerRow: bytesPerRow)
        if isCancelled() { return nil }

        // Vector pass, in a top-left coordinate system to match the layout.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if job.style == .sketch {
            drawSketchDetails(job, ctx: ctx)
        } else {
            drawCushionDetails(job, ctx: ctx)
        }
        if isCancelled() { return nil }
        drawLabels(job, ctx: ctx)

        return ctx.makeImage()
    }

    // MARK: - Pixels

    private static func shadeLeaves(_ job: TreemapRenderJob, pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int) {
        // Light from the upper left, a little in front.
        let lx = -0.09759, ly = -0.19518, lz = 0.97590
        let ambient: Double
        let diffuse: Double
        let grain: Double
        switch job.style {
        case .cushion:
            ambient = 0.42; diffuse = 0.72; grain = 0.025
        case .sketch:
            ambient = 0.52; diffuse = 0.50; grain = 0.07
        }
        let darken = job.isDark ? 0.86 : 1.0

        let leaves = job.leaves
        let chunkCount = max(1, min(64, leaves.count / 64))
        leaves.withUnsafeBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
                let lo = buf.count * chunk / chunkCount
                let hi = buf.count * (chunk + 1) / chunkCount
                for li in lo..<hi {
                    let leaf = buf[li]
                    let s = leaf.surface
                    let cr = leaf.color.r * darken, cg = leaf.color.g * darken, cb = leaf.color.b * darken
                    for y in Int(leaf.y0)..<Int(leaf.y1) {
                        let fy = Double(y) + 0.5
                        let ny = -(2 * s.y2 * fy + s.y1)
                        var p = pixels + y * bytesPerRow + Int(leaf.x0) * 4
                        for x in Int(leaf.x0)..<Int(leaf.x1) {
                            let fx = Double(x) + 0.5
                            let nx = -(2 * s.x2 * fx + s.x1)
                            let cosa = (nx * lx + ny * ly + lz) / (nx * nx + ny * ny + 1).squareRoot()
                            var v = ambient + diffuse * max(0, cosa)
                            if grain > 0 {
                                var hsh = UInt32(truncatingIfNeeded: x &* 73_856_093) ^ UInt32(truncatingIfNeeded: y &* 19_349_663)
                                hsh = (hsh ^ (hsh >> 13)) &* 0x5BD1_E995
                                hsh ^= hsh >> 15
                                v *= 1 + (Double(hsh & 0xFF) / 255 - 0.5) * grain
                            }
                            p[0] = UInt8(max(0, min(255, cr * v * 255)))
                            p[1] = UInt8(max(0, min(255, cg * v * 255)))
                            p[2] = UInt8(max(0, min(255, cb * v * 255)))
                            p[3] = 255
                            p += 4
                        }
                    }
                }
            }
        }
    }

    // MARK: - Vector details

    private static func drawSketchDetails(_ job: TreemapRenderJob, ctx: CGContext) {
        let s = job.scale
        let ink = job.ink

        // Pencil hatching on roomy files.
        let hatch = CGMutablePath()
        let minSide = 26 * s
        for (i, leaf) in job.leaves.enumerated() where leaf.isFile {
            let r = CGRect(x: CGFloat(leaf.x0), y: CGFloat(leaf.y0), width: CGFloat(leaf.x1 - leaf.x0), height: CGFloat(leaf.y1 - leaf.y0))
            guard r.width >= minSide, r.height >= minSide else { continue }
            hatch.addPath(Sketch.hatch(r.insetBy(dx: 3 * s, dy: 3 * s), spacing: 7 * s, roughness: 0.8 * s, seed: UInt64(i)))
        }
        ctx.setStrokeColor(CGColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: job.isDark ? 0.10 : 0.08))
        ctx.setLineWidth(1 * s)
        ctx.addPath(hatch)
        ctx.strokePath()

        // Fine ink edges around every visible tile.
        let edges = CGMutablePath()
        for leaf in job.leaves where leaf.x1 - leaf.x0 >= Int32(3 * s) && leaf.y1 - leaf.y0 >= Int32(3 * s) {
            edges.addRect(CGRect(x: CGFloat(leaf.x0) + 0.5, y: CGFloat(leaf.y0) + 0.5,
                                 width: CGFloat(leaf.x1 - leaf.x0) - 1, height: CGFloat(leaf.y1 - leaf.y0) - 1))
        }
        ctx.setStrokeColor(CGColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: job.isDark ? 0.16 : 0.28))
        ctx.setLineWidth(0.7 * s)
        ctx.addPath(edges)
        ctx.strokePath()

        // Wobbly pen lines around folders, heavier near the top.
        for outline in job.outlines.sorted(by: { $0.depth > $1.depth }) {
            let (width, alpha): (CGFloat, CGFloat) = outline.depth <= 1 ? (2.0, 0.85) : (1.2, 0.55)
            let path = Sketch.roughRect(outline.rect.insetBy(dx: 1.5 * s, dy: 1.5 * s), roughness: 1.4 * s, seed: outline.seed)
            ctx.setStrokeColor(CGColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: alpha))
            ctx.setLineWidth(width * s)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private static func drawCushionDetails(_ job: TreemapRenderJob, ctx: CGContext) {
        // Just a soft seam between the top-level folders so the map reads at a glance.
        let seams = CGMutablePath()
        for outline in job.outlines where outline.depth == 1 {
            seams.addRect(outline.rect.insetBy(dx: 0.5 * job.scale, dy: 0.5 * job.scale))
        }
        ctx.setStrokeColor(CGColor(srgbRed: 0.08, green: 0.06, blue: 0.04, alpha: 0.45))
        ctx.setLineWidth(1.2 * job.scale)
        ctx.addPath(seams)
        ctx.strokePath()
    }

    private static func drawLabels(_ job: TreemapRenderJob, ctx: CGContext) {
        guard !job.labels.isEmpty else { return }
        let s = job.scale
        let ink = CGColor(srgbRed: job.ink.r, green: job.ink.g, blue: job.ink.b, alpha: 1)
        let inkSoft = CGColor(srgbRed: job.ink.r, green: job.ink.g, blue: job.ink.b, alpha: 0.7)
        let paper = CGColor(srgbRed: job.tagPaper.r, green: job.tagPaper.g, blue: job.tagPaper.b, alpha: 0.92)

        for label in job.labels {
            let titleFont = CTFontCreateWithName((label.prominent ? "Noteworthy-Bold" : "Noteworthy-Light") as CFString,
                                                 (label.prominent ? 13 : 11) * s, nil)
            let subFont = CTFontCreateWithName("Noteworthy-Light" as CFString, 10.5 * s, nil)
            let maxTextWidth = label.rect.width - 22 * s
            guard maxTextWidth > 24 * s else { continue }

            guard let title = makeLine(label.title, font: titleFont, color: ink, maxWidth: maxTextWidth) else { continue }
            let sub = label.rect.height > 44 * s ? makeLine(label.subtitle, font: subFont, color: inkSoft, maxWidth: maxTextWidth) : nil

            let titleWidth = CTLineGetTypographicBounds(title, nil, nil, nil)
            let subWidth = sub.map { CTLineGetTypographicBounds($0, nil, nil, nil) } ?? 0
            let lineH = CTFontGetAscent(titleFont) + CTFontGetDescent(titleFont)
            let subH = sub != nil ? CTFontGetAscent(subFont) + CTFontGetDescent(subFont) : 0
            let padX = 7 * s, padY = 3 * s
            let tagW = CGFloat(max(titleWidth, subWidth)) + padX * 2
            let tagH = lineH + subH + padY * 2
            guard tagH + 8 * s < label.rect.height else { continue }

            var rng = SeededRandom(seed: label.seed)
            let tag = CGRect(x: label.rect.minX + 6 * s, y: label.rect.minY + 6 * s, width: tagW, height: tagH)

            ctx.saveGState()
            ctx.translateBy(x: tag.midX, y: tag.midY)
            ctx.rotate(by: rng.signed() * 0.03)
            ctx.translateBy(x: -tag.midX, y: -tag.midY)

            // Little paper tag with a pen outline.
            let tagPath = CGPath(roundedRect: tag, cornerWidth: 5 * s, cornerHeight: 5 * s, transform: nil)
            ctx.setShadow(offset: CGSize(width: 0, height: 1.5 * s), blur: 3 * s, color: CGColor(gray: 0, alpha: 0.25))
            ctx.setFillColor(paper)
            ctx.addPath(tagPath)
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setStrokeColor(ink.copy(alpha: 0.7)!)
            ctx.setLineWidth(1 * s)
            ctx.addPath(Sketch.roughRect(tag, roughness: 0.9 * s, seed: label.seed, passes: 1))
            ctx.strokePath()

            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: tag.minX + padX, y: tag.minY + padY + CTFontGetAscent(titleFont))
            CTLineDraw(title, ctx)
            if let sub {
                ctx.textPosition = CGPoint(x: tag.minX + padX, y: tag.minY + padY + lineH + CTFontGetAscent(subFont))
                CTLineDraw(sub, ctx)
            }
            ctx.restoreGState()
        }
    }

    private static func makeLine(_ text: String, font: CTFont, color: CGColor, maxWidth: CGFloat) -> CTLine? {
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs as [NSAttributedString.Key: Any]))
        if CTLineGetTypographicBounds(line, nil, nil, nil) <= Double(maxWidth) { return line }
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs as [NSAttributedString.Key: Any]))
        return CTLineCreateTruncatedLine(line, Double(maxWidth), .end, ellipsis)
    }
}
