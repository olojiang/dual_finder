import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("accentName") private var accentName = AccentChoice.blue.rawValue

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }

            Picker("Accent", selection: $accentName) {
                ForEach(AccentChoice.allCases) { accent in
                    Text(accent.label).tag(accent.rawValue)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
