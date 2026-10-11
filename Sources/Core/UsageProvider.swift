import Foundation

/// Where Usage AI reads Claude usage from.
public enum ClaudeSource: String, Codable, CaseIterable, Sendable {
    /// Claude Code's status line writes its `rate_limits` to a file (default).
    case statusLineBridge
    /// Unofficial OAuth usage endpoint, using the token Claude Code keeps in the Keychain.
    case oauth
}

/// Where a provider gets its credential from.
public enum CredentialSource: String, Codable, CaseIterable, Sendable {
    case automatic
    case manual
}

/// Settings a provider needs for one fetch. Plain values, safe to pass across actors.
/// The Claude plan picked in Settings, since Claude Code's status line doesn't say which it is.
/// The OAuth source reads the plan from Claude Code's login instead.
public enum ClaudePlan: String, CaseIterable, Sendable {
    case unspecified, pro, max5x, max20x, team, enterprise

    /// Product names are not localized. `nil` shows no plan.
    public var displayName: String? {
        switch self {
        case .unspecified: nil
        case .pro: "Pro"
        case .max5x: "Max 5x"
        case .max20x: "Max 20x"
        case .team: "Team"
        case .enterprise: "Enterprise"
        }
    }
}

public struct ProviderConfig: Sendable, Equatable {
    public var claudeSource: ClaudeSource
    public var claudePlan: ClaudePlan
    public var cursorSource: CredentialSource
    public var openAIMonthlyBudget: Double?
    public var openAIProjectID: String?

    public init(
        claudeSource: ClaudeSource = .statusLineBridge,
        claudePlan: ClaudePlan = .unspecified,
        cursorSource: CredentialSource = .automatic,
        openAIMonthlyBudget: Double? = nil,
        openAIProjectID: String? = nil
    ) {
        self.claudeSource = claudeSource
        self.claudePlan = claudePlan
        self.cursorSource = cursorSource
        self.openAIMonthlyBudget = openAIMonthlyBudget
        self.openAIProjectID = openAIProjectID
    }
}

public struct FetchContext: Sendable {
    /// True when the user asked for this refresh; allows system prompts such as Keychain access.
    public var userInitiated: Bool
    public var now: Date
    public var config: ProviderConfig

    public init(userInitiated: Bool = false, now: Date = .now, config: ProviderConfig = .init()) {
        self.userInitiated = userInitiated
        self.now = now
        self.config = config
    }
}

/// What the user has to do before a provider can work. The UI maps each case to text and an action.
public enum AuthHint: String, Codable, Sendable {
    case installClaudeBridge
    case waitingForClaudeCode
    case grantKeychainAccess
    case openClaudeCode
    case missingProfileScope
    case openCursor
    case addCursorCookie
    case addOpenAIKey
    case openAIKeyNotAdmin
    case manualCredentialRejected

    /// The provider found this without a network request, so retrying costs nothing.
    public var isLocalCheck: Bool {
        switch self {
        case .installClaudeBridge, .waitingForClaudeCode, .addCursorCookie, .addOpenAIKey: true
        default: false
        }
    }
}

public enum ProviderError: Error, Equatable, Sendable {
    case needsAuth(AuthHint)
    case rateLimited(retryAfter: TimeInterval?)
    case offline
    case http(status: Int)
    case unexpectedShape(String)
    case other(String)
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    /// Seconds between polls, given the interval the user picked. Remote sources never go below
    /// their own minimum; cheap local sources may poll faster.
    func pollingInterval(userInterval: TimeInterval, config: ProviderConfig) -> TimeInterval
    func fetch(_ context: FetchContext) async throws(ProviderError) -> ProviderSnapshot
}
