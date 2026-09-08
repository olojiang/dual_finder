import DualFinderCore
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

                ShowWindowHotkeySettingsSection()
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            ShortcutMatrixSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            TranslationSettingsView()
                .tabItem {
                    Label("Translation", systemImage: "character.book.closed")
                }
        }
        .frame(width: 820, height: 640)
    }
}

private struct TranslationSettingsView: View {
    @State private var configuration: TranslationConfiguration
    @State private var selectedProviderID: UUID?
    @State private var statusMessage: String?
    @State private var isTesting = false

    private let store: TranslationConfigurationStore

    init(store: TranslationConfigurationStore = TranslationConfigurationStore()) {
        self.store = store
        let configuration = store.load()
        _configuration = State(initialValue: configuration)
        _selectedProviderID = State(initialValue: configuration.defaultProviderID ?? configuration.providers.first?.id)
    }

    var body: some View {
        HStack(spacing: 16) {
            providerList
                .frame(width: 220)

            Divider()

            if let index = selectedProviderIndex {
                providerEditor(index: index)
            } else {
                ContentUnavailableView("No Provider", systemImage: "plus", description: Text("Add an OpenAI-compatible provider to translate files."))
            }
        }
        .padding(20)
        .onChange(of: selectedProviderID) { _, _ in
            ensureDefaultModelIsValid()
        }
        .onAppear {
            ensureDefaultModelIsValid()
            save()
        }
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Providers")
                .font(.headline)
            List(selection: $selectedProviderID) {
                ForEach(configuration.providers) { provider in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name.isEmpty ? "Unnamed Provider" : provider.name)
                        Text(provider.models.isEmpty ? "No models" : "\(provider.models.count) model(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(provider.id)
                }
                .onDelete(perform: deleteProviders)
            }
            HStack {
                Button {
                    addProvider()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Provider")
                Button {
                    deleteSelectedProvider()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedProviderIndex == nil)
                .help("Delete Provider")
                Spacer()
            }
        }
    }

