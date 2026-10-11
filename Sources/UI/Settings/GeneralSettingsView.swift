import SwiftUI
import UsageCore

struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(UsageStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let launchAtLogin = environment.launchAtLogin

        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                    .controlSize(.mini)
                if launchAtLogin.requiresApproval {
                    LabeledContent {
                        Button("Open Login Items…") { launchAtLogin.openSystemSettings() }
                    } label: {
                        Text("Allow Usage AI in System Settings › Login Items.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker("Refresh every", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.refreshIntervals, id: \.self) { interval in
                        Text(Duration.seconds(interval).formatted(.units(allowed: [.minutes], width: .wide)))
                            .tag(interval)
                    }
                }
                Toggle("Refresh when the menu opens", isOn: $settings.refreshOnOpen)
                    .controlSize(.mini)
            } header: {
                Text("Refresh")
            } footer: {
                Text("Some services have their own minimum: Cursor 1 min, Claude (OAuth) 2 min, OpenAI 10 min.")
            }

            Section("Menu Bar") {
                Picker("Show", selection: $settings.displayMode) {
                    Text("Icon only").tag(MenuBarDisplayMode.iconOnly)
                    Text("Highest usage").tag(MenuBarDisplayMode.highest)
                    Text("A metric I choose").tag(MenuBarDisplayMode.pinned)
                    Text("Each service").tag(MenuBarDisplayMode.perService)
                }
                if settings.displayMode == .pinned {
                    Picker("Metric", selection: $settings.pinnedMetricID) {
                        Text("Highest usage").tag(String?.none)
                        ForEach(pinnableMetrics, id: \.id) { item in
                            Text(item.title).tag(String?.some(item.id))
                        }
                    }
                }
                Toggle("Use color when near a limit", isOn: $settings.colorizeMenuBar)
                    .controlSize(.mini)
                LabeledContent("Preview") {
                    MenuBarPreview(store: store, settings: settings)
                }
            }

            Section {
                LabeledContent {
                    Button("Quit") { NSApp.terminate(nil) }
                } label: {
                    Text("Quit Usage AI")
                    Text("Usage AI leaves the menu bar until you open it again.")
                }
            }
        }
        .formStyle(.grouped)
        .settingsPane()
        .onAppear { launchAtLogin.refresh() }
    }

    private var pinnableMetrics: [(id: String, title: String)] {
        store.shownProviders.flatMap { provider -> [(id: String, title: String)] in
            let metrics = store.status(provider).snapshot?.metrics ?? []
            return metrics.map { (id: $0.id, title: "\(provider.displayName) · \($0.role.title)") }
        }
    }
}

private struct MenuBarPreview: View {
    let store: UsageStore
    let settings: AppSettings

    var body: some View {
        let summary = MenuBarSummary(
            statuses: store.statuses,
            enabled: store.shownProviders,
            mode: settings.displayMode,
            pinnedMetricID: settings.pinnedMetricID
        )
        Image(nsImage: MenuBarImage.render(summary, colorize: settings.colorizeMenuBar))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel(MenuBarImage.accessibilityText(summary))
    }
}
