import Foundation

public struct CursorProvider: UsageProvider {
    public let id = ProviderID.cursor

    private let transport: any HTTPTransport
    private let databaseURL: URL
    private let manualCookie: @Sendable () -> String?

    static let summaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    static let cookieName = "WorkosCursorSessionToken"

    public init(
        transport: any HTTPTransport,
        databaseURL: URL = AppPaths.cursorStateDatabase,
        manualCookie: @escaping @Sendable () -> String? = { KeychainStore().read(.cursorManualCookie) }
    ) {
        self.transport = transport
        self.databaseURL = databaseURL
        self.manualCookie = manualCookie
    }

    public func pollingInterval(userInterval: TimeInterval, config: ProviderConfig) -> TimeInterval {
        max(userInterval, 60)
    }

    public func fetch(_ context: FetchContext) async throws(ProviderError) -> ProviderSnapshot {
        let manual = context.config.cursorSource == .manual
        let session = manual ? try manualSession() : try appSession(now: context.now)
        let rejected: ProviderError = .needsAuth(manual ? .manualCredentialRejected : .openCursor)

        let summaryData = try await get(Self.summaryURL, cookie: session.cookie, rejected: rejected)
        let summary = try HTTP.decode(CursorUsageSummary.self, from: summaryData)

        var metrics = summary.metrics()
        if !summary.hasPlan, let userID = session.userID,
           var components = URLComponents(string: "https://cursor.com/api/usage") {
            components.queryItems = [URLQueryItem(name: "user", value: userID)]
            if let url = components.url {
                let legacyData = try await get(url, cookie: session.cookie, rejected: rejected)
                metrics += try CursorLegacyUsage.metrics(from: legacyData, now: context.now)
            }
        }

        return ProviderSnapshot(provider: .cursor, fetchedAt: context.now, planName: summary.planName, metrics: metrics)
    }

    private func get(_ url: URL, cookie: String, rejected: ProviderError) async throws(ProviderError) -> Data {
        let request = HTTP.request(url, headers: ["Cookie": cookie])
        let (data, response) = try await HTTP.send(request, using: transport)
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw rejected
        case 429: throw .rateLimited(retryAfter: HTTP.retryAfter(response))
        default: throw .http(status: response.statusCode)
        }
    }

    // MARK: Session

    struct Session {
        var cookie: String
        var userID: String?
    }

    /// Builds the dashboard cookie from the token the Cursor app stores locally.
    func appSession(now: Date) throws(ProviderError) -> Session {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { throw .needsAuth(.openCursor) }

        let token: String?
        do {
            token = try SQLiteValueReader.value(forKey: "cursorAuth/accessToken", in: databaseURL)
        } catch {
            throw .other("Cursor database unreadable")
        }
        guard let token, !token.isEmpty else { throw .needsAuth(.openCursor) }
        guard let claims = JWT.claims(of: token), let userID = claims.userID, Self.isValidUserID(userID) else {
            throw .unexpectedShape("unrecognized Cursor token")
        }
        guard !claims.isExpired(at: now) else { throw .needsAuth(.openCursor) }

        return Session(cookie: "\(Self.cookieName)=\(userID)%3A%3A\(token)", userID: userID)
    }

    /// Accepts the cookie value as copied from the browser, with or without the `name=` prefix.
    func manualSession() throws(ProviderError) -> Session {
        guard var value = manualCookie()?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw .needsAuth(.addCursorCookie)
        }
        if value.hasPrefix("\(Self.cookieName)=") {
            value.removeFirst(Self.cookieName.count + 1)
        }
        let decoded = value.removingPercentEncoding ?? value
        let userID = decoded.components(separatedBy: "::").first.flatMap { Self.isValidUserID($0) ? $0 : nil }
        return Session(cookie: "\(Self.cookieName)=\(value)", userID: userID)
    }

    static func isValidUserID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }
}