    private func providerEditor(index: Int) -> some View {
        let provider = providerBinding(for: index)
        return Form {
            Section("OpenAI-Compatible API") {
                TextField("Provider name", text: provider.name)
                TextField("API URL", text: provider.baseURL)
                    .textContentType(.URL)
                Text("可填写 /v1（使用或测试时自动补齐 /chat/completions），也可以填写完整的 /chat/completions 地址。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SecureField("Token", text: provider.token)
                TextField("Model names (comma separated)", text: modelsBinding(for: index))

                Picker("Default model", selection: defaultModelBinding) {
                    if configuration.providers[index].models.isEmpty {
                        Text("No models configured").tag("")
                    } else {
                        if configuration.defaultProviderID != configuration.providers[index].id {
                            Text("Not the default provider").tag("")
                        }
                        ForEach(configuration.providers[index].models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                HStack {
                    if configuration.defaultProviderID != configuration.providers[index].id {
                        Button("Use as Default") {
                            configuration.defaultProviderID = configuration.providers[index].id
                            configuration.defaultModelName = configuration.providers[index].models.first
                            save()
                        }
                    }
                    Button(isTesting ? "Testing..." : "Test Connection") {
                        testConnection(for: configuration.providers[index])
                    }
                    .disabled(isTesting || configuration.providers[index].models.isEmpty)
                    Button("Save") {
                        save()
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("The selected provider and model are used by both translation actions in the file right-click menu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var selectedProviderIndex: Int? {
        guard let selectedProviderID else { return nil }
        return configuration.providers.firstIndex { $0.id == selectedProviderID }
    }

    private var defaultModelBinding: Binding<String> {
        Binding(
            get: { configuration.defaultProviderID == selectedProviderID ? (configuration.defaultModelName ?? "") : "" },
            set: { model in
                configuration.defaultProviderID = selectedProviderID
                configuration.defaultModelName = model
                save()
            }
        )
    }

    private func providerBinding(for index: Int) -> Binding<TranslationProvider> {
        Binding(
            get: { configuration.providers[index] },
            set: { provider in
                configuration.providers[index] = provider
                save()
            }
        )
    }

    private func modelsBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { configuration.providers[index].models.joined(separator: ", ") },
            set: { value in
                configuration.providers[index].models = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                ensureDefaultModelIsValid()
                save()
            }
        )
    }

    private func addProvider() {
        let provider = TranslationProvider(
            name: "New Provider",
            baseURL: "https://api.openai.com/v1",
            token: "",
            models: ["gpt-4o-mini"]
        )
        configuration.providers.append(provider)
        selectedProviderID = provider.id
        configuration.defaultProviderID = provider.id
        configuration.defaultModelName = provider.models[0]
        save()
    }

    private func deleteProviders(at offsets: IndexSet) {
        configuration.providers.remove(atOffsets: offsets)
        if let selectedProviderID, !configuration.providers.contains(where: { $0.id == selectedProviderID }) {
            self.selectedProviderID = configuration.providers.first?.id
        }
        ensureDefaultModelIsValid()
        save()
    }

    private func deleteSelectedProvider() {
        guard let index = selectedProviderIndex else { return }
        deleteProviders(at: IndexSet(integer: index))
    }

    private func ensureDefaultModelIsValid() {
        if let defaultProviderID = configuration.defaultProviderID,
           let provider = configuration.providers.first(where: { $0.id == defaultProviderID }) {
            if !provider.models.contains(configuration.defaultModelName ?? "") {
                configuration.defaultModelName = provider.models.first
            }
            return
        }
        if let provider = configuration.providers.first {
            configuration.defaultProviderID = provider.id
            configuration.defaultModelName = provider.models.first
            return
        }
        configuration.defaultProviderID = nil
        configuration.defaultModelName = nil
    }

    private func save() {
        store.save(configuration)
    }

    private func testConnection(for provider: TranslationProvider) {
        guard let modelName = configuration.defaultProviderID == provider.id ? configuration.defaultModelName : provider.models.first,
              !modelName.isEmpty
        else {
            statusMessage = "Select a model first."
            return
        }
        isTesting = true
        statusMessage = nil
        Task { @MainActor in
            do {
                _ = try await OpenAICompatibleTranslationClient().translateText(
                    "Hello",
                    provider: provider,
                    modelName: modelName
                )
                isTesting = false
                statusMessage = "Connection succeeded."
            } catch {
                isTesting = false
                statusMessage = error.localizedDescription
            }
        }
    }
}

private struct ShowWindowHotkeySettingsSection: View {
    @State private var binding = ShowWindowHotkeyStore().binding()
    @State private var statusMessage: String?

    private let store = ShowWindowHotkeyStore()

    var body: some View {
        Section("Global Window Shortcut") {
            LabeledContent("Active Binding", value: binding.displayLabel)
            Picker("Key", selection: keyBinding) {
                ForEach(ShowWindowHotkeyBinding.allowedKeys) { choice in
                    Text(choice.label).tag(choice.id)
                }
            }
            HStack(spacing: 6) {
                Text("Modifiers")
                Spacer()
                ForEach(ShowWindowHotkeyModifier.allCases) { modifier in
                    Toggle(isOn: modifierBinding(modifier)) {
                        Text(modifier.label)
                            .font(.callout.weight(.semibold))
                            .frame(width: 18)
                    }
                    .toggleStyle(.button)
                    .help(modifier.rawValue.capitalized)
                }
            }
            if !binding.isValid {
                Label("Use at least one of Command, Control, or Option.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Login Item Helper") {
                Text(HotkeyHelperLoginItem.isRegistered ? "Enabled" : "Not enabled")
            }
            Text(PrivacyPermissionGuide.showWindowHotkeyNotes)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Login Items") {
                    HotkeyHelperLoginItem.openLoginItemsSettings()
                }
                Button("Retry Helper Registration") {
                    if HotkeyHelperLoginItem.register() {
                        HotkeyHelperLoginItem.restartRunningHelperFromEmbeddedApp()
                    }
                }
                Button("Reset Shortcut") {
                    resetBinding()
                }
            }
        }
        .onAppear {
            binding = store.binding()
        }
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { binding.key },
            set: { key in
                guard let choice = ShowWindowHotkeyBinding.allowedKeys.first(where: { $0.id == key }) else { return }
                var nextBinding = binding
                nextBinding.key = choice.id
                nextBinding.keyCode = choice.keyCode
                applyBinding(nextBinding)
            }
        )
    }

    private func modifierBinding(_ modifier: ShowWindowHotkeyModifier) -> Binding<Bool> {
        Binding(
            get: { binding.modifiers.contains(modifier) },
            set: { isOn in
                var nextBinding = binding
                if isOn {
                    nextBinding.modifiers.insert(modifier)
                } else {
                    nextBinding.modifiers.remove(modifier)
                }
                applyBinding(nextBinding)
            }
        )
    }

    private func applyBinding(_ nextBinding: ShowWindowHotkeyBinding) {
        binding = nextBinding
        guard nextBinding.isValid else {
            statusMessage = "Shortcut not saved."
            return
        }

        do {
            try store.setBinding(nextBinding)
            statusMessage = "Saved. Running hotkey listeners reload automatically."
        } catch {
            statusMessage = "Could not save shortcut."
        }
    }

    private func resetBinding() {
        do {
            try store.reset()
            binding = store.binding()
            statusMessage = "Restored default \(binding.displayLabel)."
        } catch {
            statusMessage = "Could not reset shortcut."
        }
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
