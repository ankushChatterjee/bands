import XCTest
@testable import bands

final class SecureTokenStoreTests: XCTestCase {
    private var service = "com.example.bands.tests.\(UUID().uuidString)"

    func testStoresReadsListsAndDeletesMultipleTokens() throws {
        let store = SecureTokenStore(service: service)
        try store.setToken("jev-secret", forKey: "bands:jev_key")
        try store.setToken("other-secret", forKey: "bands:other_key")
        defer {
            try? store.deleteToken(forKey: "bands:jev_key")
            try? store.deleteToken(forKey: "bands:other_key")
        }

        XCTAssertEqual(try store.token(forKey: "bands:jev_key"), "jev-secret")
        XCTAssertEqual(try store.keys(), ["bands:jev_key", "bands:other_key"])

        try store.deleteToken(forKey: "bands:jev_key")
        XCTAssertNil(try store.token(forKey: "bands:jev_key"))
    }

    func testRejectsEmptyKeysAndTokens() {
        let store = SecureTokenStore(service: service)
        XCTAssertThrowsError(try store.setToken("secret", forKey: "")) { error in
            XCTAssertEqual(error as? SecureTokenStoreError, .emptyKey)
        }
        XCTAssertThrowsError(try store.setToken("", forKey: "bands:jev_key")) { error in
            XCTAssertEqual(error as? SecureTokenStoreError, .emptyToken)
        }
    }

    func testUpdatingTokenReplacesStoredValue() throws {
        let store = SecureTokenStore(service: service)
        defer { try? store.deleteToken(forKey: "bands:jev_key") }

        try store.setToken("first-secret", forKey: "bands:jev_key")
        try store.setToken("second-secret", forKey: "bands:jev_key")

        XCTAssertEqual(try store.token(forKey: "bands:jev_key"), "second-secret")
    }
}
