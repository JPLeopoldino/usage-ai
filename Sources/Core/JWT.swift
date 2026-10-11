import Foundation

public struct JWTClaims: Sendable, Equatable {
    public var subject: String?
    public var expiresAt: Date?

    /// The part of `sub` after the last `|` (e.g. `auth0|user_abc` → `user_abc`).
    public var userID: String? {
        guard let subject, let last = subject.split(separator: "|").last, !last.isEmpty else { return nil }
        return String(last)
    }

    public func isExpired(at now: Date, leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= leeway
    }
}

public enum JWT {
    /// Decodes the payload of a JWT without verifying its signature.
    public static func claims(of token: String) -> JWTClaims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let data = base64URLDecode(String(parts[1])) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let expiresAt = (object["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return JWTClaims(subject: object["sub"] as? String, expiresAt: expiresAt)
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}
