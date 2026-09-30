import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var state: AppState
    @State private var dropTargeted = false

    private var theme: Theme { state.theme }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(state: state)
            ZStack {
                switch state.phase {
                case .welcome:
                    WelcomeView(state: state)
                        .transition(.opacity)
                case .scanning:
                    ScanningView(state: state)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                case .ready:
                    MainView(state: state)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: state.phase)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(PaperBackground(theme: theme))
        .overlay(alignment: .bottom) { toast }
        .overlay { if dropTargeted { dropOverlay } }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { state.scan(url) }
            }
            return true
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .tint(theme.accent.color)
        .frame(minWidth: 900, minHeight: 620)
    }

    @ViewBuilder private var toast: some View {
        if let text = state.toast {
            HStack(spacing: 8) {
                SparkMark(color: theme.accent.color, lineWidth: 1.8, seed: 12)
                    .frame(width: 16, height: 16)
                Text(text)
                    .font(Fonts.hand(14))
                    .foregroundStyle(theme.ink.color)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(WobblyRoundedRect(seed: 55, radius: 12, wobble: 1.3).fill(theme.paper.color).shadow(color: .black.opacity(0.18), radius: 10, y: 4))
            .overlay(SketchRect(seed: 56, roughness: 1.3).stroke(theme.ink.color.opacity(0.7), lineWidth: 1.2))
            .padding(.bottom, 44)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var dropOverlay: some View {
        ZStack {
            theme.paper.color.opacity(0.85)
            VStack(spacing: 14) {
                SparkMark(color: theme.accent.color, lineWidth: 5)
                    .frame(width: 70, height: 70)
                Text("Drop it like it's hot")
                    .font(Fonts.serif(28, weight: .medium))
                    .foregroundStyle(theme.ink.color)
            }
            SketchRect(seed: 90, roughness: 3)
                .stroke(theme.accent.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10, 8]))
                .padding(24)
        }
        .allowsHitTesting(false)
    }
}

struct HeaderBar: View {
    @ObservedObject var state: AppState
    private var theme: Theme { state.theme }

    var body: some View {
        HStack(spacing: 10) {
            // Room for the traffic lights.
            Spacer().frame(width: 70)

            SparkMark(color: theme.accent.color, lineWidth: 2.4, seed: 7)
                .frame(width: 20, height: 20)
            Text("MacDirStat")
                .font(Fonts.serif(17, weight: .semibold))
                .foregroundStyle(theme.ink.color)

            Spacer()

            if state.phase == .ready {
                DoodleIconButton(systemName: "arrow.up", help: "Zoom out (⌘↑)", theme: theme) { state.zoomOut() }
                    .disabled(!state.canZoomOut)
                DoodleIconButton(systemName: "arrow.clockwise", help: "Rescan (⌘R)", theme: theme) { state.rescan() }
                DoodleIconButton(systemName: "folder.badge.plus", help: "Map another folder (⌘O)", theme: theme) { state.chooseFolder() }
                DoodleIconButton(systemName: "xmark", help: "Close this map", theme: theme) { state.closeScan() }
            }

            ThemeMenu(state: state)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(theme.panel.color)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.line.color).frame(height: 1)
        }
    }
}

struct ThemeMenu: View {
    @ObservedObject var state: AppState

    var body: some View {
        Menu {
            ForEach(Theme.all) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { state.theme = t }
                } label: {
                    if t == state.theme {
                        Label("\(t.name) — \(t.blurb)", systemImage: "checkmark")
                    } else {
                        Text("\(t.name) — \(t.blurb)")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(state.theme.accent.color).frame(width: 10, height: 10)
                Circle().fill(state.theme.paper.color).overlay(Circle().stroke(state.theme.ink.color.opacity(0.4), lineWidth: 0.7)).frame(width: 10, height: 10)
                Text(state.theme.name)
                    .font(Fonts.hand(13, bold: true))
                    .foregroundStyle(state.theme.ink.color)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(SketchRect(seed: 61, roughness: 1).stroke(state.theme.ink.color.opacity(0.35), lineWidth: 1))
        .help("Change the paper")
    }
}
