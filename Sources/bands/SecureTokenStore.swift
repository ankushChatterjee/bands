import Foundation
import Security

enum SecureTokenKeys {
    static let jev = "jev_token"
}

/// Stores user-supplied secrets in the macOS Keychain.
///
/// Tokens are generic-password items grouped under one versioned service and
/// addressed by their caller-provided key, for example `bands:jev_key`.
/// A macOS Keychain access list trusts the signed Bands app, so its normal
/// reads do not prompt for the user's Mac password or Touch ID. The service
/// version prevents items created by an older build with a user-presence ACL
/// from being reused.
/// The item is available while the Mac's login session is unlocked and is not
/// migrated to another device.
final class SecureTokenStore: @unchecked Sendable {
    static let shared = SecureTokenStore()

    private let service: String
    private let cacheLock = NSLock()
    /// Secrets stay in memory only for this running app process. This avoids a
    /// Keychain authorization request on every Jev capture while retaining the
    /// Keychain as the only persistent store.
    private var tokenCache: [String: String] = [:]

    // v4 starts clean after v3 was created by an app bundle whose signature was
    // modified during the build script. Never touch that legacy record: doing
    // so would re-trigger its old Keychain authorization dialog.
    init(service: String = "com.example.bands.secure-tokens.v4") {
        self.service = service
    }

    func setToken(_ token: String, forKey key: String) throws {
        try validateKey(key)
        guard !token.isEmpty else {
            throw SecureTokenStoreError.emptyToken
        }

        let query = itemQuery(forKey: key)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccess as String: try trustedBandsAccess()
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            cache(token, forKey: key)
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SecureTokenStoreError.keychain(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccess as String] = try trustedBandsAccess()

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureTokenStoreError.keychain(addStatus)
        }
        cache(token, forKey: key)
    }

    func token(forKey key: String) throws -> String? {
        try validateKey(key)
        if let cached = cachedToken(forKey: key) { return cached }

        var query = itemQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecureTokenStoreError.keychain(status)
        }
        guard let data = result as? Data else {
            throw SecureTokenStoreError.invalidStoredValue
        }
        guard let token = String(data: data, encoding: .utf8) else {
            throw SecureTokenStoreError.invalidStoredValue
        }
        cache(token, forKey: key)
        return token
    }

    func deleteToken(forKey key: String) throws {
        try validateKey(key)
        let status = SecItemDelete(itemQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureTokenStoreError.keychain(status)
        }
        removeCachedToken(forKey: key)
    }

    /// Returns the keys stored by this app without exposing their secret values.
    func keys() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw SecureTokenStoreError.keychain(status)
        }

        let items = result as? [[String: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    private func itemQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private func validateKey(_ key: String) throws {
        guard !key.isEmpty else { throw SecureTokenStoreError.emptyKey }
    }

    /// macOS Keychain ACLs can explicitly trust a signed application. This
    /// gives Bands silent access to its own token while denying other apps,
    /// rather than relying on an "Allow" choice at every read.
    private func trustedBandsAccess() throws -> SecAccess {
        guard let executablePath = Bundle.main.executablePath else {
            throw SecureTokenStoreError.unavailableExecutablePath
        }

        var trustedApplication: SecTrustedApplication?
        let trustedStatus = executablePath.withCString {
            SecTrustedApplicationCreateFromPath($0, &trustedApplication)
        }
        guard trustedStatus == errSecSuccess, let trustedApplication else {
            throw SecureTokenStoreError.keychain(trustedStatus)
        }

        var access: SecAccess?
        let accessStatus = SecAccessCreate(
            "bands Jev token" as CFString,
            [trustedApplication] as CFArray,
            &access
        )
        guard accessStatus == errSecSuccess, let access else {
            throw SecureTokenStoreError.keychain(accessStatus)
        }
        return access
    }

    private func cachedToken(forKey key: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return tokenCache[key]
    }

    private func cache(_ token: String, forKey key: String) {
        cacheLock.lock()
        tokenCache[key] = token
        cacheLock.unlock()
    }

    private func removeCachedToken(forKey key: String) {
        cacheLock.lock()
        tokenCache.removeValue(forKey: key)
        cacheLock.unlock()
    }
}

enum SecureTokenStoreError: Error, Equatable {
    case emptyKey
    case emptyToken
    case invalidStoredValue
    case unavailableExecutablePath
    case keychain(OSStatus)
}
