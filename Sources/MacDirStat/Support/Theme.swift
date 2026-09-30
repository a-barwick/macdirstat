import AppKit
import SwiftUI

/// Plain RGB triple usable from any thread (the treemap renderer works in raw pixels).
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    func desaturated(_ amount: Double) -> RGB {
        let l = 0.299 * r + 0.587 * g + 0.114 * b
        return mixed(with: RGB(l, l, l), amount)
    }
}

/// The warm palette: ivory paper, slate ink, clay accents.
enum Palette {
    static let clay = RGB(hex: 0xD97757)
    static let bookCloth = RGB(hex: 0xCC785C)
    static let kraft = RGB(hex: 0xD4A27F)
    static let manilla = RGB(hex: 0xEBDBBC)
    static let oat = RGB(hex: 0xE3DACC)
    static let ivory = RGB(hex: 0xFAF9F5)
    static let ivoryMedium = RGB(hex: 0xF0EEE6)
    static let cloud = RGB(hex: 0xB0AEA5)
    static let slate = RGB(hex: 0x141413)
    static let olive = RGB(hex: 0x788C5D)
    static let sky = RGB(hex: 0x6A9BCC)
    static let fig = RGB(hex: 0xC46686)

    /// Colours handed to the biggest file types, in order.
    static let extensionColors: [RGB] = [
        RGB(hex: 0xD97757), // clay
        RGB(hex: 0x6A9BCC), // sky
        RGB(hex: 0x788C5D), // olive
        RGB(hex: 0xD4A27F), // kraft
        RGB(hex: 0xC46686), // fig
        RGB(hex: 0x9A86C8), // heather
        RGB(hex: 0xE2B44F), // mustard
        RGB(hex: 0x5E9E8F), // cactus
        RGB(hex: 0xB8563E), // rust
        RGB(hex: 0x9DB4CB), // dusk
        RGB(hex: 0x8C6A4F), // walnut
        RGB(hex: 0xC9B48E), // sand
        RGB(hex: 0xE59A7E), // peach
        RGB(hex: 0x4F7A8C), // deep sea
    ]

    static let directoryLeaf = RGB(hex: 0xB9B3A5)

    /// Stable, muted colour for extensions outside the top list.
    static func fallbackColor(for id: UInt16) -> RGB {
        var x = UInt64(id) &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 29
        let base = extensionColors[Int(x % UInt64(extensionColors.count))]
        return base.desaturated(0.45).mixed(with: oat, 0.25)
    }
}

enum TreemapStyle: String, CaseIterable, Identifiable {
    case cushion
    case sketch

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cushion: return "Cushions"
        case .sketch: return "Sketchbook"
        }
    }
}

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let blurb: String
    let paper: RGB        // main background
    let panel: RGB        // raised panels
    let well: RGB         // behind the treemap
    let ink: RGB          // primary text & sketch lines
    let inkSoft: RGB      // secondary text
    let accent: RGB       // clay highlights
    let line: RGB         // hairlines & dividers
    let isDark: Bool

    static let ivory = Theme(
        id: "ivory", name: "Ivory", blurb: "Fresh paper, sharp pencil",
        paper: RGB(hex: 0xFAF9F5), panel: RGB(hex: 0xF0EEE6), well: RGB(hex: 0xE8E6DC),
        ink: RGB(hex: 0x141413), inkSoft: RGB(hex: 0x6B6960), accent: Palette.clay,
        line: RGB(hex: 0xD9D5C8), isDark: false)

    static let oat = Theme(
        id: "oat", name: "Oat", blurb: "Warm kraft & coffee",
        paper: RGB(hex: 0xF1EADF), panel: RGB(hex: 0xE3DACC), well: RGB(hex: 0xD8CDBB),
        ink: RGB(hex: 0x3A2A1E), inkSoft: RGB(hex: 0x7A6552), accent: RGB(hex: 0xC2643F),
        line: RGB(hex: 0xCDBFA8), isDark: false)

    static let clay = Theme(
        id: "clay", name: "Clay", blurb: "Sunset terracotta",
        paper: RGB(hex: 0xF6E7DC), panel: RGB(hex: 0xEED3C2), well: RGB(hex: 0xE4C2AC),
        ink: RGB(hex: 0x3B1F14), inkSoft: RGB(hex: 0x8A5A45), accent: RGB(hex: 0xC8552F),
        line: RGB(hex: 0xDDB59C), isDark: false)

    static let slate = Theme(
        id: "slate", name: "Slate", blurb: "Late-night chalkboard",
        paper: RGB(hex: 0x262624), panel: RGB(hex: 0x1F1E1D), well: RGB(hex: 0x181817),
        ink: RGB(hex: 0xF0EEE6), inkSoft: RGB(hex: 0xA6A398), accent: RGB(hex: 0xE08462),
        line: RGB(hex: 0x3E3D39), isDark: true)

    static let all: [Theme] = [.ivory, .oat, .clay, .slate]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? .ivory }
}

enum Fonts {
    static func hand(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: size)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func nsHand(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: size) ?? .systemFont(ofSize: size)
    }
}
