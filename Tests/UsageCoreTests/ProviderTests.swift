import Foundation
import Testing
@testable import UsageCore

struct ClaudeOAuthTests {
    @Test func parsesLimitsArray() throws {
        let usage = try JSONDecoder.usage.decode(ClaudeUsageResponse.self, from: Fixture.data("claude_usage_limits"))
        let metrics = try usage.metrics()
        #expect(metrics.map(\.id) == ["claude.session", "claude.weekly", "claude.weekly.fable"])
        #expect(metrics.map(\.used) == [3, 1, 0])
        #expect(metrics[2].role == .weeklyModel("Fable"))
        #expect(metrics[0].resetsAt == Date(utc: "2026-10-11T02:00:00.419134+00:00"))
    }

    @Test func parsesFlatKeysAndExtraUsage() throws {
        let usage = try JSONDecoder.usage.decode(ClaudeUsageResponse.self, from: Fixture.data("claude_usage_flat"))
        let metrics = try usage.metrics()
        #expect(metrics.map(\.id) == ["claude.session", "claude.weekly", "claude.weekly.opus", "claude.extra"])
        #expect(metrics[1].used == 72.5)
        let extra = metrics[3]
        #expect(extra.unit == .currency(code: "USD"))
        #expect(extra.used == 20.5)
        #expect(extra.limit == 50)
    }

    @Test func missingSessionShowsAsNotStarted() throws {
        let body = #"{"seven_day":{"utilization":12,"resets_at":"2026-10-16T00:00:00+00:00"}}"#
        let usage = try JSONDecoder.usage.decode(ClaudeUsageResponse.self, from: Data(body.utf8))
        let metrics = try usage.metrics()
        #expect(metrics.map(\.id) == ["claude.session", "claude.weekly"])
        #expect(metrics[0].used == 0)
        #expect(metrics[0].resetsAt == nil)
    }

    @Test func noWindowsIsAnUnexpectedShape() throws {
        let usage = try JSONDecoder.usage.decode(ClaudeUsageResponse.self, from: Fixture.data("claude_usage_all_null"))
        #expect(throws: ProviderError.unexpectedShape("no session or weekly window")) { try usage.metrics() }
    }

    @Test func planNameFromCredentials() throws {
        let credentials = try JSONDecoder().decode(ClaudeCredentials.self, from: Fixture.data("claude_credentials"))
        let oauth = try #require(credentials.claudeAiOauth)
        #expect(oauth.planName == "Max 20x")
        #expect(oauth.isExpired(at: Date(utc: "2026-10-10T00:00:00Z")) == false)
        #expect(ClaudeCredentials.OAuth(accessToken: "t", subscriptionType: "pro").planName == "Pro")
    }

    @Test func sendsTokenAndBetaHeader() async throws {
        let body = try Fixture.data("claude_usage_limits")
        let transport = StubTransport(status: 200, body: body)
        let credentials = try Fixture.data("claude_credentials")
        let provider = ClaudeProvider(transport: transport, readCredentials: { _ in .success(credentials) })

        let snapshot = try await provider.fetch(FetchContext(config: ProviderConfig(claudeSource: .oauth)))
        #expect(snapshot.planName == "Max 20x")

        let request = try #require(transport.requests.first)
        #expect(request.url == ClaudeProvider.usageURL)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat01-test-token")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("UsageAI/") == true)
    }

    @Test(arguments: [
        (401, "", ProviderError.needsAuth(.openClaudeCode)),
        (403, #"{"error":"requires user:profile scope"}"#, .needsAuth(.missingProfileScope)),
        (403, "{}", .http(status: 403)),
        (429, "{}", .rateLimited(retryAfter: 120)),
        (500, "{}", .http(status: 500)),
    ])
    func mapsHTTPErrors(status: Int, body: String, expected: ProviderError) async throws {
        let transport = StubTransport(status: status, body: Data(body.utf8), headers: ["Retry-After": "120"])
        let credentials = try Fixture.data("claude_credentials")
        let provider = ClaudeProvider(transport: transport, readCredentials: { _ in .success(credentials) })
        await #expect(throws: expected) {
            try await provider.fetch(FetchContext(config: ProviderConfig(claudeSource: .oauth)))
        }
    }

