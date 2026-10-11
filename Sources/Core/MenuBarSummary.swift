import Foundation

/// What the menu bar item shows, derived from the current statuses. Pure, so it is easy to test.
public struct MenuBarSummary: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        /// Set in "per service" mode, where each segment gets the service's logo.
        public var provider: ProviderID?
        public var metric: UsageMetric

        public var level: UsageLevel { metric.level }
    }

    /// Fills the bar; `nil` when there is no bounded metric.
    public var fraction: Double?
    public var segments: [Segment]
    public var level: UsageLevel

    /// How much of the menu bar's bar is filled, from 0 to 1.
    public var fill: Double { Self.fill(for: fraction) }

    public init(
        statuses: [ProviderID: ProviderStatus],
        enabled: [ProviderID],
        mode: MenuBarDisplayMode,
        pinnedMetricID: String?
    ) {
        let snapshots = enabled.compactMap { statuses[$0]?.snapshot }
        let highest = snapshots.compactMap(\.primaryMetric).max { ($0.fraction ?? 0) < ($1.fraction ?? 0) }

        fraction = highest?.fraction
        level = highest?.level ?? .normal

        switch mode {
        case .iconOnly:
            segments = []
        case .highest:
            segments = highest.map { [Segment(metric: $0)] } ?? []
        case .pinned:
            let pinned = snapshots.lazy.flatMap(\.metrics).first { $0.id == pinnedMetricID }
            if let metric = pinned ?? highest {
                segments = [Segment(metric: metric)]
                fraction = metric.fraction ?? fraction
                level = metric.level
            } else {
                segments = []
            }
        case .perService:
            segments = snapshots.compactMap { snapshot in
                // Spend without a budget has no fraction; show it anyway.
                guard let metric = snapshot.primaryMetric ?? snapshot.metrics.first else { return nil }
                return Segment(provider: snapshot.provider, metric: metric)
            }
        }
    }

    public static func fill(for fraction: Double?) -> Double {
        min(max(fraction ?? 0, 0), 1)
    }
}
