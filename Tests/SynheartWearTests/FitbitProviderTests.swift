import XCTest
@testable import SynheartWear

final class FitbitProviderTests: XCTestCase {
    var provider: FitbitProvider!
    let testAppId = "test-app-fitbit"
    let testBaseURL = URL(string: "https://api.test.com")!
    let testRedirectUri = "testapp://oauth/callback"

    override func setUp() async throws {
        try await super.setUp()
        provider = FitbitProvider(
            appId: testAppId,
            baseUrl: testBaseURL,
            redirectUri: testRedirectUri
        )
        try? await provider.disconnect()
    }

    override func tearDown() async throws {
        try? await provider?.disconnect()
        provider = nil
        try await super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(provider)
        XCTAssertEqual(provider.vendor, .fitbit)
    }

    func testNotConnectedByDefault() {
        XCTAssertFalse(provider.isConnected())
        XCTAssertNil(provider.getUserId())
    }

    func testConnectWithCodeStoresUserId() async throws {
        try await provider.connectWithCode(code: "fitbit-user-123", state: "ignored", redirectUri: "ignored")
        XCTAssertTrue(provider.isConnected())
        XCTAssertEqual(provider.getUserId(), "fitbit-user-123")
    }

    func testConnectWithEmptyCodeFails() async {
        do {
            try await provider.connectWithCode(code: "", state: "s", redirectUri: "r")
            XCTFail("Expected authentication failure")
        } catch SynheartWearError.authenticationFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectWithoutUserIdThrows() async {
        do {
            try await provider.connect()
            XCTFail("Expected error when userId missing")
        } catch SynheartWearError.apiError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchHrvNotConnected() async {
        do {
            _ = try await provider.fetchHrv()
            XCTFail("Expected notConnected")
        } catch SynheartWearError.notConnected {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
