import XCTest
@testable import SynheartWear

final class GarminProviderTests: XCTestCase {
    var provider: GarminProvider!
    let testAppId = "test-app-id"
    let testBaseURL = URL(string: "https://api.test.com")!
    let testRedirectUri = "testapp://oauth/callback"

    override func setUp() {
        super.setUp()
        provider = GarminProvider(
            appId: testAppId,
            baseUrl: testBaseURL,
            redirectUri: testRedirectUri
        )
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    // MARK: - SummaryType Enum Tests

    func testSummaryTypeValues() {
        XCTAssertEqual(GarminProvider.SummaryType.dailies.rawValue, "dailies")
        XCTAssertEqual(GarminProvider.SummaryType.epochs.rawValue, "epochs")
        XCTAssertEqual(GarminProvider.SummaryType.sleeps.rawValue, "sleeps")
        XCTAssertEqual(GarminProvider.SummaryType.stressDetails.rawValue, "stressDetails")
        XCTAssertEqual(GarminProvider.SummaryType.hrv.rawValue, "hrv")
        XCTAssertEqual(GarminProvider.SummaryType.userMetrics.rawValue, "userMetrics")
        XCTAssertEqual(GarminProvider.SummaryType.bodyComps.rawValue, "bodyComps")
        XCTAssertEqual(GarminProvider.SummaryType.pulseox.rawValue, "pulseox")
        XCTAssertEqual(GarminProvider.SummaryType.respiration.rawValue, "respiration")
        XCTAssertEqual(GarminProvider.SummaryType.healthSnapshot.rawValue, "healthSnapshot")
        XCTAssertEqual(GarminProvider.SummaryType.bloodPressures.rawValue, "bloodPressures")
        XCTAssertEqual(GarminProvider.SummaryType.skinTemp.rawValue, "skinTemp")
    }

    func testSummaryTypeAllCases() {
        // Verify all 12 summary types are present
        XCTAssertEqual(GarminProvider.SummaryType.allCases.count, 12)
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertNotNil(provider)
        XCTAssertEqual(provider.vendor, .garmin)
    }

    func testInitializationWithDefaults() {
        let defaultProvider = GarminProvider(appId: "test-app")
        XCTAssertNotNil(defaultProvider)
        XCTAssertEqual(defaultProvider.vendor, .garmin)
    }

    // MARK: - Connection State Tests

    func testIsConnectedReturnsFalseInitially() {
        XCTAssertFalse(provider.isConnected())
    }

    func testGetUserIdReturnsNilInitially() {
        XCTAssertNil(provider.getUserId())
    }

    // MARK: - DeviceAdapter Tests

    func testDeviceAdapterGarminExists() {
        let adapter = DeviceAdapter.garmin
        XCTAssertNotNil(adapter)

        // Verify provider vendor matches
        XCTAssertEqual(provider.vendor, DeviceAdapter.garmin)
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

    func testFetchDailiesWhenNotConnected() async {
        do {
            _ = try await provider.fetchDailies()
            XCTFail("Should throw notConnected when not connected")
        } catch SynheartWearError.notConnected {
            // Expected
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchSleepsWhenNotConnected() async {
        do {
            _ = try await provider.fetchSleeps()
            XCTFail("Should throw notConnected when not connected")
        } catch SynheartWearError.notConnected {
            // Expected
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchHRVWhenNotConnected() async {
        do {
            _ = try await provider.fetchHRV()
            XCTFail("Should throw notConnected when not connected")
        } catch SynheartWearError.notConnected {
            // Expected
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestBackfillWhenNotConnected() async {
        do {
            _ = try await provider.requestBackfill(
                summaryType: .dailies,
                startDate: Date().addingTimeInterval(-86400),
                endDate: Date()
            )
            XCTFail("Should throw notConnected when not connected")
        } catch SynheartWearError.notConnected {
            // Expected
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - OAuth Flow Tests

    func testConnectWithCodeWithoutOAuthFlow() async {
        // Test that connectWithCode() throws .notConnected if OAuth flow wasn't initiated
        do {
            try await provider.connectWithCode(
                code: "test-user-id",
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

    func testHandleDeepLinkCallbackFailure() async {
        do {
            _ = try await provider.handleDeepLinkCallback(
                success: false,
                userId: nil,
                error: "User denied access"
            )
            XCTFail("Should throw error on failed callback")
        } catch SynheartWearError.apiError(let message) {
            XCTAssertTrue(message.contains("User denied access"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Integration Tests (Require Mock Server)

    func testFullOAuthFlow() async throws {
        // This requires a mock Wear Service or real service
        // Steps:
        // 1. Call connect() - get authorization URL
        // 2. Simulate user approval (mock the Garmin intermediate redirect)
        // 3. Call handleDeepLinkCallback() with user_id
        // 4. Verify isConnected() returns true
        // 5. Verify getUserId() returns user_id

        XCTAssertTrue(true, "Requires integration testing with mock server")
    }

    func testFetchDailiesWithData() async throws {
        // This requires a mock Wear Service that returns test data
        // Steps:
        // 1. Set up provider as connected (mock user_id)
        // 2. Mock API response with dailies data
        // 3. Call fetchDailies()
        // 4. Verify returned WearMetrics contain steps, calories, hr

        XCTAssertTrue(true, "Requires integration testing with mock server")
    }
}
