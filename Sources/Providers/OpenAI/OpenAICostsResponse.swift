import Foundation

/// Response of `GET https://api.openai.com/v1/organization/costs` (official, Admin API key).
struct OpenAICostsResponse: Decodable {
    struct Bucket: Decodable {
        var startTime: Double
        var results: [Result]

        enum CodingKeys: String, CodingKey {
            case results
            case startTime = "start_time"
        }
    }

    struct Result: Decodable {
        var amount: Amount?
        var lineItem: String?

        enum CodingKeys: String, CodingKey {
            case amount
            case lineItem = "line_item"
        }
    }

    struct Amount: Decodable {
        var value: Double
        var currency: String?

        enum CodingKeys: String, CodingKey { case value, currency }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            currency = try container.decodeIfPresent(String.self, forKey: .currency)
            if let number = try? container.decode(Double.self, forKey: .value) {
                value = number
            } else if let string = try? container.decode(String.self, forKey: .value), let number = Double(string) {
                value = number
            } else {
                value = 0
            }
        }
    }

    var data: [Bucket]
    var hasMore: Bool?
    var nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

/// Turns daily cost buckets into the numbers the menu shows. All days are UTC, like the API.
struct OpenAICostSummary {
    var today: Double
    var month: Double
    var breakdown: [BreakdownItem]
    var history: [DailyPoint]
    var currency: String

    static let topModels = 5

    init(buckets: [OpenAICostsResponse.Bucket], now: Date, calendar: Calendar = .utc) {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday

        var daily: [Date: Double] = [:]
        var models: [String: Double] = [:]
        var currency: String?

        for bucket in buckets {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: bucket.startTime))
            for result in bucket.results {
                guard let amount = result.amount else { continue }
                currency = currency ?? amount.currency
                daily[day, default: 0] += amount.value
                if day >= startOfMonth {
                    models[Self.modelName(result.lineItem), default: 0] += amount.value
                }
            }
        }

        today = daily[startOfToday] ?? 0
        month = daily.filter { $0.key >= startOfMonth }.values.reduce(0, +)
        self.currency = (currency ?? "usd").uppercased()

        let ranked = models.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        breakdown = ranked.prefix(Self.topModels).map { BreakdownItem(label: $0.key, amount: $0.value) }
        let rest = ranked.dropFirst(Self.topModels).map(\.value).reduce(0, +)
        if rest > 0 {
            breakdown.append(BreakdownItem(label: nil, amount: rest))
        }

        let firstDay = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        history = (0..<30).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            return DailyPoint(day: day, amount: daily[day] ?? 0)
        }
    }

    /// `"gpt-4o-2024-08-06, input"` → `"gpt-4o-2024-08-06"`.
    static func modelName(_ lineItem: String?) -> String {
        guard let lineItem, !lineItem.isEmpty else { return "other" }
        if let comma = lineItem.range(of: ", ", options: .backwards) {
            return String(lineItem[..<comma.lowerBound])
        }
        return lineItem
    }
}

extension Calendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