    @Test func keychainProblemsNeedAuth() async {
        let transport = StubTransport(status: 200)
        let denied = ClaudeProvider(transport: transport, readCredentials: { _ in .failure(.interactionNeeded) })
        await #expect(throws: ProviderError.needsAuth(.grantKeychainAccess)) {
            try await denied.fetch(FetchContext(config: ProviderConfig(claudeSource: .oauth)))
        }
        let missing = ClaudeProvider(transport: transport, readCredentials: { _ in .failure(.notFound) })
        await #expect(throws: ProviderError.needsAuth(.openClaudeCode)) {
            try await missing.fetch(FetchContext(config: ProviderConfig(claudeSource: .oauth)))
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func onlyAllowsKeychainUIWhenUserInitiated() async throws {
        let credentials = try Fixture.data("claude_credentials")
        let body = try Fixture.data("claude_usage_limits")
        let seen = UIFlags()
        let provider = ClaudeProvider(transport: StubTransport(status: 200, body: body), readCredentials: { allowUI in
            seen.append(allowUI)
            return .success(credentials)
        })
        _ = try await provider.fetch(FetchContext(userInitiated: false, config: ProviderConfig(claudeSource: .oauth)))
        _ = try await provider.fetch(FetchContext(userInitiated: true, config: ProviderConfig(claudeSource: .oauth)))
        #expect(seen.values == [false, true])
    }

    final class UIFlags: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Bool] = []
        var values: [Bool] { lock.withLock { _values } }
        func append(_ value: Bool) { lock.withLock { _values.append(value) } }
    }
}

struct ClaudeBridgeTests {
    private func bridge(in directory: TemporaryDirectory) -> ClaudeStatusLineBridge {
        ClaudeStatusLineBridge(
            supportDirectory: directory.url.appending(path: "Support"),
            claudeSettingsURL: directory.url.appending(path: "claude/settings.json"))
    }

    private func script(in directory: TemporaryDirectory) throws -> URL {
        let url = directory.url.appending(path: "claude-statusline.sh")
        try Data("#!/bin/bash\n".utf8).write(to: url)
        return url
    }

    private func settings(_ bridge: ClaudeStatusLineBridge) throws -> [String: Any] {
        let data = try Data(contentsOf: bridge.claudeSettingsURL)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func readsTheBridgeFileAndResetsPastWindows() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let bridge = bridge(in: directory)
        try FileManager.default.createDirectory(at: bridge.supportDirectory, withIntermediateDirectories: true)
        try Fixture.data("claude_bridge").write(to: bridge.dataURL)

        let now = Date(timeIntervalSince1970: 1_791_680_000)
        let snapshot = try bridge.snapshot(now: now)
        #expect(snapshot.dataAsOf == Date(timeIntervalSince1970: 1_791_676_724))
        #expect(snapshot.metrics.map(\.id) == ["claude.session", "claude.weekly"])
        #expect(snapshot.metrics[0].used == 23.5)
        #expect(snapshot.metrics[0].resetsAt == Date(timeIntervalSince1970: 1_791_690_000))
        // The 7-day window already reset, so its old percentage no longer applies.
        #expect(snapshot.metrics[1].used == 0)
        #expect(snapshot.metrics[1].resetsAt == nil)
    }

    @Test func bridgeShowsThePlanPickedInSettings() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let bridge = bridge(in: directory)
        try FileManager.default.createDirectory(at: bridge.supportDirectory, withIntermediateDirectories: true)
        try Fixture.data("claude_bridge").write(to: bridge.dataURL)
        let provider = ClaudeProvider(transport: StubTransport(status: 200), bridge: bridge)

