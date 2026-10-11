import Foundation
import Security

/// Usage AI's own secrets (OpenAI admin key, manual tokens) in the login keychain.
public struct KeychainStore: Sendable {
    public enum Account: String, CaseIterable, Sendable {
        case openAIAdminKey = "openai.adminKey"
        case cursorManualCookie = "cursor.manualCookie"
    }

    public let service: String

    public init(service: String = "io.github.jpleopoldino.UsageAI") {
        self.service = service
    }

    public func read(_ account: Account) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func contains(_ account: Account) -> Bool {
        var query = baseQuery(account)
        query[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public func write(_ value: String, for account: Account) -> Bool {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, update)
        if status == errSecItemNotFound {
            var item = baseQuery(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            item[kSecAttrLabel as String] = "Usage AI (\(account.rawValue))"
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    public func delete(_ account: Account) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private func baseQuery(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }
}

/// Reads a generic password that belongs to another app (e.g. Claude Code's credentials).
public enum ForeignKeychainItem {
    public enum ReadError: Error, Equatable, Sendable {
        case notFound
        /// macOS wants to ask the user. Retry with `allowUI: true` after a user action.
        case interactionNeeded
        case denied
        case failed(OSStatus)
    }

    public static func read(service: String, allowUI: Bool) -> Result<Data, ReadError> {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowUI {
            query[kSecUseAuthenticationUI as String] = (LegacyKeychainUI() as any LegacyKeychainUIValue).fail
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .failure(.failed(status)) }
            return .success(data)
        case errSecItemNotFound:
            return .failure(.notFound)
        case errSecInteractionNotAllowed, errSecAuthFailed:
            return .failure(allowUI ? .denied : .interactionNeeded)
        case errSecUserCanceled:
            return .failure(.denied)
        default:
            return .failure(.failed(status))
        }
    }
}

/// `kSecUseAuthenticationUIFail` is deprecated, but the legacy ACL prompt of the file-based
/// keychain only honors that value. Reading it through a protocol keeps the build free of a
/// warning that would otherwise show up on every build.
private protocol LegacyKeychainUIValue {
    var fail: CFString { get }
}

private struct LegacyKeychainUI: LegacyKeychainUIValue {
    @available(macOS, deprecated: 11.0)
    var fail: CFString { kSecUseAuthenticationUIFail }
}
