import SwiftUI

/// Warm paper with a faint speckle, like the good notebook.
struct PaperBackground: View {
    var theme: Theme

    var body: some View {
        ZStack {
            theme.paper.color
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 42)
                let count = Int(size.width * size.height / 900)
                for _ in 0..<count {
                    let x = rng.unit() * size.width
                    let y = rng.unit() * size.height
                    let r = 0.4 + rng.unit() * 0.8
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                             with: .color(theme.ink.color.opacity(theme.isDark ? 0.10 : 0.06)))
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Buttons that look inked on with a brush pen.
struct SketchButtonStyle: ButtonStyle {
    var theme: Theme
    var prominent = false
    var seed: UInt64 = 11
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        SketchButtonBody(configuration: configuration, theme: theme, prominent: prominent, seed: seed, compact: compact)
    }

    private struct SketchButtonBody: View {
        let configuration: Configuration
        let theme: Theme
        let prominent: Bool
        let seed: UInt64
        let compact: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 14, weight: .medium))
                .foregroundStyle(prominent ? theme.paper.color : theme.ink.color)
                .padding(.horizontal, compact ? 10 : 18)
                .padding(.vertical, compact ? 5 : 10)
                .background(
                    WobblyRoundedRect(seed: seed, radius: compact ? 8 : 12, wobble: 1.2)
                        .fill(prominent ? theme.accent.color : (hovering ? theme.panel.color : theme.paper.color.opacity(0.6)))
                )
                .overlay(
                    SketchRect(seed: seed &+ 3, roughness: 1.3)
                        .stroke(theme.ink.color.opacity(prominent ? 0.85 : 0.65), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                )
                .rotationEffect(.degrees(hovering && isEnabled ? -1.2 : 0))
                .scaleEffect(configuration.isPressed ? 0.95 : (hovering && isEnabled ? 1.03 : 1))
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
        }
    }
}

/// Small round icon button for the header.
struct DoodleIconButton: View {
    var systemName: String
    var help: String
    var theme: Theme
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.ink.color)
                .frame(width: 30, height: 28)
                .background(
                    WobblyRoundedRect(seed: UInt64(abs(systemName.hashValue % 997)), radius: 8, wobble: 1)
                        .fill(hovering ? theme.panel.color : .clear)
                )
                .overlay(
                    SketchRect(seed: UInt64(abs(systemName.hashValue % 991)), roughness: 1)
                        .stroke(theme.ink.color.opacity(hovering ? 0.6 : 0.25), lineWidth: 1)
                )
                .rotationEffect(.degrees(hovering && isEnabled ? 4 : 0))
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: hovering)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Spinning, breathing spark used while scanning.
struct SpinningSpark: View {
    var color: Color
    var size: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            SparkMark(color: color, lineWidth: lineWidth, seed: UInt64(Int(t * 3) % 5) + 7)
                .frame(width: size, height: size)
                .rotationEffect(.radians(t * 0.9))
                .scaleEffect(1 + 0.06 * sin(t * 3))
        }
    }
}

/// A doodled pointing arrow.
struct DoodleArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let start = CGPoint(x: rect.minX, y: rect.maxY * 0.8)
        let end = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.25)
        p.move(to: start)
        p.addCurve(to: end,
                   control1: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY * 1.05),
                   control2: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY - rect.height * 0.1))
        p.move(to: end)
        p.addLine(to: CGPoint(x: end.x - rect.width * 0.16, y: end.y - rect.height * 0.05))
        p.move(to: end)
        p.addLine(to: CGPoint(x: end.x - rect.width * 0.07, y: end.y + rect.height * 0.2))
        return p
    }
}

struct Swatch: View {
    var color: RGB
    var seed: UInt64
    var size: CGFloat = 12

    var body: some View {
        WobblyRoundedRect(seed: seed, radius: size / 2, wobble: 0.7)
            .fill(color.color)
            .overlay(WobblyRoundedRect(seed: seed &+ 1, radius: size / 2, wobble: 0.7).stroke(Color.black.opacity(0.35), lineWidth: 0.8))
            .frame(width: size, height: size)
    }
}
