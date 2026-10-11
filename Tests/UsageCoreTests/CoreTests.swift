import Foundation
import SQLite3
import Testing
@testable import UsageCore

struct DateParsingTests {
    @Test(arguments: [
        ("2026-10-23T13:16:38Z", 1792761398.0),
        ("2026-10-23T13:16:38.000Z", 1792761398.0),
        ("2026-10-11T02:00:00.419134+00:00", 1791684000.419134),
        ("2026-10-11T05:00:00+03:00", 1791684000.0),
    ])
    func iso8601(text: String, expected: TimeInterval) throws {
        let date = try #require(DateParsing.iso8601(text))
        #expect(abs(date.timeIntervalSince1970 - expected) < 0.001)
    }

    @Test func rejectsGarbage() {
        #expect(DateParsing.iso8601("yesterday") == nil)
    }

    @Test func epochSecondsAndMilliseconds() {
        #expect(DateParsing.epoch(1_738_425_600) == Date(timeIntervalSince1970: 1_738_425_600))
        #expect(DateParsing.epoch(1_738_425_600_000) == Date(timeIntervalSince1970: 1_738_425_600))
    }
}

struct JWTTests {
    @Test func decodesSubjectAndExpiry() throws {
        let token = makeJWT(["sub": "auth0|user_01ABC", "exp": 1_800_000_000])
        let claims = try #require(JWT.claims(of: token))
        #expect(claims.subject == "auth0|user_01ABC")
        #expect(claims.userID == "user_01ABC")
        #expect(claims.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func subjectWithoutProvider() throws {
        let claims = try #require(JWT.claims(of: makeJWT(["sub": "user_42"])))
        #expect(claims.userID == "user_42")
        #expect(claims.isExpired(at: .now) == false)
    }

    @Test func expiryUsesLeeway() throws {
        let claims = try #require(JWT.claims(of: makeJWT(["sub": "x", "exp": 1000])))
        #expect(claims.isExpired(at: Date(timeIntervalSince1970: 900)) == false)
        #expect(claims.isExpired(at: Date(timeIntervalSince1970: 950)) == true)
    }

    @Test(arguments: ["", "abc", "a.b", "a.%%%.c"])
    func rejectsMalformed(token: String) {
        #expect(JWT.claims(of: token) == nil)
    }
}

struct UsageMetricTests {
    @Test func percentFraction() {
        let metric = UsageMetric(id: "x", role: .session, unit: .percent, used: 45)
        #expect(metric.fraction == 0.45)
        #expect(metric.level == .normal)
    }

    @Test func currencyWithoutLimitIsUnbounded() {
        let metric = UsageMetric(id: "x", role: .spendMonth, unit: .currency(code: "USD"), used: 45)
        #expect(metric.fraction == nil)
    }

    @Test func reportedPercentWins() {
        let metric = UsageMetric(
            id: "x", role: .includedUsage, unit: .currency(code: "USD"), used: 12.4, limit: 20, reportedPercent: 96)
        #expect(metric.fraction == 0.96)
        #expect(metric.level == .critical)
    }

    @Test(arguments: [
        (nil, UsageLevel.normal), (0.0, .normal), (0.7999, .normal),
        (0.80, .warning), (0.9499, .warning), (0.95, .critical), (1.3, .critical),
    ] as [(Double?, UsageLevel)])
    func thresholds(fraction: Double?, expected: UsageLevel) {
        #expect(UsageLevel(fraction: fraction) == expected)
    }
}

struct BackoffPolicyTests {
    @Test func successUsesInterval() {
        #expect(BackoffPolicy.delay(interval: 300, failures: 0, error: nil) == 300)
    }

    @Test func errorsDoubleUpToTheCap() {
        let error = ProviderError.http(status: 500)
        #expect(BackoffPolicy.delay(interval: 60, failures: 1, error: error) == 60)
        #expect(BackoffPolicy.delay(interval: 60, failures: 3, error: error) == 240)
        #expect(BackoffPolicy.delay(interval: 60, failures: 20, error: error) == BackoffPolicy.maximumDelay)
    }

    @Test func rateLimitWaitsAtLeastFiveMinutesAndHonorsRetryAfter() {
        #expect(BackoffPolicy.delay(interval: 60, failures: 1, error: .rateLimited(retryAfter: nil)) == 300)
        #expect(BackoffPolicy.delay(interval: 60, failures: 1, error: .rateLimited(retryAfter: 900)) == 900)
        #expect(BackoffPolicy.delay(interval: 60, failures: 2, error: .rateLimited(retryAfter: 0)) == 600)
    }

