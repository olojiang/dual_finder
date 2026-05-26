import SwiftUI
import DualFinderCore

@main
struct DualFinderApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DualFinderViewModel(logger: AppDelegate.sharedLogger)
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("accentName") private var accentName = AccentChoice.blue.rawValue

    var body: some Scene {
        WindowGroup("Dual Finder 纪") {
            ContentView(model: model)
                .frame(minWidth: 1_080, minHeight: 680)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
                .tint((AccentChoice(rawValue: accentName) ?? .blue).color)
                .onAppear {
                    model.checkFullDiskAccessOnLaunch()
                    model.refreshAll()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Left Tab") { model.addTab(on: .left) }
                    .keyboardShortcut("t", modifiers: [.command])
                Button("New Right Tab") { model.addTab(on: .right) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("Move Selection to Trash") {
                    model.trashActiveSelection()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(!model.hasActiveSelection)

                Button("Empty Trash") {
                    model.emptyTrash()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])

                Button("Open Selection in Ghostty or Terminal") {
                    let side = model.activePaneSide
                    model.openInTerminal(model.pane(for: side).selectedItemURLs, on: side)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(!model.hasActiveSelection)
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Absolute Path") {
                    let side = model.activePaneSide
                    model.copyAbsolutePaths(model.pane(for: side).selectedItemURLs, on: side)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!model.hasActiveSelection)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
