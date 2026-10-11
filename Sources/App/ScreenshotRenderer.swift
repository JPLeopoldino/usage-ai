#if DEBUG
import AppKit
import SwiftUI
import UsageCore

/// Debug builds only: `Usage AI -renderScreenshots <dir>` draws the menu and Settings with sample
/// data into PNGs (light and dark) and quits. Used for the README and to check layouts.
enum ScreenshotRenderer {
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-renderScreenshots"), index + 1 < arguments.count else {
            return false
        }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        Task { @MainActor in
            await render(to: directory)
            exit(0)
        }
        return true
    }

    private static func render(to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: "UsageAI.screenshots")!
        defaults.removePersistentDomain(forName: "UsageAI.screenshots")
        let settings = AppSettings(defaults: defaults)
        settings.claudePlan = .max5x
        let store = UsageStore(providers: SampleData.providers, settings: settings)
        await store.refreshAll(userInitiated: false)

        let emptyStore = UsageStore(providers: SampleData.notSetUp, settings: settings)
        await emptyStore.refreshAll(userInitiated: false)

        let environment = AppEnvironment.shared
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let popover = UsagePopoverView()
                .environment(environment).environment(store).environment(settings)
                .background(Color(nsColor: .windowBackgroundColor))
            write(popover, appearance: appearance, to: directory.appending(path: "menu-\(name).png"))

            let empty = UsagePopoverView()
                .environment(environment).environment(emptyStore).environment(settings)
                .background(Color(nsColor: .windowBackgroundColor))
            write(empty, appearance: appearance, to: directory.appending(path: "menu-empty-\(name).png"))

            for display in MenuBarDisplayMode.allCases {
                settings.displayMode = display
                let label = MenuBarLabel(store: store, settings: settings)
                    .padding(6)
                    .background(Color(nsColor: .windowBackgroundColor))
                write(label, appearance: appearance, to: directory.appending(path: "menubar-\(display.rawValue)-\(name).png"))
            }
            settings.displayMode = .highest

            let tabs: [(String, AnyView)] = [
                ("general", AnyView(GeneralSettingsView())),
                ("accounts", AnyView(AccountsSettingsView())),
                ("about", AnyView(AboutSettingsView())),
            ]
            for (tab, view) in tabs {
                let page = view
                    .environment(environment).environment(store).environment(settings)
                    .background(Color(nsColor: .windowBackgroundColor))
                write(page, appearance: appearance, to: directory.appending(path: "settings-\(tab)-\(name).png"))
            }
        }
    }

    private static func write(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        // Drawn at 2x so the images stay sharp on Retina displays.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Fixed snapshots so screenshots look the same on every machine.
private enum SampleData {
    struct StaticProvider: UsageProvider {
        let id: ProviderID
        let make: @Sendable (Date) -> Result<ProviderSnapshot, ProviderError>

        func pollingInterval(userInterval: TimeInterval, config: ProviderConfig) -> TimeInterval { userInterval }

        func fetch(_ context: FetchContext) async throws(ProviderError) -> ProviderSnapshot {
            try make(context.now).get()
        }
    }

    /// Nothing set up yet, for the menu's empty state.
    static let notSetUp: [any UsageProvider] = [
        StaticProvider(id: .claude) { _ in .failure(.needsAuth(.installClaudeBridge)) },
        StaticProvider(id: .cursor) { _ in .failure(.needsAuth(.openCursor)) },
        StaticProvider(id: .openAI) { _ in .failure(.needsAuth(.addOpenAIKey)) },
    ]

    static let providers: [any UsageProvider] = [
        StaticProvider(id: .claude) { now in
            .success(ProviderSnapshot(provider: .claude, fetchedAt: now, planName: "Max 5x", metrics: [
                UsageMetric(id: "claude.session", role: .session, unit: .percent, used: 46,
                            resetsAt: now.addingTimeInterval(2 * 3600 + 13 * 60)),
                UsageMetric(id: "claude.weekly", role: .weekly, unit: .percent, used: 83,
                            resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600)),
                UsageMetric(id: "claude.weekly.fable", role: .weeklyModel("Fable"), unit: .percent, used: 12,
                            resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600)),
            ]))
        },
        StaticProvider(id: .cursor) { now in
            .success(ProviderSnapshot(provider: .cursor, fetchedAt: now, planName: "Pro", metrics: [
                UsageMetric(id: "cursor.included", role: .includedUsage, unit: .currency(code: "USD"), used: 12.4,
                            limit: 20, reportedPercent: 62, resetsAt: now.addingTimeInterval(12 * 86400)),
            ]))
        },
        StaticProvider(id: .openAI) { now in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            let amounts = [0.4, 1.1, 0.8, 2.3, 0, 0, 1.7, 3.2, 2.1, 0.9, 1.4, 4.0, 2.6, 1.9, 0.3,
                           0, 1.2, 2.8, 3.5, 2.2, 1.6, 0.7, 2.9, 3.8, 1.1, 0, 0.6, 2.4, 1.8, 1.23]
            let history = amounts.enumerated().map { offset, amount in
                DailyPoint(day: calendar.date(byAdding: .day, value: offset - 29, to: today)!, amount: amount)
            }
            return .success(ProviderSnapshot(
                provider: .openAI, fetchedAt: now,
                metrics: [
                    UsageMetric(id: "openai.month", role: .spendMonth, unit: .currency(code: "USD"), used: 45.67),
                    UsageMetric(id: "openai.today", role: .spendToday, unit: .currency(code: "USD"), used: 1.23),
                ],
                breakdown: [
                    BreakdownItem(label: "gpt-5", amount: 30.10),
                    BreakdownItem(label: "gpt-4.1-mini", amount: 9.80),
                    BreakdownItem(label: "text-embedding-3-small", amount: 3.27),
                    BreakdownItem(label: nil, amount: 2.50),
                ],
                history: history,
                currencyCode: "USD"
            ))
        },
    ]
}
#endif
