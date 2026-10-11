import Foundation

/// Polls the store on a timer. The app pauses it while the Mac sleeps.
@MainActor
public final class RefreshScheduler {
    /// How often due providers are checked. Each provider has its own, longer interval.
    public static let tick: Duration = .seconds(15)

    private let store: UsageStore
    private var loop: Task<Void, Never>?

    public init(store: UsageStore) {
        self.store = store
    }

    public var isRunning: Bool { loop != nil }

    public func start(after delay: Duration = .zero) {
        loop?.cancel()
        loop = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            while !Task.isCancelled {
                await self?.store.refreshDue()
                try? await Task.sleep(for: Self.tick, tolerance: .seconds(3))
            }
        }
        Log.scheduler.info("started")
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        Log.scheduler.info("stopped")
    }
}
