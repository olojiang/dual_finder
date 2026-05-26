import SwiftUI
import DualFinderCore

struct ContentView: View {
    @ObservedObject var model: DualFinderViewModel

    var body: some View {
        VStack(spacing: 0) {
            AppToolbar(model: model)
            Divider()
            HStack(spacing: 0) {
                FilePaneView(side: .left, model: model)
                Divider()
                FilePaneView(side: .right, model: model)
            }
            Divider()
            StatusBar(message: model.statusMessage)
        }
        .background(.background)
    }
}

private struct AppToolbar: View {
    @ObservedObject var model: DualFinderViewModel
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("accentName") private var accentName = AccentChoice.blue.rawValue

    var body: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "arrow.clockwise", help: "Refresh both panes") {
                model.refreshAll()
            }
            IconButton(systemName: "doc.on.doc", help: "Copy left selection to right") {
                model.copySelection(from: .left)
            }
            IconButton(systemName: "doc.on.doc.fill", help: "Copy right selection to left") {
                model.copySelection(from: .right)
            }
            IconButton(systemName: "arrow.right.arrow.left", help: "Move left selection to right") {
                model.moveSelection(from: .left)
            }
            Toggle(isOn: $model.showHiddenFiles) {
                Image(systemName: model.showHiddenFiles ? "eye" : "eye.slash")
            }
            .toggleStyle(.button)
            .help("Show hidden files")

            Spacer()

            Picker("", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .help("Appearance")

            Picker("", selection: $accentName) {
                ForEach(AccentChoice.allCases) { accent in
                    Text(accent.label).tag(accent.rawValue)
                }
            }
            .frame(width: 120)
            .help("Accent color")

            IconButton(systemName: "doc.text.magnifyingglass", help: "Open log folder") {
                model.openLogFolder()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct StatusBar: View {
    let message: String

    var body: some View {
        HStack {
            Text(message.isEmpty ? "Ready" : message)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
    }
}
