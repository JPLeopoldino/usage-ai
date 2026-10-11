import SwiftUI
import UsageCore

struct SettingsView: View {
    @AppStorage(SettingsOpener.tabDefaultsKey) private var tab = SettingsOpener.Tab.general.rawValue

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsOpener.Tab.general.rawValue)
            AccountsSettingsView()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsOpener.Tab.accounts.rawValue)
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsOpener.Tab.about.rawValue)
        }
    }
}

extension View {
    /// Panes share a width and are as tall as their content, so the window fits the current pane.
    /// A pane that would be too tall for small screens passes a height and scrolls instead.
    @ViewBuilder
    func settingsPane(height: CGFloat? = nil) -> some View {
        if let height {
            frame(width: 520, height: height)
        } else {
            frame(width: 520)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Connected · Max 5x", "Checking…" or the current problem.
struct ProviderStatusRow: View {
    let provider: ProviderID
    @Environment(UsageStore.self) private var store

    var body: some View {
        let status = store.status(provider)
        LabeledContent("Status") {
            HStack(spacing: 6) {
                if status.isLoading {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                } else if let error = status.error {
                    let problem = ProblemDescription(error, provider: provider)
                    Image(systemName: problem.isWarning ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(problem.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    Text(problem.message)
                } else if let snapshot = status.snapshot {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    if let plan = snapshot.planName {
                        Text("Connected · \(plan)")
                    } else {
                        Text("Connected")
                    }
                } else {
                    Text("Not checked yet")
                }
            }
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
        }
    }
}