        let none = try await provider.fetch(FetchContext(config: ProviderConfig()))
        #expect(none.planName == nil)
        let max = try await provider.fetch(FetchContext(config: ProviderConfig(claudePlan: .max5x)))
        #expect(max.planName == "Max 5x")
    }

    @Test func bridgeWithoutSessionWindowShowsItAsNotStarted() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let bridge = bridge(in: directory)
        try FileManager.default.createDirectory(at: bridge.supportDirectory, withIntermediateDirectories: true)
        let file = #"{"captured_at":1791680000,"rate_limits":{"seven_day":{"used_percentage":2,"resets_at":1792108800}}}"#
        try Data(file.utf8).write(to: bridge.dataURL)

        let snapshot = try bridge.snapshot(now: Date(timeIntervalSince1970: 1_791_680_100))
        #expect(snapshot.metrics.map(\.id) == ["claude.session", "claude.weekly"])
        #expect(snapshot.metrics[0].used == 0)
        #expect(snapshot.metrics[0].resetsAt == nil)
        #expect(snapshot.metrics[1].used == 2)
    }

    @Test func missingFileAsksToInstallOrWait() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let bridge = bridge(in: directory)
        #expect(throws: ProviderError.needsAuth(.installClaudeBridge)) { try bridge.snapshot(now: .now) }

        try bridge.install(script: try script(in: directory))
        #expect(throws: ProviderError.needsAuth(.waitingForClaudeCode)) { try bridge.snapshot(now: .now) }
    }

    @Test func installWithoutExistingSettings() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let bridge = bridge(in: directory)
        #expect(bridge.state() == .notInstalled)

        try bridge.install(script: try script(in: directory))

        #expect(bridge.state() == .installed)
        let statusLine = try #require(try settings(bridge)["statusLine"] as? [String: Any])
        #expect(statusLine["type"] as? String == "command")
        #expect(statusLine["command"] as? String == "\"\(bridge.scriptURL.path)\"")
        let permissions = try FileManager.default.attributesOfItem(atPath: bridge.scriptURL.path)[.posixPermissions]
        #expect(permissions as? Int == 0o755)
        #expect(!FileManager.default.fileExists(atPath: bridge.nextCommandURL.path))
    }

    @Test func installKeepsTheExistingStatusLineAndOtherSettings() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let bridge = bridge(in: directory)
        try FileManager.default.createDirectory(
            at: bridge.claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"{"model":"opus","statusLine":{"type":"command","command":"~/.claude/statusline.sh","padding":2}}"#
        try Data(original.utf8).write(to: bridge.claudeSettingsURL)
        #expect(bridge.state() == .otherStatusLine(command: "~/.claude/statusline.sh"))

        try bridge.install(script: try script(in: directory))

        let updated = try settings(bridge)
        #expect(updated["model"] as? String == "opus")
        let statusLine = try #require(updated["statusLine"] as? [String: Any])
        #expect(statusLine["padding"] as? Int == 2)
        #expect(try String(contentsOf: bridge.nextCommandURL, encoding: .utf8) == "~/.claude/statusline.sh")
        #expect(try String(contentsOf: bridge.backupURL, encoding: .utf8) == original)

        // Installing twice must not chain the bridge to itself.
        try bridge.install(script: try script(in: directory))
        #expect(try String(contentsOf: bridge.nextCommandURL, encoding: .utf8) == "~/.claude/statusline.sh")

        try bridge.uninstall()
        let restored = try #require(try settings(bridge)["statusLine"] as? [String: Any])
        #expect(restored["command"] as? String == "~/.claude/statusline.sh")
        #expect(restored["padding"] as? Int == 2)
        #expect(!FileManager.default.fileExists(atPath: bridge.scriptURL.path))
    }

    @Test func updatesAnInstalledScriptThatChanged() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let bridge = bridge(in: directory)
        let newer = directory.url.appending(path: "newer.sh")
        try Data("#!/bin/bash\nexit 0\n".utf8).write(to: newer)

        // Not installed: nothing to update, and nothing gets installed.
        try bridge.updateScript(from: newer)
        #expect(!FileManager.default.fileExists(atPath: bridge.scriptURL.path))

        try bridge.install(script: try script(in: directory))
        try bridge.updateScript(from: newer)
        #expect(try Data(contentsOf: bridge.scriptURL) == Data(contentsOf: newer))
        let permissions = try FileManager.default.attributesOfItem(atPath: bridge.scriptURL.path)[.posixPermissions]
        #expect(permissions as? Int == 0o755)
        #expect(try FileManager.default.contentsOfDirectory(atPath: bridge.supportDirectory.path) == [ClaudeStatusLineBridge.scriptName])
    }

    @Test func uninstallRemovesOurStatusLine() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let bridge = bridge(in: directory)
        try bridge.install(script: try script(in: directory))
        try bridge.uninstall()
        #expect(try settings(bridge)["statusLine"] == nil)
        #expect(bridge.state() == .notInstalled)
    }

    @Test func invalidSettingsAreLeftAlone() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let bridge = bridge(in: directory)
        try FileManager.default.createDirectory(
            at: bridge.claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: bridge.claudeSettingsURL)

        #expect(throws: ClaudeStatusLineBridge.BridgeError.unreadableSettings) {
            try bridge.install(script: try script(in: directory))
        }
        #expect(try String(contentsOf: bridge.claudeSettingsURL, encoding: .utf8) == "{ not json")
    }
}

