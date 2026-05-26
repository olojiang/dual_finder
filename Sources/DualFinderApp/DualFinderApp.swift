import SwiftUI
import DualFinderCore

@main
struct DualFinderApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DualFinderViewModel(logger: AppDelegate.sharedLogger)
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("accentName") private var accentName = AccentChoice.blue.rawValue

    var body: some Scene {
        WindowGroup("Dual Finder") {
            ContentView(model: model)
                .frame(minWidth: 1_080, minHeight: 680)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
                .tint((AccentChoice(rawValue: accentName) ?? .blue).color)
                .onAppear {
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
        }

        Settings {
            SettingsView()
        }
    }
}
