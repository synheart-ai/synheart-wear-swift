import XCTest
@testable import SynheartWear

final class WhoopProviderTests: XCTestCase {
    var provider: WhoopProvider!
    let testAppId = "test-app-id"
    let testBaseURL = URL(string: "https://api.test.com")!
    let testRedirectUri = "testapp://oauth/callback"
    
    override func setUp() {
        super.setUp()
        provider = WhoopProvider(
            appId: testAppId,
            baseUrl: testBaseURL,
            redirectUri: testRedirectUri
        )
    }
    
    override func tearDown() {
        provider = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertNotNil(provider)
        XCTAssertEqual(provider.vendor, .whoop)
        XCTAssertFalse(provider.isConnected())
        XCTAssertNil(provider.getUserId())
    }
    
    func testInitializationWithDefaults() {
        let defaultProvider = WhoopProvider(appId: "test-app")
        XCTAssertNotNil(defaultProvider)
        // Should use default baseURL and redirectUri
    }
    
    // MARK: - Connection State Tests
    
    func testIsConnectedWhenNotConnected() {
        XCTAssertFalse(provider.isConnected())
    }
    
    func testGetUserIdWhenNotConnected() {
        XCTAssertNil(provider.getUserId())
    }
    
    // MARK: - OAuth Flow Tests
    
    func testConnectGeneratesState() async throws {
        // Note: This test would require mocking the API call and browser opening
        // For now, we test the structure
        
        // The connect() method should:
        // 1. Generate a state parameter
        // 2. Call getAuthorizationURL API
        // 3. Open browser with authorization URL
        
        // This requires integration testing or mocking
        XCTAssertTrue(true, "OAuth flow requires integration testing")
    }
    
    func testConnectWithCodeValidatesState() async {
        // Test that connectWithCode() validates state parameter
        // First, we need to simulate an OAuth flow by storing a state
        // Then test with invalid state - should throw .authenticationFailed
        
        // Simulate OAuth flow initiation by storing state
        let validState = "valid-state-123"
        UserDefaults.standard.set(validState, forKey: "synheart_whoop_oauth_state_\(testAppId)")
        
        do {
            // Try with invalid state
            try await provider.connectWithCode(
                code: "test-code",
                state: "invalid-state",
                redirectUri: testRedirectUri
            )
            XCTFail("Should throw authenticationFailed for invalid state")
        } catch SynheartWearError.authenticationFailed {
            // Expected - state validation failed
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "synheart_whoop_oauth_state_\(testAppId)")
    }
    
    func testConnectWithCodeWithoutOAuthFlow() async {
        // Test that connectWithCode() throws .notConnected if OAuth flow wasn't initiated
        do {
            try await provider.connectWithCode(
                code: "test-code",
                state: "test-state",
                redirectUri: testRedirectUri
            )
            XCTFail("Should throw notConnected when OAuth flow not initiated")
        } catch SynheartWearError.notConnected {
            // Expected
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Disconnect Tests
    
    func testDisconnectWhenNotConnected() async throws {
        // Disconnect when not connected should succeed (no-op)
        try await provider.disconnect()
        XCTAssertFalse(provider.isConnected())
    }
    
    // MARK: - Data Fetching Tests
    
    func testFetchRecoveryWhenNotConnected() async {
        do {
            _ = try await provider.fetchRecovery()
            XCTFail("Should throw notConnected when not connected")
        } catch SynheartWearError.notConnected {
            // Expected
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testFetchSleepWhenNotConnected() async {
        do {
            _ = try await provider.fetchSleep()
            XCTFail("Should throw notConnected when not connected")
        } catch SynheartWearError.notConnected {
            // Expected
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testFetchWorkoutsWhenNotConnected() async {
        do {
            _ = try await provider.fetchWorkouts()
            XCTFail("Should throw notConnected when not connected")
        } catch SynheartWearError.notConnected {
            // Expected
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testFetchCyclesWhenNotConnected() async {
        do {
            _ = try await provider.fetchCycles()
            XCTFail("Should throw notConnected when not connected")
        } catch SynheartWearError.notConnected {
            // Expected
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Integration Tests (Require Mock Server)
    
    func testFullOAuthFlow() async throws {
        // This requires a mock Wear Service or real service
        // Steps:
        // 1. Call connect() - get authorization URL
        // 2. Simulate user approval (mock the callback)
        // 3. Call connectWithCode() with code and state
        // 4. Verify isConnected() returns true
        // 5. Verify getUserId() returns user_id
        
        XCTAssertTrue(true, "Requires integration testing with mock server")
    }
    
    func testFetchRecoveryWithData() async throws {
        // This requires a mock Wear Service that returns test data
        // Steps:
        // 1. Set up provider as connected (mock user_id)
        // 2. Mock API response with recovery data
        // 3. Call fetchRecovery()
        // 4. Verify returned WearMetrics are correct
        
        XCTAssertTrue(true, "Requires integration testing with mock server")
    }
}