    @Test func localAuthChecksKeepTheIntervalButRejectionsBackOff() {
        #expect(BackoffPolicy.delay(interval: 30, failures: 8, error: .needsAuth(.waitingForClaudeCode)) == 30)
        #expect(BackoffPolicy.delay(interval: 60, failures: 3, error: .needsAuth(.openCursor)) == 240)
    }

    @Test func offlineKeepsTheInterval() {
        #expect(BackoffPolicy.delay(interval: 120, failures: 5, error: .offline) == 120)
    }
}

struct SQLiteValueReaderTests {
    @Test func readsTextAndBlobValues() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let url = directory.url.appending(path: "state.vscdb")

        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'abc.def.ghi')", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO ItemTable VALUES ('blob', CAST('xyz' AS BLOB))", nil, nil, nil)
        sqlite3_close(db)

        #expect(try SQLiteValueReader.value(forKey: "cursorAuth/accessToken", in: url) == "abc.def.ghi")
        #expect(try SQLiteValueReader.value(forKey: "blob", in: url) == "xyz")
        #expect(try SQLiteValueReader.value(forKey: "missing", in: url) == nil)
        // A quote in the key must not break the query.
        #expect(try SQLiteValueReader.value(forKey: "x' OR '1'='1", in: url) == nil)
    }

    @Test func missingFileFails() {
        #expect(throws: SQLiteValueReader.ReadError.openFailed) {
            try SQLiteValueReader.value(forKey: "k", in: URL(fileURLWithPath: "/nonexistent/state.vscdb"))
        }
    }
}

@MainActor
struct MenuBarSummaryTests {
    private func statuses() -> [ProviderID: ProviderStatus] {
        let now = Date.now
        return [
            .claude: ProviderStatus(snapshot: ProviderSnapshot(provider: .claude, fetchedAt: now, metrics: [
                UsageMetric(id: "claude.session", role: .session, unit: .percent, used: 30),
                UsageMetric(id: "claude.weekly", role: .weekly, unit: .percent, used: 85),
            ])),
            .cursor: ProviderStatus(snapshot: ProviderSnapshot(provider: .cursor, fetchedAt: now, metrics: [
                UsageMetric(id: "cursor.included", role: .includedUsage, unit: .currency(code: "USD"), used: 5,
                            limit: 20, reportedPercent: 25),
            ])),
            .openAI: ProviderStatus(snapshot: ProviderSnapshot(provider: .openAI, fetchedAt: now, metrics: [
                UsageMetric(id: "openai.month", role: .spendMonth, unit: .currency(code: "USD"), used: 45.67),
            ])),
        ]
    }

    @Test func highestPicksTheMostConstrainedMetric() {
        let summary = MenuBarSummary(statuses: statuses(), enabled: ProviderID.allCases, mode: .highest, pinnedMetricID: nil)
        #expect(summary.segments.map(\.metric.id) == ["claude.weekly"])
        #expect(summary.level == .warning)
        #expect(summary.fill == 0.85)
    }

    @Test func iconOnlyHasNoText() {
        let summary = MenuBarSummary(statuses: statuses(), enabled: ProviderID.allCases, mode: .iconOnly, pinnedMetricID: nil)
        #expect(summary.segments.isEmpty)
        #expect(summary.fraction == 0.85)
    }

    @Test func pinnedMetricAndFallback() {
        let pinned = MenuBarSummary(
            statuses: statuses(), enabled: ProviderID.allCases, mode: .pinned, pinnedMetricID: "openai.month")
        #expect(pinned.segments.map(\.metric.id) == ["openai.month"])
        #expect(pinned.level == .normal)

        let missing = MenuBarSummary(statuses: statuses(), enabled: ProviderID.allCases, mode: .pinned, pinnedMetricID: "gone")
        #expect(missing.segments.map(\.metric.id) == ["claude.weekly"])
    }

    @Test func perServiceIncludesUnboundedSpend() {
        let summary = MenuBarSummary(statuses: statuses(), enabled: ProviderID.allCases, mode: .perService, pinnedMetricID: nil)
        #expect(summary.segments.map(\.provider) == [.claude, .cursor, .openAI])
        #expect(summary.segments.map(\.metric.id) == ["claude.weekly", "cursor.included", "openai.month"])
    }

    @Test func disabledProvidersAreIgnored() {
        let summary = MenuBarSummary(statuses: statuses(), enabled: [.cursor], mode: .highest, pinnedMetricID: nil)
        #expect(summary.segments.map(\.metric.id) == ["cursor.included"])
    }

