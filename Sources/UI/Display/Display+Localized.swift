import AppKit
import Foundation
import UsageCore

// Everything the user reads is built here, so Core stays free of UI strings.

extension MetricRole {
    var title: String {
        switch self {
        case .session: String(localized: "Current session")
        case .weekly: String(localized: "Weekly · All models")
        case .weeklyModel(let model): String(localized: "Weekly · \(model)")
        case .extraUsage: String(localized: "Extra usage")
        case .includedUsage: String(localized: "Included usage")
        case .autoUsage: String(localized: "Auto")
        case .apiUsage: String(localized: "API models")
        case .onDemand: String(localized: "On-demand")
        case .requests(let model): String(localized: "Requests · \(model)")
        case .spendToday: String(localized: "Today (UTC)")
        case .spendMonth: String(localized: "This month")
        }
    }
}

enum Format {
    /// "72%", or "<1%" for tiny non-zero values.
    static func percent(_ value: Double) -> String {
        if value > 0 && value < 1 {
            return "<" + (0.01).formatted(.percent.precision(.fractionLength(0)))
        }
        return (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    static func currency(_ value: Double, code: String, compact: Bool = false) -> String {
        if compact && value >= 100 {
            return value.formatted(.currency(code: code).precision(.fractionLength(0)))
        }
        return value.formatted(.currency(code: code))
    }

    static func count(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }

    /// The short text used in the menu bar.
    static func compact(_ metric: UsageMetric) -> String {
        switch metric.unit {
        case .percent:
            return percent(metric.used)
        case .currency(let code):
            if let fraction = metric.fraction, metric.limit != nil || metric.reportedPercent != nil {
                return percent(fraction * 100)
            }
            return currency(metric.used, code: code, compact: true)
        case .count:
            if let fraction = metric.fraction { return percent(fraction * 100) }
            return count(metric.used)
        }
    }

    /// The value shown on the right of a metric row in the menu.
    static func value(_ metric: UsageMetric) -> String {
        switch metric.unit {
        case .percent:
            return percent(metric.used)
        case .currency(let code):
            let used = currency(metric.used, code: code)
            guard let limit = metric.limit else { return used }
            let amounts = String(localized: "\(used) of \(currency(limit, code: code))")
            if let reported = metric.reportedPercent {
                return "\(percent(reported)) · \(amounts)"
            }
            return amounts
        case .count:
            guard let limit = metric.limit else { return count(metric.used) }
            return String(localized: "\(count(metric.used)) of \(count(limit))")
        }
    }

    /// "Resets in 2h 13m", "Resets Tue 09:00" or "Resets Oct 23".
    static func reset(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 60 {
            return String(localized: "Resets soon")
        }
        if remaining < 24 * 3600 {
            let duration = Duration.seconds(remaining).formatted(
                .units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
            return String(localized: "Resets in \(duration)")
        }
        if remaining < 6 * 24 * 3600 {
            return String(localized: "Resets \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
        }
        return String(localized: "Resets \(date.formatted(.dateTime.month(.abbreviated).day()))")
    }

    /// "Updated 3 min ago" / "Updated just now".
    static func updated(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 {
            return String(localized: "Updated just now")
        }
        let relative = date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return String(localized: "Updated \(relative)")
    }
}

/// A problem shown in the menu, with an optional button.
struct ProblemDescription {
    enum Action {
        case openSettings
        case grantKeychainAccess
        case openCursor
        case retry
    }

    var message: String
    var actionTitle: String?
    var action: Action?
    var isWarning: Bool

    init(_ error: ProviderError, provider: ProviderID) {
        isWarning = true
        switch error {
        case .needsAuth(let hint):
            self = ProblemDescription(hint)
            return
        case .rateLimited:
            message = String(localized: "Rate limited by \(provider.displayName). Trying again later.")
            isWarning = false
        case .offline:
            message = String(localized: "Offline. Showing the last known data.")
            isWarning = false
        case .http(let status):
            message = String(localized: "\(provider.displayName) returned an error (HTTP \(status)).")
            actionTitle = String(localized: "Retry")
            action = .retry
        case .unexpectedShape:
            message = String(localized: "Unexpected response. \(provider.displayName) may have changed its API.")
            actionTitle = String(localized: "Retry")
            action = .retry
        case .other:
            message = String(localized: "Couldn't load usage.")
            actionTitle = String(localized: "Retry")
            action = .retry
        }
    }

    init(_ hint: AuthHint) {
        isWarning = true
        switch hint {
        case .installClaudeBridge:
            message = String(localized: "Connect Claude Code to show your plan limits.")
            actionTitle = String(localized: "Set Up…")
            action = .openSettings
        case .waitingForClaudeCode:
            message = String(localized: "Waiting for Claude Code. Usage appears after your next message there.")
            isWarning = false
        case .grantKeychainAccess:
            message = String(localized: "Usage AI needs permission to read Claude Code's login in the Keychain.")
            actionTitle = String(localized: "Allow Access…")
            action = .grantKeychainAccess
        case .openClaudeCode:
            message = String(localized: "Claude Code's login expired. Run `claude` in Terminal to refresh it.")
        case .missingProfileScope:
            message = String(localized: "This Claude token can't read usage. Log in again with `claude`.")
        case .openCursor:
            message = String(localized: "Sign in to the Cursor app to show usage.")
            actionTitle = String(localized: "Open Cursor")
            action = .openCursor
        case .addCursorCookie:
            message = String(localized: "Paste your Cursor session cookie in Settings.")
            actionTitle = String(localized: "Settings…")
            action = .openSettings
        case .addOpenAIKey:
            message = String(localized: "Add an OpenAI Admin API key to show spend.")
            actionTitle = String(localized: "Add Key…")
            action = .openSettings
        case .openAIKeyNotAdmin:
            message = String(localized: "This OpenAI key can't read costs. Use an Admin API key.")
            actionTitle = String(localized: "Settings…")
            action = .openSettings
        case .manualCredentialRejected:
            message = String(localized: "The saved credential was rejected. Update it in Settings.")
            actionTitle = String(localized: "Settings…")
            action = .openSettings
        }
    }
}

enum ExternalApps {
    static let cursorBundleID = "com.todesktop.230313mzl4w4u92"

    @MainActor
    static func openCursor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cursorBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
