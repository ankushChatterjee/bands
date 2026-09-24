import Foundation

enum SecureTokenKeys {
    static let jev = "jev_token"
}

/// Stores user-supplied tokens in a local, user-private file.
///
/// The store deliberately does not use Keychain. Tokens are persisted at
/// `~/Library/Application Support/bands/tokens.json` in a directory with mode
/// 0700; the file itself has mode 0600. This protects against other macOS
/// users and accidental disclosure, but not against software running as the
/// current user. FileVault should remain enabled to protect the data at rest.
final class LocalTokenStore: @unchecked Sendable {
    static let shared = LocalTokenStore()

    private static let fileName = "tokens.json"

    private let directoryURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var cachedTokens: [String: String]?

    init(
        directoryURL: URL = LocalTokenStore.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent(Self.fileName, isDirectory: false)
        self.fileManager = fileManager
    }

    func setToken(_ token: String, forKey key: String) throws {
        try validateKey(key)
        guard !token.isEmpty else { throw LocalTokenStoreError.emptyToken }

        lock.lock()
        defer { lock.unlock() }
        var tokens = try loadTokens()
        tokens[key] = token
        try save(tokens)
    }

    func token(forKey key: String) throws -> String? {
        try validateKey(key)

        lock.lock()
        defer { lock.unlock() }
        return try loadTokens()[key]
    }

    func deleteToken(forKey key: String) throws {
        try validateKey(key)

        lock.lock()
        defer { lock.unlock() }
        var tokens = try loadTokens()
        guard tokens.removeValue(forKey: key) != nil else { return }
        try save(tokens)
    }

    /// Returns stored keys without exposing their token values.
    func keys() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return try loadTokens().keys.sorted()
    }

    private func loadTokens() throws -> [String: String] {
        if let cachedTokens { return cachedTokens }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            cachedTokens = [:]
            return [:]
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let file = try JSONDecoder().decode(TokenFile.self, from: data)
            guard file.version == TokenFile.currentVersion else {
                throw LocalTokenStoreError.invalidStoredValue
            }
            cachedTokens = file.tokens
            return file.tokens
        } catch let error as LocalTokenStoreError {
            throw error
        } catch {
            throw LocalTokenStoreError.invalidStoredValue
        }
    }

    private func save(_ tokens: [String: String]) throws {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)

            let data = try JSONEncoder().encode(TokenFile(tokens: tokens))
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            cachedTokens = tokens
        } catch {
            throw LocalTokenStoreError.storageUnavailable
        }
    }

    private func validateKey(_ key: String) throws {
        guard !key.isEmpty else { throw LocalTokenStoreError.emptyKey }
    }

    private static func defaultDirectoryURL() -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory is unavailable")
        }
        return applicationSupport.appendingPathComponent("bands", isDirectory: true)
    }
}

private struct TokenFile: Codable {
    static let currentVersion = 1

    let version: Int
    let tokens: [String: String]

    init(tokens: [String: String]) {
        self.version = Self.currentVersion
        self.tokens = tokens
    }
}

enum LocalTokenStoreError: Error, Equatable {
    case emptyKey
    case emptyToken
    case invalidStoredValue
    case storageUnavailable
}
