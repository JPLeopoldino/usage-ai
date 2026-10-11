import SwiftUI
import UsageCore

/// The window that opens from the menu bar item.
struct UsagePopoverView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(UsageStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let providers = store.shownProviders
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 8)

            if providers.isEmpty {
                Divider()
                emptyState
            } else {
                ForEach(providers) { provider in
                    Divider()
                    ProviderSectionView(
                        provider: provider,
                        status: store.status(provider),
                        refreshInterval: settings.refreshInterval,
                        perform: { perform($0, for: provider) }
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(width: 340)
        .background(PanelWindowObserver { environment.menuDidOpen() })
    }

    private var header: some View {
        HStack {
            Text("Usage AI")
                .font(.headline)
            Spacer()
            Button {
                showSettings(nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",")
            .help("Settings…")
            .accessibilityLabel("Settings…")
        }
    }

    /// Shown until at least one service is set up. Services that still need setup live in Settings only.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Services Set Up", systemImage: "gauge.with.dots.needle.0percent")
        } description: {
            Text("Connect Claude, Cursor or OpenAI in Settings to see your usage here.")
        } actions: {
            Button("Open Settings…") { showSettings(.accounts) }
        }
        .padding(.vertical, 12)
    }

    private func perform(_ action: ProblemDescription.Action, for provider: ProviderID) {
        switch action {
        case .openSettings:
            showSettings(.accounts)
        case .grantKeychainAccess, .retry:
            environment.refreshNow(provider, userInitiated: true)
        case .openCursor:
            ExternalApps.openCursor()
        }
    }

    private func showSettings(_ tab: SettingsOpener.Tab?) {
        SettingsOpener.open(openSettings, tab: tab)
    }
}
