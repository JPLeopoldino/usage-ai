import Foundation

public enum BackoffPolicy {
    public static let maximumDelay: TimeInterval = 30 * 60
    public static let minimumRateLimitDelay: TimeInterval = 5 * 60

    /// Seconds to wait before the next attempt.
    /// - Parameters:
    ///   - interval: the normal polling interval for the provider.
    ///   - failures: consecutive failures so far (0 means the last attempt succeeded).
    ///   - error: the last error, if any.
    ///   - jitter: a factor applied to failure delays, normally random in 0.8…1.2.
    public static func delay(
        interval: TimeInterval,
        failures: Int,
        error: ProviderError?,
        jitter: Double = 1
    ) -> TimeInterval {
        guard failures > 0, let error else { return interval }

        let exponent = Double(min(failures - 1, 10))
        switch error {
        case .rateLimited(let retryAfter):
            let base = max(retryAfter ?? 0, minimumRateLimitDelay) * pow(2, exponent)
            return min(base, maximumDelay)
        case .offline:
            // The network monitor triggers a refresh when the connection comes back.
            return interval
        case .needsAuth(let hint) where hint.isLocalCheck:
            // Nothing reaches a server, so keep checking at the normal pace.
            return interval
        case .needsAuth:
            // Don't hammer a server that rejected the credential.
            return min(interval * pow(2, exponent), maximumDelay)
        case .http, .unexpectedShape, .other:
            return min(interval * pow(2, exponent) * jitter, maximumDelay)
        }
    }
}
