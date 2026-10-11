import Foundation

/// Response of `GET https://cursor.com/api/usage-summary` (unofficial dashboard endpoint).
/// Amounts are in cents; percents are 0…100 and can be fractional.
struct CursorUsageSummary: Decodable {
    struct Plan: Decodable {
        var enabled: Bool?
        var used: Double?
        var limit: Double?
        var autoPercentUsed: Double?
        var apiPercentUsed: Double?
        var totalPercentUsed: Double?
    }

    struct OnDemand: Decodable {
        var enabled: Bool?
        var used: Double?
        var limit: Double?
    }

    struct Usage: Decodable {
        var plan: Plan?
        var onDemand: OnDemand?
    }

    var billingCycleEnd: Date?
    var membershipType: String?
    var isUnlimited: Bool?
    var individualUsage: Usage?

    var hasPlan: Bool { individualUsage?.plan.map { $0.enabled != false } ?? false }

    func metrics() -> [UsageMetric] {
        var metrics: [UsageMetric] = []
        let resetsAt = billingCycleEnd
        let unlimited = isUnlimited == true

        if let plan = individualUsage?.plan, plan.enabled != false {
            metrics.append(UsageMetric(
                id: "cursor.included",
                role: .includedUsage,
                unit: .currency(code: "USD"),
                used: (plan.used ?? 0) / 100,
                limit: unlimited ? nil : plan.limit.map { $0 / 100 },
                reportedPercent: unlimited ? nil : plan.totalPercentUsed,
                resetsAt: resetsAt
            ))
            if let auto = plan.autoPercentUsed {
                metrics.append(UsageMetric(id: "cursor.auto", role: .autoUsage, unit: .percent, used: auto, resetsAt: resetsAt))
            }
            if let api = plan.apiPercentUsed {
                metrics.append(UsageMetric(id: "cursor.api", role: .apiUsage, unit: .percent, used: api, resetsAt: resetsAt))
            }
        }

        if let onDemand = individualUsage?.onDemand, onDemand.enabled == true {
            metrics.append(UsageMetric(
                id: "cursor.onDemand",
                role: .onDemand,
                unit: .currency(code: "USD"),
                used: (onDemand.used ?? 0) / 100,
                limit: onDemand.limit.map { $0 / 100 },
                resetsAt: resetsAt
            ))
        }
        return metrics
    }

    var planName: String? {
        guard let type = membershipType?.lowercased(), !type.isEmpty else { return nil }
        return Self.planNames[type] ?? type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static let planNames = [
        "free": "Free", "free_trial": "Trial", "hobby": "Hobby", "pro": "Pro", "pro_plus": "Pro+",
        "ultra": "Ultra", "team": "Teams", "business": "Business", "enterprise": "Enterprise",
    ]
}

/// Response of the legacy `GET https://cursor.com/api/usage?user=<id>` (request-count plans):
/// `{"gpt-4": {"numRequests": 12, "maxRequestUsage": 500}, "startOfMonth": "…"}`.
enum CursorLegacyUsage {
    static func metrics(from data: Data, now: Date) throws(ProviderError) -> [UsageMetric] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .unexpectedShape("invalid JSON")
        }
        let start = (object["startOfMonth"] as? String).flatMap(DateParsing.iso8601)
        let resetsAt = start.flatMap { Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: $0) }

        return object.keys.sorted().compactMap { model -> UsageMetric? in
            guard let entry = object[model] as? [String: Any],
                  let used = (entry["numRequests"] as? NSNumber)?.doubleValue,
                  let limit = (entry["maxRequestUsage"] as? NSNumber)?.doubleValue
            else { return nil }
            return UsageMetric(
                id: "cursor.requests.\(model)",
                role: .requests(model: model),
                unit: .count,
                used: used,
                limit: limit,
                resetsAt: resetsAt
            )
        }
    }
}
