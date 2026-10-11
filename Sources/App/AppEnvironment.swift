import AppKit
import Network
import Observation
import ServiceManagement
import UsageCore

/// Composition root: builds the providers, store and scheduler, and wires system events.
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settings: AppSettings
    let store: UsageStore
    let keychain = KeychainStore()
    let bridge = ClaudeStatusLineBridge()
    let launchAtLogin = LaunchAtLogin()

    @ObservationIgnored private let scheduler: RefreshScheduler
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        let transport = URLSessionTransport()
        let settings = AppSettings()
        let store = UsageStore(
            providers: [
                ClaudeProvider(transport: transport),
                CursorProvider(transport: transport),
                OpenAIProvider(transport: transport),
            ],
            settings: settings,
            cache: SnapshotCache()
        )
        self.settings = settings
        self.store = store
        scheduler = RefreshScheduler(store: store)
    }

    func start() {
        if let script = Bundle.main.url(forResource: "claude-statusline", withExtension: "sh") {
            try? bridge.updateScript(from: script)
        }
        Task {
            await store.loadCache()
            scheduler.start()
        }
        observeSleepAndWake()
        observeNetwork()
        observeSettingsWindow()
    }

    func stop() {
        scheduler.stop()
        pathMonitor.cancel()
    }

    /// Re-polls one provider right away, e.g. after its settings changed.
    func refreshNow(_ provider: ProviderID, userInitiated: Bool = true) {
        store.resetBackoff(provider)
        Task { await store.refresh([provider], userInitiated: userInitiated) }
    }

    func menuDidOpen() {
        guard settings.refreshOnOpen else { return }
        Task { await store.refreshIfOlder(than: 60) }
    }

    // MARK: System events

    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppEnvironment.shared.scheduler.stop() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            // Give Wi-Fi a moment to reconnect before polling.
            MainActor.assumeIsolated { AppEnvironment.shared.scheduler.start(after: .seconds(10)) }
        })
    }

    private func observeNetwork() {
        pathMonitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in
                let store = AppEnvironment.shared.store
                let cameBack = store.isOffline && online
                store.isOffline = !online
                if cameBack {
                    await store.refreshAll(userInitiated: false)
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "UsageAI.network"))
    }

    /// The app has no Dock icon; it becomes a regular app only while Settings is open.
    private func observeSettingsWindow() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let window, SettingsOpener.isSettingsWindow(window) else { return }
                _ = NSApp.setActivationPolicy(.accessory)
            }
        })
    }
}

/// Wraps `SMAppService` so the toggle always reflects the system state.
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.store.error("Launch at login change failed")
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
