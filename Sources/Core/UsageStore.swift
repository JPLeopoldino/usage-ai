import Foundation
import Observation

public struct ProviderStatus: Equatable, Sendable {
    /// The last good snapshot (from the network or the cache). Kept while errors happen.
    public var snapshot: ProviderSnapshot?
    /// The error of the last attempt, `nil` if it succeeded.
    public var error: ProviderError?
    public var isLoading = false
    public var lastAttempt: Date?
    public var consecutiveFailures = 0
    public var nextEligible: Date = .distantPast

    public init(snapshot: ProviderSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public var isRateLimited: Bool {
        if case .rateLimited = error { return true }
        return false
    }

    /// Not set up on this Mac yet, so the menu leaves it out and only Settings lists it.
    /// A provider that showed data before stays, so an expired login is still noticed.
    public var needsSetup: Bool {
        guard case .needsAuth(let hint)? = error else { return false }
        switch hint {
        case .installClaudeBridge, .addCursorCookie, .addOpenAIKey:
            return true
        case .grantKeychainAccess, .openClaudeCode, .openCursor:
            return snapshot == nil
        case .waitingForClaudeCode, .missingProfileScope, .openAIKeyNotAdmin, .manualCredentialRejected:
            return false
        }
    }
}

@MainActor
@Observable
public final class UsageStore {
    public private(set) var statuses: [ProviderID: ProviderStatus] = [:]
    public var isOffline = false

    @ObservationIgnored private let providers: [ProviderID: any UsageProvider]
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let cache: SnapshotCache?
    @ObservationIgnored private let randomJitter: @Sendable () -> Double

    public init(
        providers: [any UsageProvider],
        settings: AppSettings,
        cache: SnapshotCache? = nil,
        randomJitter: @escaping @Sendable () -> Double = { Double.random(in: 0.8...1.2) }
    ) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.settings = settings
        self.cache = cache
        self.randomJitter = randomJitter
    }

    public func status(_ id: ProviderID) -> ProviderStatus {
        statuses[id] ?? ProviderStatus()
    }

    /// Enabled providers that are set up, in display order: what the menu and menu bar show.
    public var shownProviders: [ProviderID] {
        settings.orderedEnabledProviders.filter { !status($0).needsSetup }
    }

    public func loadCache() async {
        guard let cache else { return }
        for (id, snapshot) in await cache.load() where statuses[id]?.snapshot == nil {
            statuses[id, default: ProviderStatus()].snapshot = snapshot
        }
    }

    /// Refreshes the enabled providers whose next poll is due.
    public func refreshDue(now: Date = .now) async {
        guard !isOffline else { return }
        let due = settings.orderedEnabledProviders.filter { status($0).nextEligible <= now }
        await refresh(due, userInitiated: false)
    }

    /// Refreshes providers not attempted in the last `minimumAge` seconds (used when the menu opens).
    public func refreshIfOlder(than minimumAge: TimeInterval, now: Date = .now) async {
        guard !isOffline else { return }
        let ids = settings.orderedEnabledProviders.filter { id in
            let status = status(id)
            guard !status.isRateLimited || status.nextEligible <= now else { return false }
            guard let lastAttempt = status.lastAttempt else { return true }
            return now.timeIntervalSince(lastAttempt) > minimumAge
        }
        await refresh(ids, userInitiated: false)
    }

    /// Refreshes now, skipping backoff (but not an active rate-limit window). Allows Keychain prompts.
    public func refreshAll(userInitiated: Bool = true, now: Date = .now) async {
        let ids = settings.orderedEnabledProviders.filter { id in
            let status = status(id)
            return !status.isRateLimited || status.nextEligible <= now
        }
        await refresh(ids, userInitiated: userInitiated)
    }

    public func refresh(_ ids: [ProviderID], userInitiated: Bool) async {
        let config = settings.providerConfig
        let now = Date.now
        let targets = ids.filter { settings.enabledProviders.contains($0) && !status($0).isLoading && providers[$0] != nil }
        guard !targets.isEmpty else { return }

        for id in targets {
            statuses[id, default: ProviderStatus()].isLoading = true
        }

        await withTaskGroup(of: (ProviderID, Result<ProviderSnapshot, ProviderError>).self) { group in
            for id in targets {
                guard let provider = providers[id] else { continue }
                let context = FetchContext(userInitiated: userInitiated, now: now, config: config)
                // Child tasks run off the main actor, so blocking file and SQLite reads don't stall the UI.
                group.addTask {
                    do throws(ProviderError) {
                        return (id, .success(try await provider.fetch(context)))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                apply(result, to: id, config: config)
            }
        }

        await cache?.save(statuses.compactMapValues(\.snapshot))
    }

    /// Forgets the error and backoff of a provider, e.g. after its settings changed.
    public func resetBackoff(_ id: ProviderID) {
        guard var status = statuses[id] else { return }
        status.consecutiveFailures = 0
        status.nextEligible = .distantPast
        if !status.isRateLimited { status.error = nil }
        statuses[id] = status
    }

    private func apply(_ result: Result<ProviderSnapshot, ProviderError>, to id: ProviderID, config: ProviderConfig) {
        guard let provider = providers[id] else { return }
        var status = status(id)
        let now = Date.now
        let interval = provider.pollingInterval(userInterval: settings.refreshInterval, config: config)

        status.isLoading = false
        status.lastAttempt = now
        switch result {
        case .success(let snapshot):
            status.snapshot = snapshot
            status.error = nil
            status.consecutiveFailures = 0
            status.nextEligible = now.addingTimeInterval(interval)
            Log.provider(id).info("refresh ok, \(snapshot.metrics.count) metrics")
        case .failure(let error):
            status.error = error
            status.consecutiveFailures += 1
            let delay = BackoffPolicy.delay(
                interval: interval, failures: status.consecutiveFailures, error: error, jitter: randomJitter())
            status.nextEligible = now.addingTimeInterval(delay)
            Log.provider(id).notice("refresh failed: \(String(describing: error), privacy: .public)")
        }
        statuses[id] = status
    }
}
