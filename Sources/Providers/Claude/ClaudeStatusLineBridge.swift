import Foundation

/// Gets Claude usage from Claude Code's own status line data, without reusing its token.
///
/// Claude Code runs the status line command after each response and passes JSON on stdin that
/// includes `rate_limits.five_hour` and `rate_limits.seven_day` for Pro and Max subscribers.
/// The bundled `claude-statusline.sh` saves that part to `claude-rate-limits.json`, then prints
/// the output of the user's previous status line command (if any), so nothing visible changes.
public struct ClaudeStatusLineBridge: Sendable {
    public enum State: Equatable, Sendable {
        case notInstalled
        /// Another status line is configured; installing keeps it and chains to it.
        case otherStatusLine(command: String)
        case installed
    }

    public enum BridgeError: Error, Equatable, Sendable {
        case unreadableSettings
        case writeFailed
    }

    public static let scriptName = "claude-statusline.sh"

    public var supportDirectory: URL
    public var claudeSettingsURL: URL

    public init(supportDirectory: URL = AppPaths.supportDirectory, claudeSettingsURL: URL = AppPaths.claudeSettings) {
        self.supportDirectory = supportDirectory
        self.claudeSettingsURL = claudeSettingsURL
    }

    public var scriptURL: URL { supportDirectory.appending(path: Self.scriptName) }
    public var dataURL: URL { supportDirectory.appending(path: "claude-rate-limits.json") }
    /// Holds the user's previous status line command, which the script runs after saving the data.
    public var nextCommandURL: URL { supportDirectory.appending(path: "statusline-next-command") }
    public var backupURL: URL { claudeSettingsURL.appendingPathExtension("usage-ai-backup") }

    /// The `command` value written to Claude Code's settings.
    public var command: String { "\"\(scriptURL.path)\"" }

    // MARK: State

    public func state() -> State {
        guard let settings = try? readSettings(),
              let statusLine = settings["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String, !command.isEmpty
        else { return .notInstalled }
        return command.contains(Self.scriptName) ? .installed : .otherStatusLine(command: command)
    }

    /// The JSON snippet users can paste themselves instead of letting the app edit the file.
    public var settingsSnippet: String {
        """
        "statusLine": {
          "type": "command",
          "command": "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        }
        """
    }

    // MARK: Install / uninstall

    /// Copies the script, backs up `settings.json`, and points `statusLine` at the script.
    public func install(script source: URL) throws(BridgeError) {
        var settings: [String: Any]
        do { settings = try readSettings() } catch { throw .unreadableSettings }

        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: scriptURL.path) {
                try FileManager.default.removeItem(at: scriptURL)
            }
            try FileManager.default.copyItem(at: source, to: scriptURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
            if let previous = statusLine["command"] as? String, !previous.isEmpty, !previous.contains(Self.scriptName) {
                try Data(previous.utf8).write(to: nextCommandURL, options: .atomic)
            } else if statusLine["command"] == nil, FileManager.default.fileExists(atPath: nextCommandURL.path) {
                try FileManager.default.removeItem(at: nextCommandURL)
            }
            statusLine["type"] = "command"
            statusLine["command"] = command
            settings["statusLine"] = statusLine

            try backUpSettings()
            try writeSettings(settings)
        } catch {
            throw .writeFailed
        }
    }

    /// Replaces the installed script when the app's copy changed, so script fixes reach existing
    /// installs without reconnecting. Does nothing when the bridge isn't installed.
    public func updateScript(from source: URL) throws(BridgeError) {
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { return }
        do {
            let bundled = try Data(contentsOf: source)
            guard try Data(contentsOf: scriptURL) != bundled else { return }
            // Swap in a ready, executable file, so Claude Code never runs a half-written script.
            let temporary = supportDirectory.appending(path: ".\(Self.scriptName).\(UUID().uuidString)")
            try bundled.write(to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
            _ = try FileManager.default.replaceItemAt(scriptURL, withItemAt: temporary)
        } catch {
            throw .writeFailed
        }
    }

    /// Restores the previous status line (or removes ours) and deletes the bridge files.
    public func uninstall() throws(BridgeError) {
        var settings: [String: Any]
        do { settings = try readSettings() } catch { throw .unreadableSettings }

        do {
            if var statusLine = settings["statusLine"] as? [String: Any],
               (statusLine["command"] as? String)?.contains(Self.scriptName) == true {
                if let data = try? Data(contentsOf: nextCommandURL), let previous = String(data: data, encoding: .utf8),
                   !previous.isEmpty {
                    statusLine["command"] = previous
                    settings["statusLine"] = statusLine
                } else {
                    settings.removeValue(forKey: "statusLine")
                }
                try backUpSettings()
                try writeSettings(settings)
            }
            for url in [scriptURL, nextCommandURL, dataURL] where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            throw .writeFailed
        }
    }

    // MARK: Data

    struct BridgeFile: Decodable {
        struct Window: Decodable {
            var usedPercentage: Double?
            var resetsAt: Date?

            enum CodingKeys: String, CodingKey {
                case usedPercentage = "used_percentage"
                case resetsAt = "resets_at"
            }
        }

        struct RateLimits: Decodable {
            var fiveHour: Window?
            var sevenDay: Window?

            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"
                case sevenDay = "seven_day"
            }
        }

        var capturedAt: Date?
        var rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case capturedAt = "captured_at"
            case rateLimits = "rate_limits"
        }
    }

    /// Reads the file the script writes. A window whose reset time has passed is reported as 0%.
    public func snapshot(now: Date) throws(ProviderError) -> ProviderSnapshot {
        guard let data = try? Data(contentsOf: dataURL) else {
            throw .needsAuth(state() == .installed ? .waitingForClaudeCode : .installClaudeBridge)
        }
        let file = try HTTP.decode(BridgeFile.self, from: data)
        let capturedAt = file.capturedAt
            ?? (try? dataURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        var metrics: [UsageMetric] = []
        for (id, role, window) in [
            ("claude.session", MetricRole.session, file.rateLimits?.fiveHour),
            ("claude.weekly", MetricRole.weekly, file.rateLimits?.sevenDay),
        ] {
            guard let window, let used = window.usedPercentage else { continue }
            if let resetsAt = window.resetsAt, resetsAt <= now {
                metrics.append(UsageMetric(id: id, role: role, unit: .percent, used: 0))
            } else {
                metrics.append(UsageMetric(id: id, role: role, unit: .percent, used: used, resetsAt: window.resetsAt))
            }
        }
        guard !metrics.isEmpty else { throw .unexpectedShape("bridge file has no rate limits") }
        // Claude Code drops the 5-hour window once it resets, until the next message starts one.
        if !metrics.contains(where: { $0.role == .session }) {
            metrics.insert(UsageMetric(id: "claude.session", role: .session, unit: .percent, used: 0), at: 0)
        }

        return ProviderSnapshot(provider: .claude, fetchedAt: now, dataAsOf: capturedAt, metrics: metrics)
    }

    // MARK: Settings file

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: claudeSettingsURL.path) else { return [:] }
        let data = try Data(contentsOf: claudeSettingsURL)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError.unreadableSettings
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: claudeSettingsURL, options: .atomic)
    }

    private func backUpSettings() throws {
        guard FileManager.default.fileExists(atPath: claudeSettingsURL.path) else { return }
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.copyItem(at: claudeSettingsURL, to: backupURL)
    }
}
