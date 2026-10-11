import Foundation

public struct ClaudeProvider: UsageProvider {
    public let id = ProviderID.claude

    private let transport: any HTTPTransport
    private let bridge: ClaudeStatusLineBridge
    private let readCredentials: @Sendable (_ allowUI: Bool) -> Result<Data, ForeignKeychainItem.ReadError>

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init(
        transport: any HTTPTransport,
        bridge: ClaudeStatusLineBridge = ClaudeStatusLineBridge(),
        readCredentials: @escaping @Sendable (_ allowUI: Bool) -> Result<Data, ForeignKeychainItem.ReadError> = {
            ForeignKeychainItem.read(service: "Claude Code-credentials", allowUI: $0)
        }
    ) {
        self.transport = transport
        self.bridge = bridge
        self.readCredentials = readCredentials
    }

    public func pollingInterval(userInterval: TimeInterval, config: ProviderConfig) -> TimeInterval {
        switch config.claudeSource {
        case .statusLineBridge: min(userInterval, 30)  // only reads a local file
        case .oauth: max(userInterval, 120)  // the endpoint rate-limits aggressively
        }
    }

    public func fetch(_ context: FetchContext) async throws(ProviderError) -> ProviderSnapshot {
        switch context.config.claudeSource {
        case .statusLineBridge:
            var snapshot = try bridge.snapshot(now: context.now)
            snapshot.planName = context.config.claudePlan.displayName
            return snapshot
        case .oauth:
            return try await fetchOAuth(context)
        }
    }

    private func fetchOAuth(_ context: FetchContext) async throws(ProviderError) -> ProviderSnapshot {
        let oauth = try credentials(allowUI: context.userInitiated)
        guard !oauth.isExpired(at: context.now) else { throw .needsAuth(.openClaudeCode) }

        let request = HTTP.request(Self.usageURL, headers: [
            "Authorization": "Bearer \(oauth.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
        ])
        let (data, response) = try await HTTP.send(request, using: transport)

        switch response.statusCode {
        case 200..<300:
            break
        case 401:
            throw .needsAuth(.openClaudeCode)
        case 403:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw body.contains("user:profile") ? .needsAuth(.missingProfileScope) : .http(status: 403)
        case 429:
            throw .rateLimited(retryAfter: HTTP.retryAfter(response))
        default:
            throw .http(status: response.statusCode)
        }

        let usage = try HTTP.decode(ClaudeUsageResponse.self, from: data)
        return ProviderSnapshot(
            provider: .claude,
            fetchedAt: context.now,
            planName: oauth.planName,
            metrics: try usage.metrics()
        )
    }

    private func credentials(allowUI: Bool) throws(ProviderError) -> ClaudeCredentials.OAuth {
        switch readCredentials(allowUI) {
        case .success(let data):
            guard let parsed = try? JSONDecoder().decode(ClaudeCredentials.self, from: data),
                  let oauth = parsed.claudeAiOauth, !oauth.accessToken.isEmpty
            else { throw .needsAuth(.openClaudeCode) }
            return oauth
        case .failure(.notFound):
            throw .needsAuth(.openClaudeCode)
        case .failure(.interactionNeeded), .failure(.denied):
            throw .needsAuth(.grantKeychainAccess)
        case .failure(.failed(let status)):
            throw .other("Keychain status \(status)")
        }
    }
}
