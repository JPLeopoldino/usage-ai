import Foundation
import Observation

public enum MenuBarDisplayMode: String, CaseIterable, Codable, Sendable {
    case iconOnly
    case highest
    case pinned
    case perService
}

/// User preferences, persisted in `UserDefaults`. Secrets live in the Keychain, never here.
@MainActor
@Observable
public final class AppSettings {
    public static let refreshIntervals: [TimeInterval] = [60, 120, 300, 600, 900]

    @ObservationIgnored private let defaults: UserDefaults

    public var refreshInterval: TimeInterval { didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) } }
    public var refreshOnOpen: Bool { didSet { defaults.set(refreshOnOpen, forKey: Key.refreshOnOpen) } }
    public var displayMode: MenuBarDisplayMode { didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) } }
    public var pinnedMetricID: String? { didSet { defaults.set(pinnedMetricID, forKey: Key.pinnedMetricID) } }
    public var colorizeMenuBar: Bool { didSet { defaults.set(colorizeMenuBar, forKey: Key.colorizeMenuBar) } }
    public var enabledProviders: Set<ProviderID> {
        didSet { defaults.set(enabledProviders.map(\.rawValue).sorted(), forKey: Key.enabledProviders) }
    }
    public var claudeSource: ClaudeSource { didSet { defaults.set(claudeSource.rawValue, forKey: Key.claudeSource) } }
    public var claudePlan: ClaudePlan { didSet { defaults.set(claudePlan.rawValue, forKey: Key.claudePlan) } }
    public var cursorSource: CredentialSource { didSet { defaults.set(cursorSource.rawValue, forKey: Key.cursorSource) } }
    /// 0 means no budget.
    public var openAIMonthlyBudget: Double { didSet { defaults.set(openAIMonthlyBudget, forKey: Key.openAIMonthlyBudget) } }
    public var openAIProjectID: String { didSet { defaults.set(openAIProjectID, forKey: Key.openAIProjectID) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let interval = defaults.double(forKey: Key.refreshInterval)
        refreshInterval = Self.refreshIntervals.contains(interval) ? interval : 300
        refreshOnOpen = defaults.object(forKey: Key.refreshOnOpen) as? Bool ?? true
        displayMode = defaults.string(forKey: Key.displayMode).flatMap(MenuBarDisplayMode.init) ?? .highest
        pinnedMetricID = defaults.string(forKey: Key.pinnedMetricID)
        colorizeMenuBar = defaults.object(forKey: Key.colorizeMenuBar) as? Bool ?? true
        if let stored = defaults.stringArray(forKey: Key.enabledProviders) {
            enabledProviders = Set(stored.compactMap(ProviderID.init))
        } else {
            enabledProviders = Set(ProviderID.allCases)
        }
        claudeSource = defaults.string(forKey: Key.claudeSource).flatMap(ClaudeSource.init) ?? .statusLineBridge
        claudePlan = defaults.string(forKey: Key.claudePlan).flatMap(ClaudePlan.init) ?? .unspecified
        cursorSource = defaults.string(forKey: Key.cursorSource).flatMap(CredentialSource.init) ?? .automatic
        openAIMonthlyBudget = max(0, defaults.double(forKey: Key.openAIMonthlyBudget))
        openAIProjectID = defaults.string(forKey: Key.openAIProjectID) ?? ""
    }

    public var providerConfig: ProviderConfig {
        ProviderConfig(
            claudeSource: claudeSource,
            claudePlan: claudePlan,
            cursorSource: cursorSource,
            openAIMonthlyBudget: openAIMonthlyBudget > 0 ? openAIMonthlyBudget : nil,
            openAIProjectID: openAIProjectID.isEmpty ? nil : openAIProjectID
        )
    }

    /// Enabled providers in display order.
    public var orderedEnabledProviders: [ProviderID] {
        ProviderID.allCases.filter(enabledProviders.contains)
    }

    public func setEnabled(_ enabled: Bool, _ provider: ProviderID) {
        if enabled { enabledProviders.insert(provider) } else { enabledProviders.remove(provider) }
    }

    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let refreshOnOpen = "refreshOnOpen"
        static let displayMode = "menuBarDisplayMode"
        static let pinnedMetricID = "pinnedMetricID"
        static let colorizeMenuBar = "colorizeMenuBar"
        static let enabledProviders = "enabledProviders"
        static let claudeSource = "claudeSource"
        static let claudePlan = "claudePlan"
        static let cursorSource = "cursorSource"
        static let openAIMonthlyBudget = "openAIMonthlyBudget"
        static let openAIProjectID = "openAIProjectID"
    }
}
