import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("accentName") private var accentName = AccentChoice.blue.rawValue

    var body: some View {
        TabView {
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
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            ShortcutMatrixSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 720, height: 540)
    }
}

private struct ShortcutMatrixSettingsView: View {
    @State private var bindings: [AppShortcutAction: AppShortcutBinding] = [:]

    private var groupedActions: [(String, [AppShortcutAction])] {
        let groups = Dictionary(grouping: AppShortcutAction.allCases, by: \.group)
        return ["Commands", "Navigation", "Tabs", "File Operations"].compactMap { group in
            guard let actions = groups[group] else { return nil }
            return (group, actions)
        }
    }

    private var conflicts: Set<AppShortcutBinding> {
        let grouped = Dictionary(grouping: AppShortcutAction.allCases) { action in
            binding(for: action)
        }
        return Set(grouped.compactMap { binding, actions in
            actions.count > 1 ? binding : nil
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Shortcut Matrix")
                    .font(.headline)
                Spacer()
                Button("Reset Defaults") {
                    AppShortcutMatrix.reset()
                    loadBindings()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            List {
                ForEach(groupedActions, id: \.0) { group, actions in
                    Section(group) {
                        ForEach(actions) { action in
                            ShortcutMatrixRow(
                                action: action,
                                binding: bindingForAction(action),
                                isConflicting: conflicts.contains(binding(for: action))
                            )
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .onAppear(perform: loadBindings)
    }

    private func loadBindings() {
        bindings = Dictionary(uniqueKeysWithValues: AppShortcutAction.allCases.map { action in
            (action, AppShortcutMatrix.binding(for: action))
        })
    }

    private func binding(for action: AppShortcutAction) -> AppShortcutBinding {
        bindings[action] ?? AppShortcutMatrix.binding(for: action)
    }

    private func bindingForAction(_ action: AppShortcutAction) -> Binding<AppShortcutBinding> {
        Binding(
            get: { binding(for: action) },
            set: { nextBinding in
                bindings[action] = nextBinding
                AppShortcutMatrix.setBinding(nextBinding, for: action)
            }
        )
    }
}

private struct ShortcutMatrixRow: View {
    let action: AppShortcutAction
    @Binding var binding: AppShortcutBinding
    let isConflicting: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .lineLimit(1)
                    Text(binding.displayText)
                        .font(.caption)
                        .foregroundStyle(isConflicting ? .orange : .secondary)
                        .monospaced()
                }
                .gridColumnAlignment(.leading)
                .frame(width: 210, alignment: .leading)

                Picker("Key", selection: keyBinding) {
                    ForEach(AppShortcutMatrix.allowedKeys) { choice in
                        Text(choice.label).tag(choice.id)
                    }
                }
                .labelsHidden()
                .frame(width: 105)

                HStack(spacing: 6) {
                    ForEach(AppShortcutModifier.allCases) { modifier in
                        Toggle(isOn: modifierBinding(modifier)) {
                            Text(modifier.label)
                                .font(.callout.weight(.semibold))
                                .frame(width: 18)
                        }
                        .toggleStyle(.button)
                        .help(modifier.rawValue.capitalized)
                    }
                }

                if isConflicting {
                    Label("Conflict", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(" ")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { binding.key },
            set: { key in
                guard let choice = AppShortcutMatrix.allowedKeys.first(where: { $0.id == key }) else { return }
                var nextBinding = binding
                nextBinding.key = choice.id
                nextBinding.keyCode = choice.keyCode
                binding = nextBinding
            }
        )
    }

    private func modifierBinding(_ modifier: AppShortcutModifier) -> Binding<Bool> {
        Binding(
            get: { binding.modifiers.contains(modifier) },
            set: { isOn in
                var nextBinding = binding
                if isOn {
                    nextBinding.modifiers.insert(modifier)
                } else {
                    nextBinding.modifiers.remove(modifier)
                }
                binding = nextBinding
            }
        )
    }
}
