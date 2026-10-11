import Foundation

public struct OpenAIProvider: UsageProvider {
    public let id = ProviderID.openAI

    private let transport: any HTTPTransport
    private let adminKey: @Sendable () -> String?

    static let costsURL = URL(string: "https://api.openai.com/v1/organization/costs")!
    static let maxPages = 10

    public init(
        transport: any HTTPTransport,
        adminKey: @escaping @Sendable () -> String? = { KeychainStore().read(.openAIAdminKey) }
    ) {
        self.transport = transport
        self.adminKey = adminKey
    }

    /// Cost data is aggregated per day and arrives with a delay, so polling more often is pointless.
    public func pollingInterval(userInterval: TimeInterval, config: ProviderConfig) -> TimeInterval {
        max(userInterval, 600)
    }

    public func fetch(_ context: FetchContext) async throws(ProviderError) -> ProviderSnapshot {
        guard let key = adminKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw .needsAuth(.addOpenAIKey)
        }

        let calendar = Calendar.utc
        let startOfToday = calendar.startOfDay(for: context.now)
        let startOfMonth = calendar.dateInterval(of: .month, for: context.now)?.start ?? startOfToday
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        let start = min(startOfMonth, thirtyDaysAgo)

        var buckets: [OpenAICostsResponse.Bucket] = []
        var page: String?
        for _ in 0..<Self.maxPages {
            let response = try await fetchPage(key: key, start: start, page: page, projectID: context.config.openAIProjectID)
            buckets += response.data
            guard response.hasMore == true, let next = response.nextPage, !next.isEmpty else { break }
            page = next
        }

        let summary = OpenAICostSummary(buckets: buckets, now: context.now, calendar: calendar)
        let currency = UsageMetric.Unit.currency(code: summary.currency)
        let budget = context.config.openAIMonthlyBudget.flatMap { $0 > 0 ? $0 : nil }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)

        return ProviderSnapshot(
            provider: .openAI,
            fetchedAt: context.now,
            metrics: [
                UsageMetric(id: "openai.month", role: .spendMonth, unit: currency, used: summary.month, limit: budget,
                            resetsAt: nextMonth),
                UsageMetric(id: "openai.today", role: .spendToday, unit: currency, used: summary.today),
            ],
            breakdown: summary.breakdown,
            history: summary.history,
            currencyCode: summary.currency
        )
    }

    private func fetchPage(
        key: String,
        start: Date,
        page: String?,
        projectID: String?
    ) async throws(ProviderError) -> OpenAICostsResponse {
        var components = URLComponents(url: Self.costsURL, resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "group_by", value: "line_item"),
            URLQueryItem(name: "limit", value: "60"),
        ]
        if let projectID = projectID?.trimmingCharacters(in: .whitespaces), !projectID.isEmpty {
            query.append(URLQueryItem(name: "project_ids", value: projectID))
        }
        if let page {
            query.append(URLQueryItem(name: "page", value: page))
        }
        components.queryItems = query

        let request = HTTP.request(components.url!, headers: ["Authorization": "Bearer \(key)"])
        let (data, response) = try await HTTP.send(request, using: transport)
        switch response.statusCode {
        case 200..<300: return try HTTP.decode(OpenAICostsResponse.self, from: data)
        case 401: throw .needsAuth(.manualCredentialRejected)
        case 403: throw .needsAuth(.openAIKeyNotAdmin)
        case 429: throw .rateLimited(retryAfter: HTTP.retryAfter(response))
        default: throw .http(status: response.statusCode)
        }
    }
}
