import XCTest
@testable import lanes

final class SecureTokenStoreTests: XCTestCase {
    private var service = "com.example.lanes.tests.\(UUID().uuidString)"

    func testStoresReadsListsAndDeletesMultipleTokens() throws {
        let store = SecureTokenStore(service: service)
        try store.setToken("jev-secret", forKey: "lanes:jev_key")
        try store.setToken("other-secret", forKey: "lanes:other_key")
        defer {
            try? store.deleteToken(forKey: "lanes:jev_key")
            try? store.deleteToken(forKey: "lanes:other_key")
        }

        XCTAssertEqual(try store.token(forKey: "lanes:jev_key"), "jev-secret")
        XCTAssertEqual(try store.keys(), ["lanes:jev_key", "lanes:other_key"])

        try store.deleteToken(forKey: "lanes:jev_key")
        XCTAssertNil(try store.token(forKey: "lanes:jev_key"))
    }

    func testRejectsEmptyKeysAndTokens() {
        let store = SecureTokenStore(service: service)
        XCTAssertThrowsError(try store.setToken("secret", forKey: "")) { error in
            XCTAssertEqual(error as? SecureTokenStoreError, .emptyKey)
        }
        XCTAssertThrowsError(try store.setToken("", forKey: "lanes:jev_key")) { error in
            XCTAssertEqual(error as? SecureTokenStoreError, .emptyToken)
        }
    }

    func testUpdatingTokenReplacesStoredValue() throws {
        let store = SecureTokenStore(service: service)
        defer { try? store.deleteToken(forKey: "lanes:jev_key") }

        try store.setToken("first-secret", forKey: "lanes:jev_key")
        try store.setToken("second-secret", forKey: "lanes:jev_key")

        XCTAssertEqual(try store.token(forKey: "lanes:jev_key"), "second-secret")
    }
}
