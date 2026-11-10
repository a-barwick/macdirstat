import AppKit
import SwiftUI

@main
struct MacDirStatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("MacDirStat", id: "main") {
            ContentView(state: state)
                .onAppear {
                    appDelegate.state = state
                    // `--scan <path>` starts mapping straight away (handy from the command line).
                    let args = CommandLine.arguments
                    if let i = args.firstIndex(of: "--scan"), i + 1 < args.count, state.phase == .welcome {
                        state.scan(URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath))
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Map a Folder…") { state.chooseFolder() }
                    .keyboardShortcut("o")
                Button("Map Home Folder") { state.scan(URL(fileURLWithPath: NSHomeDirectory())) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Map Macintosh HD") { state.scan(URL(fileURLWithPath: "/")) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Rescan") { state.rescan() }
                    .keyboardShortcut("r")
                    .disabled(state.root == nil || state.isScanning)
            }
            CommandGroup(after: .newItem) {
                Button("Ask \(state.preferredAgent?.name ?? "an Agent") About This Scan") { state.askPreferredAgent() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(state.preferredAgent == nil || state.root == nil || state.isScanning)
                Menu("Ask an Agent") {
                    if state.agents.isEmpty {
                        Button("No agent CLIs found") {}.disabled(true)
                    } else {
                        ForEach(state.agents) { agent in
                            Button("Ask \(agent.name)") { state.askAgent(agent) }
                        }
                    }
                    Divider()
                    Menu("Open in Terminal") {
                        ForEach(state.terminals) { terminal in
                            Button {
                                state.preferredTerminal = terminal
                            } label: {
                                if terminal == state.activeTerminal {
                                    Label(terminal.name, systemImage: "checkmark")
                                } else {
                                    Text(terminal.name)
                                }
                            }
                        }
                    }
                }
                .disabled(state.root == nil || state.isScanning)
                Divider()
                Button("Copy Report") { state.copyReport() }
                    .disabled(state.root == nil || state.isScanning)
                Button("Save Report…") { state.saveReport() }
                    .keyboardShortcut("s")
                    .disabled(state.root == nil || state.isScanning)
            }
            CommandMenu("Map") {
                Button("Zoom Into Selection") { if let s = state.selection { state.zoom(into: s) } }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .disabled(state.selection == nil)
                Button("Zoom Out") { state.zoomOut() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!state.canZoomOut)
                Button("Back to the Top") { state.zoomToRoot() }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                    .disabled(!state.canZoomOut)
                Divider()
                Button("Reveal in Finder") { if let s = state.selection { state.revealInFinder(s) } }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(state.selection == nil)
                Button("Copy Path") { if let s = state.selection { state.copyPath(s) } }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(state.selection == nil)
                Button("Move to Trash…") { if let s = state.selection { state.moveToTrash(s) } }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(state.selection?.parent == nil)
                Divider()
                Picker("Style", selection: $state.style) {
                    ForEach(TreemapStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Hand-written Labels", isOn: $state.showLabels)
                    .keyboardShortcut("l")
            }
            CommandMenu("Paper") {
                ForEach(Array(Theme.all.enumerated()), id: \.element.id) { i, theme in
                    Button("\(theme.name) — \(theme.blurb)") { state.theme = theme }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in self.state?.scan(url) }
    }
}