struct CursorTests {
    private let now = Date(utc: "2026-10-10T12:00:00Z")

    @Test func mapsUsageSummary() throws {
        let summary = try JSONDecoder.usage.decode(CursorUsageSummary.self, from: Fixture.data("cursor_summary_used"))
        let metrics = summary.metrics()
        #expect(summary.planName == "Pro+")
        #expect(metrics.map(\.id) == ["cursor.included", "cursor.auto", "cursor.api", "cursor.onDemand"])

        let included = metrics[0]
        #expect(included.used == 12.4)
        #expect(included.limit == 20)
        #expect(included.fraction == 0.62)
        #expect(included.resetsAt == Date(utc: "2026-10-23T13:16:38Z"))
        #expect(metrics[1].used == 0.36)
        #expect(metrics[3].used == 3.1)
        #expect(metrics[3].limit == 50)
    }

    @Test func zeroUsageFromTheRealResponse() throws {
        let summary = try JSONDecoder.usage.decode(CursorUsageSummary.self, from: Fixture.data("cursor_summary_pro"))
        #expect(summary.planName == "Pro")
        #expect(summary.metrics().first?.fraction == 0)
        #expect(summary.metrics().contains { $0.role == .onDemand } == false)
    }

    @Test func unlimitedHasNoGauge() throws {
        let summary = try JSONDecoder.usage.decode(CursorUsageSummary.self, from: Fixture.data("cursor_summary_unlimited"))
        let included = try #require(summary.metrics().first)
        #expect(included.limit == nil)
        #expect(included.fraction == nil)
        #expect(summary.planName == "Ultra")
    }

    @Test func legacyRequestCounts() throws {
        let data = Data(#"{"gpt-4":{"numRequests":120,"maxRequestUsage":500},"gpt-3.5-turbo":{"numRequests":3,"maxRequestUsage":null},"startOfMonth":"2026-09-23T13:16:38.000Z"}"#.utf8)
        let metrics = try CursorLegacyUsage.metrics(from: data, now: now)
        #expect(metrics.map(\.id) == ["cursor.requests.gpt-4"])
        #expect(metrics[0].fraction == 0.24)
        #expect(metrics[0].resetsAt == Date(utc: "2026-10-23T13:16:38Z"))
        #expect(try CursorLegacyUsage.metrics(from: Fixture.data("cursor_usage_legacy"), now: now).isEmpty)
    }

    private func database(token: String, in directory: TemporaryDirectory) throws -> URL {
        let url = directory.url.appending(path: "state.vscdb")
        let script = "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);"
            + "INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', '\(token)');"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, script]
        try process.run()
        process.waitUntilExit()
        return url
    }

