import AppKit
import SwiftUI
import UsageCore

struct AboutSettingsView: View {
    @Environment(UsageStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var copied = false

    static let repositoryURL = URL(string: "https://github.com/JPLeopoldino/usage-ai")!

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Usage AI")
                .font(.title2.weight(.semibold))
            Text("Version \(Self.version) (\(Self.build))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Your AI subscriptions' usage, in the menu bar.")
            Link("Source code on GitHub", destination: Self.repositoryURL)

            GroupBox {
                Text("Claude and Cursor usage comes from undocumented endpoints and files that can change at any time. Usage AI is not affiliated with Anthropic, Anysphere or OpenAI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
            .frame(maxWidth: 420)

            Button(copied ? "Copied" : "Copy Diagnostics") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(diagnostics, forType: .string)
                copied = true
            }
            .help("Copies states and error codes only — never tokens or usage values")
        }
        .padding(24)
        .settingsPane()
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// States and error codes only, so it is safe to paste in a GitHub issue.
    private var diagnostics: String {
        var lines = [
            "Usage AI \(Self.version) (\(Self.build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Refresh: \(Int(settings.refreshInterval))s, menu bar: \(settings.displayMode.rawValue)",
            "Claude source: \(settings.claudeSource.rawValue), Cursor source: \(settings.cursorSource.rawValue)",
            "Offline: \(store.isOffline)",
        ]
        for provider in ProviderID.allCases {
            let status = store.status(provider)
            let enabled = settings.enabledProviders.contains(provider)
            let error = status.error.map { String(describing: $0) } ?? "none"
            let metrics = status.snapshot?.metrics.map(\.id).joined(separator: ",") ?? "-"
            let age = status.snapshot.map { "\(Int(Date.now.timeIntervalSince($0.asOf)))s" } ?? "-"
            lines.append("\(provider.rawValue): enabled=\(enabled) error=\(error) failures=\(status.consecutiveFailures) metrics=[\(metrics)] age=\(age)")
        }
        return lines.joined(separator: "\n")
    }
}
