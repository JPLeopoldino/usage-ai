import AppKit
import SwiftUI
import UsageCore

struct AccountsSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppSettings.self) private var settings

    @State private var bridgeState: ClaudeStatusLineBridge.State = .notInstalled
    @State private var confirmingInstall = false
    @State private var bridgeError: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Show Claude", isOn: enabled(.claude))
                    .controlSize(.mini)
                Picker("Source", selection: $settings.claudeSource) {
                    Text("Claude Code status line").tag(ClaudeSource.statusLineBridge)
                    Text("OAuth endpoint (unofficial)").tag(ClaudeSource.oauth)
                }
                .onChange(of: settings.claudeSource) { environment.refreshNow(.claude) }

                switch settings.claudeSource {
                case .statusLineBridge:
                    bridgeControls
                    planPicker
                case .oauth:
                    oauthControls
                }
                ProviderStatusRow(provider: .claude)
            } header: {
                ProviderHeader(provider: .claude)
            } footer: {
                switch settings.claudeSource {
                case .statusLineBridge:
                    Text("Claude Code passes your plan limits to its status line. Usage AI adds a small script there that saves them and keeps your current status line. Usage updates while you use Claude Code. Per-model limits, such as Fable, need the OAuth source.")
                case .oauth:
                    Label("Reads the login Claude Code keeps in the Keychain and calls an undocumented endpoint. It adds per-model limits, but Anthropic's terms restrict using subscription logins in other tools. Use at your own risk.", systemImage: "exclamationmark.triangle.fill")
                }
            }

            Section {
                Toggle("Show Cursor", isOn: enabled(.cursor))
                    .controlSize(.mini)
                Picker("Session", selection: $settings.cursorSource) {
                    Text("From the Cursor app").tag(CredentialSource.automatic)
                    Text("Session cookie").tag(CredentialSource.manual)
                }
                .onChange(of: settings.cursorSource) { environment.refreshNow(.cursor) }
                if settings.cursorSource == .manual {
                    SecretField(title: "Cookie", account: .cursorManualCookie, prompt: "WorkosCursorSessionToken") {
                        environment.refreshNow(.cursor)
                    }
                }
                ProviderStatusRow(provider: .cursor)
            } header: {
                ProviderHeader(provider: .cursor)
            } footer: {
                if settings.cursorSource == .manual {
                    Text("Copy the value of the WorkosCursorSessionToken cookie from cursor.com in your browser.")
                } else {
                    Text("Uses the session of the Cursor app on this Mac. Nothing to set up.")
                }
            }

            Section {
                Toggle("Show OpenAI", isOn: enabled(.openAI))
                    .controlSize(.mini)
                SecretField(title: "Admin key", account: .openAIAdminKey, prompt: "sk-admin-…") {
                    environment.refreshNow(.openAI)
                }
                TextField("Monthly budget", value: $settings.openAIMonthlyBudget, format: .currency(code: "USD"))
                    .onSubmit { environment.refreshNow(.openAI) }
                TextField("Project ID", text: $settings.openAIProjectID, prompt: Text("All projects"))
                    .onSubmit { environment.refreshNow(.openAI) }
                ProviderStatusRow(provider: .openAI)
            } header: {
                ProviderHeader(provider: .openAI)
            } footer: {
                Text("Shows spend from the official Costs API. Only organization owners can create an Admin key; a read-only one is enough. [Create a key](https://platform.openai.com/settings/organization/admin-keys)")
            }
        }
        .formStyle(.grouped)
        .settingsPane(height: 600)
        .onAppear { bridgeState = environment.bridge.state() }
        .alert("Connect Claude Code?", isPresented: $confirmingInstall) {
            Button("Connect") { installBridge() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(installMessage)
        }
        .alert("Couldn't update Claude Code settings", isPresented: Binding(
            get: { bridgeError != nil }, set: { if !$0 { bridgeError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bridgeError ?? "")
        }
    }

    // MARK: Claude

    @ViewBuilder
    private var bridgeControls: some View {
        LabeledContent("Status line") {
            HStack {
                if bridgeState == .installed {
                    Button("Disconnect") { uninstallBridge() }
                } else {
                    Button("Connect…") { confirmingInstall = true }
                }
                Button("Copy Snippet") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(environment.bridge.settingsSnippet, forType: .string)
                }
                .help("Copy the settings to add to ~/.claude/settings.json yourself")
            }
        }
    }

    private var planPicker: some View {
        @Bindable var settings = settings
        return Picker(selection: $settings.claudePlan) {
            Text("Don't show").tag(ClaudePlan.unspecified)
            ForEach(ClaudePlan.allCases.filter { $0 != .unspecified }, id: \.self) { plan in
                Text(verbatim: plan.displayName ?? "").tag(plan)
            }
        } label: {
            Text("Plan")
            Text("Shown next to Claude in the menu. Claude Code's status line doesn't include it.")
        }
        .onChange(of: settings.claudePlan) { environment.refreshNow(.claude) }
    }

    private var oauthControls: some View {
        LabeledContent("Keychain") {
            Button("Allow Access…") { environment.refreshNow(.claude, userInitiated: true) }
        }
    }

    private var installMessage: String {
        var message = String(localized: "Usage AI will point the status line in ~/.claude/settings.json to its script. A backup is saved next to it as settings.json.usage-ai-backup.")
        if case .otherStatusLine = bridgeState {
            message += " " + String(localized: "Your current status line keeps working.")
        }
        return message
    }

    private func installBridge() {
        guard let script = Bundle.main.url(forResource: "claude-statusline", withExtension: "sh") else {
            bridgeError = String(localized: "The bridge script is missing from the app.")
            return
        }
        do {
            try environment.bridge.install(script: script)
        } catch {
            bridgeError = message(for: error)
        }
        bridgeState = environment.bridge.state()
        environment.refreshNow(.claude)
    }

    private func uninstallBridge() {
        do {
            try environment.bridge.uninstall()
        } catch {
            bridgeError = message(for: error)
        }
        bridgeState = environment.bridge.state()
        environment.refreshNow(.claude)
    }

    private func message(for error: ClaudeStatusLineBridge.BridgeError) -> String {
        switch error {
        case .unreadableSettings: String(localized: "~/.claude/settings.json isn't valid JSON. Fix it or use Copy Snippet.")
        case .writeFailed: String(localized: "The file couldn't be written. Check its permissions.")
        }
    }

    private func enabled(_ provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { settings.enabledProviders.contains(provider) },
            set: { isOn in
                settings.setEnabled(isOn, provider)
                if isOn { environment.refreshNow(provider) }
            }
        )
    }
}

