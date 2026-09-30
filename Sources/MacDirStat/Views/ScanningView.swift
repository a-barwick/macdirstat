import SwiftUI

struct ScanningView: View {
    @ObservedObject var state: AppState

    private var theme: Theme { state.theme }

    var body: some View {
        VStack(spacing: 20) {
            SpinningSpark(color: theme.accent.color, size: 110, lineWidth: 7)

            Text("\(state.scanVerb)…")
                .font(Fonts.serif(32, weight: .medium))
                .foregroundStyle(theme.ink.color)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: state.scanVerb)

            Text(state.scanPath == "/" ? "Macintosh HD" : Format.path(state.scanPath))
                .font(Fonts.hand(16))
                .foregroundStyle(theme.inkSoft.color)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 28) {
                stat(Format.count(state.progress.files), "files")
                stat(Format.count(state.progress.dirs), "folders")
                stat(Format.bytes(state.progress.bytes), "found")
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 26)
            .background(WobblyRoundedRect(seed: 77, radius: 14, wobble: 1.4).fill(theme.panel.color))
            .overlay(SketchRect(seed: 78, roughness: 1.4).stroke(theme.ink.color.opacity(0.5), lineWidth: 1.2))

            Text(Format.path(state.progress.currentPath))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.inkSoft.color.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 560)

            Button("Never mind") { state.cancelScan() }
                .buttonStyle(SketchButtonStyle(theme: theme, seed: 31, compact: true))
                .keyboardShortcut(.cancelAction)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Fonts.serif(22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.ink.color)
                .contentTransition(.numericText())
            Text(label)
                .font(Fonts.hand(13))
                .foregroundStyle(theme.inkSoft.color)
        }
        .frame(minWidth: 90)
    }
}
