import XCTest
@testable import bands

final class LocalTokenStoreTests: XCTestCase {
    private var directoryURL: URL!
    private var store: LocalTokenStore!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bands-token-store-\(UUID().uuidString)", isDirectory: true)
        store = LocalTokenStore(directoryURL: directoryURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directoryURL)
        store = nil
        directoryURL = nil
    }

    func testStoresReadsListsAndDeletesMultipleTokens() throws {
        try store.setToken("jev-secret", forKey: "bands:jev_key")
        try store.setToken("other-secret", forKey: "bands:other_key")

        XCTAssertEqual(try store.token(forKey: "bands:jev_key"), "jev-secret")
        XCTAssertEqual(try store.keys(), ["bands:jev_key", "bands:other_key"])

        try store.deleteToken(forKey: "bands:jev_key")
        XCTAssertNil(try store.token(forKey: "bands:jev_key"))
    }

    func testRejectsEmptyKeysAndTokens() {
        XCTAssertThrowsError(try store.setToken("secret", forKey: "")) { error in
            XCTAssertEqual(error as? LocalTokenStoreError, .emptyKey)
        }
        XCTAssertThrowsError(try store.setToken("", forKey: "bands:jev_key")) { error in
            XCTAssertEqual(error as? LocalTokenStoreError, .emptyToken)
        }
    }

    func testUpdatingTokenReplacesStoredValue() throws {
        try store.setToken("first-secret", forKey: "bands:jev_key")
        try store.setToken("second-secret", forKey: "bands:jev_key")

        XCTAssertEqual(try store.token(forKey: "bands:jev_key"), "second-secret")
    }

    func testCreatesPrivateDirectoryAndTokenFile() throws {
        try store.setToken("jev-secret", forKey: "bands:jev_key")

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: directoryURL.appendingPathComponent("tokens.json").path
        )
        XCTAssertEqual(directoryAttributes[.posixPermissions] as? NSNumber, 0o700)
        XCTAssertEqual(fileAttributes[.posixPermissions] as? NSNumber, 0o600)
    }

    func testRejectsInvalidStoredFile() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: directoryURL.appendingPathComponent("tokens.json"))

        XCTAssertThrowsError(try store.token(forKey: "bands:jev_key")) { error in
            XCTAssertEqual(error as? LocalTokenStoreError, .invalidStoredValue)
        }
    }
}