/// A section header with the service's logo.
struct ProviderHeader: View {
    let provider: ProviderID

    var body: some View {
        Label {
            Text(provider.displayName)
        } icon: {
            ProviderLogo(provider: provider, size: 14)
        }
    }
}

/// A secret kept in the Keychain. Once saved, only its last characters are shown.
struct SecretField: View {
    let title: LocalizedStringKey
    let account: KeychainStore.Account
    let prompt: String
    let onChange: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @State private var draft = ""
    @State private var savedSuffix: String?
    @State private var editing = false

    var body: some View {
        LabeledContent(title) {
            if let savedSuffix, !editing {
                HStack {
                    Text(verbatim: "••••\(savedSuffix)")
                        .monospaced()
                        .foregroundStyle(.secondary)
                    Button("Replace") { editing = true }
                    Button("Remove", role: .destructive) {
                        environment.keychain.delete(account)
                        self.savedSuffix = nil
                        onChange()
                    }
                }
            } else {
                HStack {
                    SecureField(prompt, text: $draft)
                        .labelsHidden()
                        .frame(minWidth: 180)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if editing {
                        Button("Cancel") { editing = false; draft = "" }
                    }
                }
            }
        }
        .onAppear(perform: loadSuffix)
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, environment.keychain.write(value, for: account) else { return }
        draft = ""
        editing = false
        loadSuffix()
        onChange()
    }

    private func loadSuffix() {
        savedSuffix = environment.keychain.read(account).map { String($0.suffix(4)) }
    }
}