    @Test func noDataShowsAnEmptyBar() {
        let summary = MenuBarSummary(statuses: [:], enabled: ProviderID.allCases, mode: .highest, pinnedMetricID: nil)
        #expect(summary.segments.isEmpty)
        #expect(summary.fill == 0)
    }

    @Test(arguments: [(nil, 0), (-0.2, 0), (0.3, 0.3), (1, 1), (1.5, 1)] as [(Double?, Double)])
    func fillIsClamped(fraction: Double?, fill: Double) {
        #expect(MenuBarSummary.fill(for: fraction) == fill)
    }
}

@MainActor
struct UsageStoreTests {
    struct FailingThenOK: UsageProvider {
        let id = ProviderID.cursor
        let calls: Counter

        func pollingInterval(userInterval: TimeInterval, config: ProviderConfig) -> TimeInterval { userInterval }

        func fetch(_ context: FetchContext) async throws(ProviderError) -> ProviderSnapshot {
            if calls.increment() == 1 {
                return ProviderSnapshot(provider: .cursor, fetchedAt: context.now, metrics: [
                    UsageMetric(id: "cursor.included", role: .includedUsage, unit: .percent, used: 10),
                ])
            }
            throw .http(status: 503)
        }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() -> Int { lock.withLock { value += 1; return value } }
    }

    private func makeStore(_ provider: some UsageProvider) -> UsageStore {
        let defaults = UserDefaults(suiteName: "UsageStoreTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.refreshInterval = 300
        return UsageStore(providers: [provider], settings: settings, randomJitter: { 1 })
    }

    @Test func keepsTheLastGoodSnapshotOnErrorAndBacksOff() async {
        let store = makeStore(FailingThenOK(calls: Counter()))

        await store.refresh([.cursor], userInitiated: false)
        #expect(store.status(.cursor).snapshot?.metrics.first?.used == 10)
        #expect(store.status(.cursor).error == nil)

        await store.refresh([.cursor], userInitiated: false)
        await store.refresh([.cursor], userInitiated: false)
        let status = store.status(.cursor)
        #expect(status.snapshot?.metrics.first?.used == 10)
        #expect(status.error == .http(status: 503))
        #expect(status.consecutiveFailures == 2)
        let wait = status.nextEligible.timeIntervalSince(status.lastAttempt!)
        #expect(abs(wait - 600) < 1)
    }

    @Test func refreshDueSkipsProvidersThatAreNotDue() async {
        let counter = Counter()
        let store = makeStore(FailingThenOK(calls: counter))
        await store.refreshDue()
        await store.refreshDue()
        #expect(counter.increment() == 2)  // one fetch so far, then this call
    }

    struct NotSetUp: UsageProvider {
        let id = ProviderID.openAI

        func pollingInterval(userInterval: TimeInterval, config: ProviderConfig) -> TimeInterval { userInterval }

        func fetch(_ context: FetchContext) async throws(ProviderError) -> ProviderSnapshot {
            throw .needsAuth(.addOpenAIKey)
        }
    }

    @Test func providersThatNeedSetupAreNotShown() async {
        let store = makeStore(NotSetUp())
        #expect(store.shownProviders.contains(.openAI))
        await store.refresh([.openAI], userInitiated: false)
        #expect(store.status(.openAI).needsSetup)
        #expect(!store.shownProviders.contains(.openAI))
    }

    @Test(arguments: [
        (AuthHint.installClaudeBridge, false, true),
        (.addOpenAIKey, true, true),
        (.addCursorCookie, false, true),
        (.openCursor, false, true),
        (.openCursor, true, false),
        (.grantKeychainAccess, false, true),
        (.waitingForClaudeCode, false, false),
        (.openAIKeyNotAdmin, false, false),
    ])
    func needsSetup(hint: AuthHint, hadData: Bool, expected: Bool) {
        var status = ProviderStatus(snapshot: hadData ? ProviderSnapshot(provider: .cursor, fetchedAt: .now, metrics: []) : nil)
        status.error = .needsAuth(hint)
        #expect(status.needsSetup == expected)
    }

    @Test func otherErrorsDoNotHideAProvider() {
        var status = ProviderStatus()
        status.error = .http(status: 500)
        #expect(!status.needsSetup)
    }

    @Test func offlineSkipsPolling() async {
        let counter = Counter()
        let store = makeStore(FailingThenOK(calls: counter))
        store.isOffline = true
        await store.refreshDue()
        #expect(counter.increment() == 1)
    }
}