    @Test func buildsTheCookieFromTheAppDatabase() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let token = makeJWT(["sub": "auth0|user_01ABC", "exp": now.timeIntervalSince1970 + 3600])
        let transport = StubTransport(status: 200, body: try Fixture.data("cursor_summary_used"))
        let provider = CursorProvider(transport: transport, databaseURL: try database(token: token, in: directory))

        let snapshot = try await provider.fetch(FetchContext(now: now))
        #expect(snapshot.planName == "Pro+")

        let request = try #require(transport.requests.first)
        #expect(request.url == CursorProvider.summaryURL)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "WorkosCursorSessionToken=user_01ABC%3A%3A\(token)")
    }

    @Test func expiredTokenNeedsAuthWithoutANetworkCall() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let token = makeJWT(["sub": "auth0|user_01ABC", "exp": now.timeIntervalSince1970 - 10])
        let transport = StubTransport(status: 200)
        let provider = CursorProvider(transport: transport, databaseURL: try database(token: token, in: directory))

        await #expect(throws: ProviderError.needsAuth(.openCursor)) { try await provider.fetch(FetchContext(now: now)) }
        #expect(transport.requests.isEmpty)
    }

    @Test func missingDatabaseNeedsCursor() async {
        let provider = CursorProvider(transport: StubTransport(status: 200), databaseURL: URL(fileURLWithPath: "/nope.vscdb"))
        await #expect(throws: ProviderError.needsAuth(.openCursor)) { try await provider.fetch(FetchContext(now: now)) }
    }

    @Test func rejectedSessionNeedsAuth() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let token = makeJWT(["sub": "user_1", "exp": now.timeIntervalSince1970 + 3600])
        let provider = CursorProvider(
            transport: StubTransport(status: 401), databaseURL: try database(token: token, in: directory))
        await #expect(throws: ProviderError.needsAuth(.openCursor)) { try await provider.fetch(FetchContext(now: now)) }
    }

    @Test func manualCookieAcceptsNameAndValue() async throws {
        let transport = StubTransport(status: 200, body: try Fixture.data("cursor_summary_pro"))
        let provider = CursorProvider(
            transport: transport, databaseURL: URL(fileURLWithPath: "/nope"),
            manualCookie: { " WorkosCursorSessionToken=user_9%3A%3Aabc.def.ghi \n" })
        _ = try await provider.fetch(FetchContext(now: now, config: ProviderConfig(cursorSource: .manual)))
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Cookie")
            == "WorkosCursorSessionToken=user_9%3A%3Aabc.def.ghi")
    }

    @Test func missingManualCookie() async {
        let provider = CursorProvider(
            transport: StubTransport(status: 200), databaseURL: URL(fileURLWithPath: "/nope"), manualCookie: { nil })
        await #expect(throws: ProviderError.needsAuth(.addCursorCookie)) {
            try await provider.fetch(FetchContext(now: now, config: ProviderConfig(cursorSource: .manual)))
        }
    }

    @Test func fallsBackToLegacyRequestsWithoutAPlan() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let token = makeJWT(["sub": "auth0|user_7", "exp": now.timeIntervalSince1970 + 3600])
        let legacy = Data(#"{"gpt-4":{"numRequests":50,"maxRequestUsage":500},"startOfMonth":"2026-10-01T00:00:00Z"}"#.utf8)
        let summary = try Fixture.data("cursor_summary_no_plan")
        let transport = StubTransport { request in
            request.url?.path == "/api/usage" ? .init(status: 200, body: legacy) : .init(status: 200, body: summary)
        }
        let provider = CursorProvider(transport: transport, databaseURL: try database(token: token, in: directory))

        let snapshot = try await provider.fetch(FetchContext(now: now))
        #expect(snapshot.metrics.map(\.id) == ["cursor.requests.gpt-4"])
        #expect(transport.requests.last?.url?.query == "user=user_7")
    }
}

struct OpenAITests {
    private let now = Date(utc: "2026-10-11T12:00:00Z")

    private func provider(_ transport: StubTransport, key: String? = "sk-admin-test") -> OpenAIProvider {
        OpenAIProvider(transport: transport, adminKey: { key })
    }

