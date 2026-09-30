import SwiftUI

struct MainView: View {
    @ObservedObject var state: AppState

    private var theme: Theme { state.theme }

    var body: some View {
        VSplitView {
            HSplitView {
                panel(title: "The Tree", note: state.root.map { "\(Format.count($0.fileCount)) files" }) {
                    DirectoryOutline(state: state)
                }
                .frame(minWidth: 380, idealWidth: 720, maxWidth: .infinity)

                panel(title: "File Types", note: "\(state.extensionStats.count) kinds") {
                    ExtensionList(state: state)
                }
                .frame(minWidth: 210, idealWidth: 270, maxWidth: 420)
            }
            .frame(minHeight: 180, idealHeight: 300)

            TreemapPanel(state: state)
                .frame(minHeight: 200, idealHeight: 420, maxHeight: .infinity)
        }
    }

    private func panel<Content: View>(title: String, note: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(Fonts.serif(15, weight: .semibold))
                    .foregroundStyle(theme.ink.color)
                if let note {
                    Text(note)
                        .font(Fonts.hand(12))
                        .foregroundStyle(theme.inkSoft.color)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
            content()
        }
        .background(theme.paper.color)
    }
}

// MARK: - Treemap panel

struct TreemapPanel: View {
    @ObservedObject var state: AppState
    private var theme: Theme { state.theme }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("The Map")
                    .font(Fonts.serif(15, weight: .semibold))
                    .foregroundStyle(theme.ink.color)
                Breadcrumbs(state: state)
                Spacer(minLength: 8)
                Picker("", selection: $state.style) {
                    ForEach(TreemapStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
                .help("How should the map be drawn?")
                Toggle(isOn: $state.showLabels) {
                    Image(systemName: "tag")
                }
                .toggleStyle(.button)
                .help("Hand-written labels on the big folders")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ZStack(alignment: .bottomLeading) {
                TreemapView(state: state)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(SketchRect(seed: 404, roughness: 1.5).stroke(theme.ink.color.opacity(0.55), lineWidth: 1.4))
                    .padding(.horizontal, 10)
            }
            .padding(.bottom, 6)

            FooterBar(state: state, hover: state.hover)
        }
        .background(theme.paper.color)
    }
}

struct Breadcrumbs: View {
    @ObservedObject var state: AppState
    private var theme: Theme { state.theme }

    var body: some View {
        let chain = state.viewRoot?.ancestry ?? []
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(chain.enumerated()), id: \.offset) { i, node in
                    if i > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(theme.inkSoft.color.opacity(0.6))
                    }
                    Button {
                        state.viewRoot = node
                    } label: {
                        Text(node.displayName)
                            .font(Fonts.hand(13, bold: i == chain.count - 1))
                            .foregroundStyle(i == chain.count - 1 ? theme.accent.color : theme.inkSoft.color)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 520)
    }
}

// MARK: - Footer

struct FooterBar: View {
    @ObservedObject var state: AppState
    @ObservedObject var hover: HoverState
    private var theme: Theme { state.theme }

    var body: some View {
        HStack(spacing: 10) {
            if let node = hover.node ?? state.selection {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(node.isDirectory ? theme.accent.color : state.color(for: node).color)
                Text(Format.path(node.path))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.ink.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Format.bytes(node.size))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.ink.color)
                Text(Whimsy.comparison(for: node.size, seed: node.name.utf8.count))
                    .font(Fonts.hand(12.5))
                    .foregroundStyle(theme.accent.color)
                    .lineLimit(1)
            } else if let root = state.root {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.accent.color)
                Text("Mapped \(Format.bytes(root.size)) in \(Format.count(root.fileCount)) files in \(Format.duration(state.lastScanDuration)). Hover to peek, click to select, double-click to dive in.")
                    .font(Fonts.hand(12.5))
                    .foregroundStyle(theme.inkSoft.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if state.unreadableCount > 0 {
                Label("\(Format.count(state.unreadableCount)) folders kept their secrets", systemImage: "lock")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkSoft.color)
                    .help("macOS didn't let us look inside these. Grant MacDirStat Full Disk Access in System Settings › Privacy & Security for a complete map.")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(theme.panel.color)
        .overlay(alignment: .top) { Rectangle().fill(theme.line.color).frame(height: 1) }
    }
}

// MARK: - Extensions

struct ExtensionList: View {
    @ObservedObject var state: AppState
    private var theme: Theme { state.theme }

    var body: some View {
        let stats = Array(state.extensionStats.prefix(400))
        let total = max(1, state.root?.size ?? 1)
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(stats) { stat in
                    ExtensionRow(stat: stat, total: total, color: state.color(forExtension: stat.id),
                                 selected: state.selectedExtension == stat.id, theme: theme)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25)) {
                                state.selectedExtension = state.selectedExtension == stat.id ? nil : stat.id
                            }
                        }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .background(theme.paper.color)
    }
}

private struct ExtensionRow: View {
    let stat: ExtensionStat
    let total: Int64
    let color: RGB
    let selected: Bool
    let theme: Theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Swatch(color: color, seed: UInt64(stat.id), size: 13)
            VStack(alignment: .leading, spacing: 0) {
                Text(stat.label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.ink.color)
                    .lineLimit(1)
                Text("\(Format.count(stat.count)) file\(stat.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.inkSoft.color)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Format.bytes(stat.bytes))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(theme.ink.color)
                Text(Format.percent(stat.bytes, of: total))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(theme.inkSoft.color)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            WobblyRoundedRect(seed: UInt64(stat.id) &+ 5, radius: 7, wobble: 0.8)
                .fill(selected ? theme.accent.color.opacity(0.22) : (hovering ? theme.panel.color : .clear))
        )
        .overlay(
            selected ? SketchRect(seed: UInt64(stat.id), roughness: 1.1).stroke(theme.accent.color, lineWidth: 1.3) : nil
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(selected ? "Click again to stop highlighting" : "Highlight every \(stat.label) file on the map")
    }
}
