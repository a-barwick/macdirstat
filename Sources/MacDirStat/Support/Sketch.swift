import AppKit
import SwiftUI

/// Tiny deterministic RNG so hand-drawn wobbles stay put between redraws.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in -1...1
    mutating func signed() -> CGFloat { CGFloat(Double(next() >> 11) / Double(1 << 53)) * 2 - 1 }
    mutating func unit() -> CGFloat { CGFloat(Double(next() >> 11) / Double(1 << 53)) }
}

/// Rough.js-flavoured helpers: lines that wobble like they were drawn by hand.
enum Sketch {
    /// A single wobbly stroke from a to b.
    static func addLine(_ path: CGMutablePath, from a: CGPoint, to b: CGPoint, roughness: CGFloat, rng: inout SeededRandom) {
        let len = hypot(b.x - a.x, b.y - a.y)
        let j = min(roughness, len * 0.08 + 0.4)
        let start = CGPoint(x: a.x + rng.signed() * j, y: a.y + rng.signed() * j)
        let end = CGPoint(x: b.x + rng.signed() * j, y: b.y + rng.signed() * j)
        // Bow the line a little around its middle.
        let nx = -(b.y - a.y) / max(len, 0.001)
        let ny = (b.x - a.x) / max(len, 0.001)
        let bow = rng.signed() * j * 1.4
        let t = 0.35 + rng.unit() * 0.3
        let ctrl = CGPoint(x: a.x + (b.x - a.x) * t + nx * bow, y: a.y + (b.y - a.y) * t + ny * bow)
        path.move(to: start)
        path.addQuadCurve(to: end, control: ctrl)
    }

    /// Rectangle drawn with two overlapping passes and slightly overshooting corners.
    static func roughRect(_ r: CGRect, roughness: CGFloat, seed: UInt64, passes: Int = 2) -> CGMutablePath {
        let path = CGMutablePath()
        var rng = SeededRandom(seed: seed)
        let o = min(roughness * 1.2, min(r.width, r.height) * 0.12)
        for _ in 0..<passes {
            addLine(path, from: CGPoint(x: r.minX - o * rng.unit(), y: r.minY), to: CGPoint(x: r.maxX + o * rng.unit(), y: r.minY), roughness: roughness, rng: &rng)
            addLine(path, from: CGPoint(x: r.maxX, y: r.minY - o * rng.unit()), to: CGPoint(x: r.maxX, y: r.maxY + o * rng.unit()), roughness: roughness, rng: &rng)
            addLine(path, from: CGPoint(x: r.maxX + o * rng.unit(), y: r.maxY), to: CGPoint(x: r.minX - o * rng.unit(), y: r.maxY), roughness: roughness, rng: &rng)
            addLine(path, from: CGPoint(x: r.minX, y: r.maxY + o * rng.unit()), to: CGPoint(x: r.minX, y: r.minY - o * rng.unit()), roughness: roughness, rng: &rng)
        }
        return path
    }

    /// Diagonal hatching clipped to `r` — the pencil-shading look.
    static func hatch(_ r: CGRect, spacing: CGFloat, roughness: CGFloat, seed: UInt64) -> CGMutablePath {
        let path = CGMutablePath()
        var rng = SeededRandom(seed: seed)
        var d = -r.height + spacing * rng.unit()
        while d < r.width {
            let a = CGPoint(x: r.minX + max(d, 0), y: r.maxY - max(0, -d))
            let bx = min(d + r.height, r.width)
            let b = CGPoint(x: r.minX + bx, y: r.maxY - (bx - d))
            addLine(path, from: a, to: b, roughness: roughness, rng: &rng)
            d += spacing
        }
        return path
    }

    /// A hand-drawn spark: uneven rays bursting from a centre.
    static func spark(in rect: CGRect, rays: Int = 11, seed: UInt64 = 7, wobble: CGFloat = 0.18) -> CGMutablePath {
        let path = CGMutablePath()
        var rng = SeededRandom(seed: seed)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let inner = radius * 0.16
        for i in 0..<rays {
            let angle = (CGFloat(i) / CGFloat(rays)) * .pi * 2 + rng.signed() * 0.12
            let len = radius * (0.72 + rng.unit() * 0.28)
            let bend = rng.signed() * wobble * radius * 0.25
            let a = CGPoint(x: c.x + cos(angle) * inner, y: c.y + sin(angle) * inner)
            let b = CGPoint(x: c.x + cos(angle) * len, y: c.y + sin(angle) * len)
            let mid = CGPoint(x: (a.x + b.x) / 2 - sin(angle) * bend, y: (a.y + b.y) / 2 + cos(angle) * bend)
            path.move(to: a)
            path.addQuadCurve(to: b, control: mid)
        }
        return path
    }

    /// A loose, loopy underline.
    static func squiggle(width: CGFloat, height: CGFloat, seed: UInt64) -> CGMutablePath {
        let path = CGMutablePath()
        var rng = SeededRandom(seed: seed)
        let mid = height / 2
        path.move(to: CGPoint(x: 0, y: mid + rng.signed() * 2))
        let segments = max(3, Int(width / 38))
        let step = width / CGFloat(segments)
        for i in 1...segments {
            let x = step * CGFloat(i)
            let up = i % 2 == 0 ? -1.0 : 1.0
            path.addQuadCurve(
                to: CGPoint(x: x, y: mid + rng.signed() * 1.5),
                control: CGPoint(x: x - step / 2, y: mid + up * height * 0.45 + rng.signed() * 2))
        }
        return path
    }
}

// MARK: - SwiftUI shapes

struct SketchRect: Shape {
    var seed: UInt64 = 1
    var roughness: CGFloat = 1.6
    var passes = 2

    func path(in rect: CGRect) -> Path {
        Path(Sketch.roughRect(rect.insetBy(dx: roughness, dy: roughness), roughness: roughness, seed: seed, passes: passes))
    }
}

/// Filled blob with wobbly edges (for fills; SketchRect is strokes only).
struct WobblyRoundedRect: Shape {
    var seed: UInt64 = 3
    var radius: CGFloat = 10
    var wobble: CGFloat = 1.5

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed: seed)
        let r = min(radius, min(rect.width, rect.height) / 2)
        let w = wobble
        func j() -> CGFloat { rng.signed() * w }
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY + j()))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY + j()), control: CGPoint(x: rect.midX, y: rect.minY + j()))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + j(), y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + j(), y: rect.maxY - r), control: CGPoint(x: rect.maxX + j(), y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY + j()), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY + j()), control: CGPoint(x: rect.midX, y: rect.maxY + j()))
        p.addQuadCurve(to: CGPoint(x: rect.minX + j(), y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + j(), y: rect.minY + r), control: CGPoint(x: rect.minX + j(), y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct SparkShape: Shape {
    var rays = 11
    var seed: UInt64 = 7

    func path(in rect: CGRect) -> Path { Path(Sketch.spark(in: rect, rays: rays, seed: seed)) }
}

struct SquiggleShape: Shape {
    var seed: UInt64 = 5

    func path(in rect: CGRect) -> Path {
        Path(Sketch.squiggle(width: rect.width, height: rect.height, seed: seed))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// The app's spark mark, stroked with round caps like a brush pen.
struct SparkMark: View {
    var color: Color
    var lineWidth: CGFloat = 4
    var seed: UInt64 = 7

    var body: some View {
        SparkShape(seed: seed)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}