    private func pagedTransport() throws -> StubTransport {
        let page1 = try Fixture.data("openai_costs_page1")
        let page2 = try Fixture.data("openai_costs_page2")
        return StubTransport { request in
            let isSecondPage = request.url?.query?.contains("page=") == true
            return .init(status: 200, body: isSecondPage ? page2 : page1)
        }
    }

    @Test func sumsTodayMonthAndModelsAcrossPages() async throws {
        let transport = try pagedTransport()
        let snapshot = try await provider(transport).fetch(FetchContext(now: now))

        let month = try #require(snapshot.metrics.first { $0.role == .spendMonth })
        let today = try #require(snapshot.metrics.first { $0.role == .spendToday })
        #expect(abs(month.used - 6.0) < 0.0001)
        #expect(abs(today.used - 1.5) < 0.0001)
        #expect(month.limit == nil)
        #expect(month.resetsAt == Date(utc: "2026-11-01T00:00:00Z"))
        #expect(snapshot.currencyCode == "USD")

        #expect(snapshot.breakdown.map(\.label) == ["gpt-5", "gpt-4.1-mini-2025-04-14", "text-embedding-3-small"])
        #expect(abs(snapshot.breakdown[0].amount - 4.85) < 0.0001)
        #expect(snapshot.history.count == 30)
        #expect(snapshot.history.last?.day == Date(utc: "2026-10-11T00:00:00Z"))
        #expect(abs((snapshot.history.last?.amount ?? 0) - 1.5) < 0.0001)

        #expect(transport.requests.count == 2)
        let first = try #require(transport.requests.first)
        #expect(first.value(forHTTPHeaderField: "Authorization") == "Bearer sk-admin-test")
        let query = try #require(first.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems)
        #expect(query.contains(URLQueryItem(name: "bucket_width", value: "1d")))
        #expect(query.contains(URLQueryItem(name: "group_by", value: "line_item")))
        // 30 days back reaches into September, earlier than the start of the month.
        #expect(query.contains(URLQueryItem(name: "start_time", value: "1789171200")))
        #expect(transport.requests[1].url?.query?.contains("page=page_AAAAAGdGxdEiJdKOAAAAAGcqsYA") == true)
    }

    @Test func budgetMakesTheMonthABoundedMetric() async throws {
        let config = ProviderConfig(openAIMonthlyBudget: 10, openAIProjectID: "proj_abc")
        let transport = try pagedTransport()
        let snapshot = try await provider(transport).fetch(FetchContext(now: now, config: config))
        let month = try #require(snapshot.metrics.first { $0.role == .spendMonth })
        #expect(month.limit == 10)
        #expect(abs((month.fraction ?? 0) - 0.6) < 0.0001)
        #expect(transport.requests.first?.url?.query?.contains("project_ids=proj_abc") == true)
    }

    @Test func missingKeyNeedsAuth() async {
        let transport = StubTransport(status: 200)
        await #expect(throws: ProviderError.needsAuth(.addOpenAIKey)) {
            try await provider(transport, key: nil).fetch(FetchContext(now: now))
        }
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [
        (401, ProviderError.needsAuth(.manualCredentialRejected)),
        (403, .needsAuth(.openAIKeyNotAdmin)),
        (404, .http(status: 404)),
        (429, .rateLimited(retryAfter: nil)),
    ])
    func mapsHTTPErrors(status: Int, expected: ProviderError) async {
        await #expect(throws: expected) {
            try await provider(StubTransport(status: status)).fetch(FetchContext(now: now))
        }
    }

    @Test func modelNameFromLineItem() {
        #expect(OpenAICostSummary.modelName("gpt-4o-2024-08-06, input") == "gpt-4o-2024-08-06")
        #expect(OpenAICostSummary.modelName("web search tool calls") == "web search tool calls")
        #expect(OpenAICostSummary.modelName(nil) == "other")
    }
}

extension JSONDecoder {
    static var usage: JSONDecoder { DateParsing.decoder() }
}
