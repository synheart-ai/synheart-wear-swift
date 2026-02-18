import XCTest
@testable import SynheartWear

final class SynheartWearFluxTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FluxFfi.shared.resetForTesting()
    }

    override func tearDown() {
        FluxFfi.shared.resetForTesting()
        super.tearDown()
    }

    func testSynheartWearConfigDefaultHasFluxDisabled() {
        let config = SynheartWearConfig()
        XCTAssertFalse(config.enableFlux)
    }

    func testSynheartWearConfigCanEnableFlux() {
        let config = SynheartWearConfig(enableFlux: true)
        XCTAssertTrue(config.enableFlux)
    }

    func testSynheartWearConfigDefaultBaselineWindowIs14Days() {
        let config = SynheartWearConfig()
        XCTAssertEqual(config.fluxBaselineWindowDays, 14)
    }

    func testSynheartWearConfigCanSetCustomBaselineWindow() {
        let config = SynheartWearConfig(
            enableFlux: true,
            fluxBaselineWindowDays: 7
        )
        XCTAssertEqual(config.fluxBaselineWindowDays, 7)
    }

    func testFluxErrorCodesAreDefined() {
        // These are the error codes used by SynheartWear for Flux errors
        let disabledError = FluxError.disabled
        let notAvailableError = FluxError.notAvailable(nil)
        let processingError = FluxError.processingFailed(nil)
        let jsonError = FluxError.invalidJson("test")

        // Verify codes are non-empty
        XCTAssertFalse(disabledError.code.isEmpty)
        XCTAssertFalse(notAvailableError.code.isEmpty)
        XCTAssertFalse(processingError.code.isEmpty)
        XCTAssertFalse(jsonError.code.isEmpty)
    }

    func testFluxErrorDescriptions() {
        XCTAssertNotNil(FluxError.disabled.errorDescription)
        XCTAssertNotNil(FluxError.notAvailable(nil).errorDescription)
        XCTAssertNotNil(FluxError.notAvailable("test reason").errorDescription)
        XCTAssertNotNil(FluxError.processingFailed(nil).errorDescription)
        XCTAssertNotNil(FluxError.processingFailed("test reason").errorDescription)
        XCTAssertNotNil(FluxError.invalidJson("test").errorDescription)
    }

    func testVendorEnumCoversExpectedVendors() {
        // Ensure we have the expected vendors
        XCTAssertEqual(Vendor.whoop.rawValue, "whoop")
        XCTAssertEqual(Vendor.garmin.rawValue, "garmin")
    }

    func testFluxConfigCombinedWithOtherConfig() {
        let config = SynheartWearConfig(
            enabledAdapters: [.appleHealthKit, .whoop],
            enableLocalCaching: true,
            enableEncryption: false,
            streamInterval: 5.0,
            appId: "test-app",
            enableFlux: true,
            fluxBaselineWindowDays: 21
        )

        XCTAssertEqual(config.enabledAdapters.count, 2)
        XCTAssertTrue(config.enableLocalCaching)
        XCTAssertFalse(config.enableEncryption)
        XCTAssertEqual(config.streamInterval, 5.0)
        XCTAssertEqual(config.appId, "test-app")
        XCTAssertTrue(config.enableFlux)
        XCTAssertEqual(config.fluxBaselineWindowDays, 21)
    }
}
