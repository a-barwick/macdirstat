// Renders the app icon (hand-drawn treemap + spark on warm paper) into an .iconset.
import AppKit

struct RNG { var s: UInt64; mutating func n() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(Double(s >> 11) / Double(1 << 53)) * 2 - 1 } }

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let u = size / 1024
    func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a) }
    var rng = RNG(s: 7)
    func wob(_ r: CGRect, _ j: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for _ in 0..<2 {
            let pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY)]
            p.move(to: CGPoint(x: pts[0].x + rng.n() * j, y: pts[0].y + rng.n() * j))
            for i in 1..<pts.count {
                let a = pts[i - 1], b = pts[i]
                p.addQuadCurve(to: CGPoint(x: b.x + rng.n() * j, y: b.y + rng.n() * j), control: CGPoint(x: (a.x + b.x) / 2 + rng.n() * j * 1.5, y: (a.y + b.y) / 2 + rng.n() * j * 1.5))
            }
        }
        return p
    }
    // Squircle paper
    let bg = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * u), blur: 30 * u, color: c(0x000000, 0.35))
    ctx.addPath(CGPath(roundedRect: bg, cornerWidth: 185 * u, cornerHeight: 185 * u, transform: nil))
    ctx.setFillColor(c(0xF3EBDD)); ctx.fillPath()
    ctx.restoreGState()
    // Treemap tiles
    let area = bg.insetBy(dx: 120 * u, dy: 120 * u)
    let tiles: [(CGRect, UInt32)] = [
        (CGRect(x: 0, y: 0, width: 0.56, height: 1), 0xD97757),
        (CGRect(x: 0.56, y: 0.45, width: 0.44, height: 0.55), 0x6A9BCC),
        (CGRect(x: 0.56, y: 0, width: 0.26, height: 0.45), 0x788C5D),
        (CGRect(x: 0.82, y: 0.2, width: 0.18, height: 0.25), 0xD4A27F),
        (CGRect(x: 0.82, y: 0, width: 0.18, height: 0.2), 0xC46686),
    ]
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    for (t, col) in tiles {
        let r = CGRect(x: area.minX + t.minX * area.width, y: area.minY + t.minY * area.height, width: t.width * area.width, height: t.height * area.height).insetBy(dx: 10 * u, dy: 10 * u)
        ctx.setFillColor(c(col)); ctx.fill(r)
        // hatching
        ctx.saveGState(); ctx.clip(to: r)
        ctx.setStrokeColor(c(0x141413, 0.16)); ctx.setLineWidth(5 * u)
        var d: CGFloat = -r.height
        while d < r.width { ctx.move(to: CGPoint(x: r.minX + d, y: r.minY)); ctx.addLine(to: CGPoint(x: r.minX + d + r.height, y: r.maxY)); d += 34 * u }
        ctx.strokePath(); ctx.restoreGState()
        ctx.setStrokeColor(c(0x141413, 0.9)); ctx.setLineWidth(9 * u)
        ctx.addPath(wob(r, 7 * u)); ctx.strokePath()
    }
    // Spark
    let center = CGPoint(x: 700 * u, y: 690 * u)
    ctx.setStrokeColor(c(0xFAF9F5)); ctx.setLineWidth(46 * u)
    var srng = RNG(s: 3)
    let rays = 11
    let paths = CGMutablePath()
    for i in 0..<rays {
        let a = CGFloat(i) / CGFloat(rays) * .pi * 2 + srng.n() * 0.1
        let len = (150 + srng.n() * 30) * u
        paths.move(to: CGPoint(x: center.x + cos(a) * 26 * u, y: center.y + sin(a) * 26 * u))
        paths.addLine(to: CGPoint(x: center.x + cos(a) * len, y: center.y + sin(a) * len))
    }
    ctx.addPath(paths); ctx.strokePath()
    ctx.setStrokeColor(c(0xC8552F)); ctx.setLineWidth(26 * u)
    ctx.addPath(paths); ctx.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let data = draw(size: CGFloat(px)).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
