import SwiftUI

struct WelcomeView: View {
    @ObservedObject var state: AppState
    @State private var appeared = false
    @State private var dropTargeted = false

    private var theme: Theme { state.theme }

    var body: some View {
        ZStack {
            doodles

            VStack(spacing: 22) {
                SparkMark(color: theme.accent.color, lineWidth: 7)
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(appeared ? 0 : -90))
                    .scaleEffect(appeared ? 1 : 0.4)

                VStack(spacing: 6) {
                    Text("Where did all the space go?")
                        .font(Fonts.serif(40, weight: .medium))
                        .foregroundStyle(theme.ink.color)
                    SquiggleShape(seed: 9)
                        .stroke(theme.accent.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 330, height: 14)
                        .offset(x: 70)
                }

                Text("Point me at a folder and I'll sketch you a map of it —\nbig boxes are big files. Then we can tidy up together.")
                    .font(Fonts.serif(16))
                    .foregroundStyle(theme.inkSoft.color)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                HStack(spacing: 14) {
                    Button {
                        state.scan(URL(fileURLWithPath: NSHomeDirectory()))
                    } label: {
                        Label("My Home Folder", systemImage: "house")
                    }
                    .buttonStyle(SketchButtonStyle(theme: theme, prominent: true, seed: 21))

                    Button {
                        state.scan(URL(fileURLWithPath: "/"))
                    } label: {
                        Label("Macintosh HD", systemImage: "internaldrive")
                    }
                    .buttonStyle(SketchButtonStyle(theme: theme, seed: 22))

                    Button {
                        state.chooseFolder()
                    } label: {
                        Label("Choose a Folder…", systemImage: "folder")
                    }
                    .buttonStyle(SketchButtonStyle(theme: theme, seed: 23))
                }
                .padding(.top, 6)

                HStack(spacing: 8) {
                    DoodleArrow()
                        .stroke(theme.inkSoft.color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 44, height: 22)
                    Text("…or just drop a folder anywhere on this window")
                        .font(Fonts.hand(15))
                        .foregroundStyle(theme.inkSoft.color)
                }
                .padding(.top, 14)
            }
            .padding(40)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) { appeared = true }
        }
    }

    /// Loose sketches in the margins.
    private var doodles: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                MiniTreemapDoodle(theme: theme)
                    .frame(width: 170, height: 120)
                    .rotationEffect(.degrees(-6))
                    .position(x: w * 0.13, y: h * 0.22)
                FolderDoodle(theme: theme)
                    .frame(width: 110, height: 84)
                    .rotationEffect(.degrees(7))
                    .position(x: w * 0.87, y: h * 0.76)
                ForEach(0..<6, id: \.self) { i in
                    var rng = SeededRandom(seed: UInt64(i) + 100)
                    let x = w * (0.08 + rng.unit() * 0.84)
                    let y = h * (i % 2 == 0 ? 0.08 + rng.unit() * 0.12 : 0.82 + rng.unit() * 0.12)
                    SparkMark(color: (i % 3 == 0 ? theme.accent : theme.inkSoft).color.opacity(0.55), lineWidth: 1.6, seed: UInt64(i) + 30)
                        .frame(width: 14 + CGFloat(i % 3) * 5, height: 14 + CGFloat(i % 3) * 5)
                        .position(x: x, y: y)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A tiny hand-drawn treemap for the welcome page margin.
struct MiniTreemapDoodle: View {
    var theme: Theme

    var body: some View {
        Canvas { ctx, size in
            let boxes: [(CGRect, RGB)] = [
                (CGRect(x: 0, y: 0, width: 0.58, height: 1), Palette.clay),
                (CGRect(x: 0.58, y: 0, width: 0.42, height: 0.55), Palette.sky),
                (CGRect(x: 0.58, y: 0.55, width: 0.24, height: 0.45), Palette.olive),
                (CGRect(x: 0.82, y: 0.55, width: 0.18, height: 0.25), Palette.kraft),
                (CGRect(x: 0.82, y: 0.8, width: 0.18, height: 0.2), Palette.fig),
            ]
            for (i, (unit, color)) in boxes.enumerated() {
                let r = CGRect(x: unit.minX * size.width, y: unit.minY * size.height,
                               width: unit.width * size.width, height: unit.height * size.height).insetBy(dx: 2, dy: 2)
                ctx.fill(Path(r.insetBy(dx: 1, dy: 1)), with: .color(color.color.opacity(0.8)))
                ctx.stroke(Path(Sketch.hatch(r, spacing: 6, roughness: 0.8, seed: UInt64(i))),
                           with: .color(theme.ink.color.opacity(0.18)), lineWidth: 1)
                ctx.stroke(Path(Sketch.roughRect(r, roughness: 1.4, seed: UInt64(i) + 40)),
                           with: .color(theme.ink.color.opacity(0.8)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
        .opacity(0.8)
    }
}

struct FolderDoodle: View {
    var theme: Theme

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var p = Path()
            p.move(to: CGPoint(x: 4, y: h * 0.25))
            p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.23))
            p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.36))
            p.addLine(to: CGPoint(x: w - 4, y: h * 0.35))
            p.addQuadCurve(to: CGPoint(x: w - 6, y: h - 4), control: CGPoint(x: w - 1, y: h * 0.7))
            p.addLine(to: CGPoint(x: 6, y: h - 3))
            p.addQuadCurve(to: CGPoint(x: 4, y: h * 0.25), control: CGPoint(x: 2, y: h * 0.6))
            ctx.fill(p, with: .color(Palette.kraft.color.opacity(0.75)))
            ctx.stroke(p, with: .color(theme.ink.color.opacity(0.8)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            // Papers poking out
            var paper = Path()
            paper.move(to: CGPoint(x: w * 0.2, y: h * 0.36))
            paper.addLine(to: CGPoint(x: w * 0.26, y: h * 0.08))
            paper.addLine(to: CGPoint(x: w * 0.7, y: h * 0.12))
            paper.addLine(to: CGPoint(x: w * 0.68, y: h * 0.35))
            ctx.stroke(paper, with: .color(theme.ink.color.opacity(0.6)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            ctx.stroke(Path(Sketch.spark(in: CGRect(x: w * 0.72, y: -h * 0.1, width: h * 0.4, height: h * 0.4), rays: 8, seed: 3)),
                       with: .color(Palette.clay.color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        .opacity(0.85)
    }
}
