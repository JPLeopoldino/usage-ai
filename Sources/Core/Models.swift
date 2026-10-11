import Foundation

/// The services Usage AI knows how to read.
public enum ProviderID: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable, Identifiable {
    case claude
    case cursor
    case openAI

    public var id: String { rawValue }

    /// Brand names are not localized.
    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .openAI: "OpenAI"
        }
    }
}

/// What a metric measures. The UI maps each role to localized text.
public enum MetricRole: Codable, Hashable, Sendable {
    // Claude
    case session
    case weekly
    case weeklyModel(String)
    case extraUsage
    // Cursor
    case includedUsage
    case autoUsage
    case apiUsage
    case onDemand
    case requests(model: String)
    // OpenAI
    case spendToday
    case spendMonth
}

public enum UsageLevel: Int, Codable, Comparable, Sendable {
    case normal
    case warning
    case critical

    public static let warningThreshold = 0.80
    public static let criticalThreshold = 0.95

    public init(fraction: Double?) {
        guard let fraction else { self = .normal; return }
        if fraction >= Self.criticalThreshold {
            self = .critical
        } else if fraction >= Self.warningThreshold {
            self = .warning
        } else {
            self = .normal
        }
    }

    public static func < (lhs: UsageLevel, rhs: UsageLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct UsageMetric: Codable, Hashable, Sendable, Identifiable {
    public enum Unit: Codable, Hashable, Sendable {
        /// `used` is 0…100 (can exceed 100).
        case percent
        /// `used` and `limit` are in major units (dollars, not cents).
        case currency(code: String)
        case count
    }

    /// Stable identifier, e.g. "claude.session". Used to pin a metric in the menu bar.
    public var id: String
    public var role: MetricRole
    public var unit: Unit
    public var used: Double
    /// `nil` means unbounded. Percent metrics are implicitly bounded by 100.
    public var limit: Double?
    /// Percent reported by the service when it differs from `used / limit`.
    public var reportedPercent: Double?
    public var resetsAt: Date?

    public init(
        id: String,
        role: MetricRole,
        unit: Unit,
        used: Double,
        limit: Double? = nil,
        reportedPercent: Double? = nil,
        resetsAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.unit = unit
        self.used = used
        self.limit = limit
        self.reportedPercent = reportedPercent
        self.resetsAt = resetsAt
    }

    /// 0…1 (or more) for gauges and thresholds; `nil` when unbounded.
    public var fraction: Double? {
        if let reportedPercent { return max(0, reportedPercent / 100) }
        switch unit {
        case .percent:
            return max(0, used / (limit ?? 100))
        case .currency, .count:
            guard let limit, limit > 0 else { return nil }
            return max(0, used / limit)
        }
    }

    public var level: UsageLevel { UsageLevel(fraction: fraction) }
}

public struct BreakdownItem: Codable, Hashable, Sendable, Identifiable {
    /// `nil` label means "everything else".
    public var label: String?
    public var amount: Double

    public var id: String { label ?? "__other__" }

    public init(label: String?, amount: Double) {
        self.label = label
        self.amount = amount
    }
}

public struct DailyPoint: Codable, Hashable, Sendable, Identifiable {
    public var day: Date
    public var amount: Double

    public var id: Date { day }

    public init(day: Date, amount: Double) {
        self.day = day
        self.amount = amount
    }
}

public struct ProviderSnapshot: Codable, Hashable, Sendable {
    public var provider: ProviderID
    public var fetchedAt: Date
    /// When the data itself was captured, if older than `fetchedAt` (e.g. the Claude Code bridge file).
    public var dataAsOf: Date?
    public var planName: String?
    public var metrics: [UsageMetric]
    public var breakdown: [BreakdownItem]
    public var history: [DailyPoint]
    public var currencyCode: String?

    public init(
        provider: ProviderID,
        fetchedAt: Date,
        dataAsOf: Date? = nil,
        planName: String? = nil,
        metrics: [UsageMetric],
        breakdown: [BreakdownItem] = [],
        history: [DailyPoint] = [],
        currencyCode: String? = nil
    ) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.dataAsOf = dataAsOf
        self.planName = planName
        self.metrics = metrics
        self.breakdown = breakdown
        self.history = history
        self.currencyCode = currencyCode
    }

    /// The most constrained metric that has a known fraction.
    public var primaryMetric: UsageMetric? {
        metrics
            .filter { $0.fraction != nil }
            .max { ($0.fraction ?? 0) < ($1.fraction ?? 0) }
    }

    /// When the numbers were last true.
    public var asOf: Date { dataAsOf ?? fetchedAt }
}
