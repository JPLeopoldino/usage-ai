import Foundation

/// Response of `GET https://api.anthropic.com/api/oauth/usage` (unofficial).
/// Older responses only have the flat window keys; newer ones also have `limits`.
struct ClaudeUsageResponse: Decodable {
    struct Window: Decodable {
        var utilization: Double?
        var resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    struct Limit: Decodable {
        struct Scope: Decodable {
            struct Model: Decodable {
                var displayName: String?

                enum CodingKeys: String, CodingKey { case displayName = "display_name" }
            }

            var model: Model?
        }

        var kind: String?
        var percent: Double?
        var resetsAt: Date?
        var scope: Scope?

        enum CodingKeys: String, CodingKey {
            case kind, percent, scope
            case resetsAt = "resets_at"
        }
    }

    struct ExtraUsage: Decodable {
        var isEnabled: Bool?
        /// Minor units (cents).
        var monthlyLimit: Double?
        /// Minor units (cents).
        var usedCredits: Double?
        var currency: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
        }
    }

    var fiveHour: Window?
    var sevenDay: Window?
    var sevenDayOpus: Window?
    var sevenDaySonnet: Window?
    var extraUsage: ExtraUsage?
    var limits: [Limit]?

    enum CodingKeys: String, CodingKey {
        case limits
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }

    func metrics() throws(ProviderError) -> [UsageMetric] {
        var metrics: [UsageMetric] = []

        func limit(_ kind: String) -> Limit? {
            limits?.first { $0.kind == kind && $0.percent != nil }
        }

        if let session = limit("session") {
            metrics.append(.percent("claude.session", .session, session.percent, session.resetsAt))
        } else if let window = fiveHour, window.utilization != nil {
            metrics.append(.percent("claude.session", .session, window.utilization, window.resetsAt))
        }

        if let weekly = limit("weekly_all") {
            metrics.append(.percent("claude.weekly", .weekly, weekly.percent, weekly.resetsAt))
        } else if let window = sevenDay, window.utilization != nil {
            metrics.append(.percent("claude.weekly", .weekly, window.utilization, window.resetsAt))
        }

        guard !metrics.isEmpty else { throw .unexpectedShape("no session or weekly window") }
        // No session window means none has started yet, which is 0% used.
        if !metrics.contains(where: { $0.role == .session }) {
            metrics.insert(.percent("claude.session", .session, 0, nil), at: 0)
        }

        var models: [String: UsageMetric] = [:]
        for scoped in limits ?? [] where scoped.kind == "weekly_scoped" {
            guard let name = scoped.scope?.model?.displayName, !name.isEmpty, scoped.percent != nil else { continue }
            models[name] = .percent("claude.weekly.\(name.lowercased())", .weeklyModel(name), scoped.percent, scoped.resetsAt)
        }
        for (name, window) in [("Opus", sevenDayOpus), ("Sonnet", sevenDaySonnet)] {
            guard models[name] == nil, let window, window.utilization != nil else { continue }
            models[name] = .percent("claude.weekly.\(name.lowercased())", .weeklyModel(name), window.utilization, window.resetsAt)
        }
        metrics += models.keys.sorted().compactMap { models[$0] }

        if let extra = extraUsage, extra.isEnabled == true, let used = extra.usedCredits {
            metrics.append(UsageMetric(
                id: "claude.extra",
                role: .extraUsage,
                unit: .currency(code: extra.currency ?? "USD"),
                used: used / 100,
                limit: extra.monthlyLimit.map { $0 / 100 }
            ))
        }
        return metrics
    }
}

/// The Keychain item Claude Code writes after `claude` login.
struct ClaudeCredentials: Decodable {
    struct OAuth: Decodable {
        var accessToken: String
        /// Milliseconds since the epoch.
        var expiresAt: Double?
        var subscriptionType: String?
        var rateLimitTier: String?
    }

    var claudeAiOauth: OAuth?
}

extension ClaudeCredentials.OAuth {
    func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return DateParsing.epoch(expiresAt) <= now
    }

    /// "Max 20x", "Max 5x", "Pro"…
    var planName: String? {
        if let tier = rateLimitTier?.lowercased(), let range = tier.range(of: #"max_(\d+)x"#, options: .regularExpression) {
            let multiplier = tier[range].dropFirst(4)
            return "Max \(multiplier)"
        }
        guard let type = subscriptionType, !type.isEmpty else { return nil }
        return type.prefix(1).uppercased() + type.dropFirst()
    }
}

extension UsageMetric {
    static func percent(_ id: String, _ role: MetricRole, _ value: Double?, _ resetsAt: Date?) -> UsageMetric {
        UsageMetric(id: id, role: role, unit: .percent, used: value ?? 0, resetsAt: resetsAt)
    }
}
