import XCTest
@testable import SynheartWear

final class OuraProviderTests: XCTestCase {
    var provider: OuraProvider!
    let testAppId = "test-app-oura"
    let testBaseURL = URL(string: "https://api.test.com")!
    let testRedirectUri = "testapp://oauth/callback"

    override func setUp() async throws {
        try await super.setUp()
        provider = OuraProvider(
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
        XCTAssertEqual(provider.vendor, .oura)
    }

    func testNotConnectedByDefault() {
        XCTAssertFalse(provider.isConnected())
        XCTAssertNil(provider.getUserId())
    }

    func testConnectWithCodeStoresUserId() async throws {
        try await provider.connectWithCode(code: "oura-user-abc", state: "x", redirectUri: "x")
        XCTAssertTrue(provider.isConnected())
        XCTAssertEqual(provider.getUserId(), "oura-user-abc")
    }

    func testConnectWithEmptyCodeFails() async {
        do {
            try await provider.connectWithCode(code: "", state: "s", redirectUri: "r")
            XCTFail("Expected authentication failure")
        } catch SynheartWearError.authenticationFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchReadinessNotConnected() async {
        do {
            _ = try await provider.fetchReadiness()
            XCTFail("Expected notConnected")
        } catch SynheartWearError.notConnected {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
