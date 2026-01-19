import XCTest
@testable import SynheartWear

final class FluxProcessorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset FFI state before each test
        FluxFfi.shared.resetForTesting()
    }

    override func tearDown() {
        // Clean up after tests
        FluxFfi.shared.resetForTesting()
        super.tearDown()
    }

    func testFluxProcessorGracefullyHandlesUnavailableNativeLibrary() {
        // In unit tests, native library won't be available
        let processor = FluxProcessor()

        // Should not crash, just return unavailable
        XCTAssertFalse(processor.isAvailable)

        // Methods should return nil instead of throwing
        XCTAssertNil(processor.saveBaselines())
        XCTAssertNil(processor.processWhoop("{}", timezone: "UTC", deviceId: "device-123"))
        XCTAssertNil(processor.processGarmin("{}", timezone: "UTC", deviceId: "device-123"))
        XCTAssertNil(processor.currentBaselines)

        // loadBaselines should return false
        XCTAssertFalse(processor.loadBaselines("{}"))

        // close() should not crash
        processor.close()
    }

    func testFluxProcessorCreateWithCustomBaselineWindow() {
        let processor = FluxProcessor(baselineWindowDays: 7)

        // Should create successfully even without native library
        XCTAssertNotNil(processor)

        processor.close()
    }

    func testIsFluxAvailableReturnsFalseWhenNativeLibraryNotLoaded() {
        // In unit tests, native library won't be available
        XCTAssertFalse(isFluxAvailable)
    }

    func testFluxLoadErrorContainsMeaningfulMessageWhenLibraryNotAvailable() {
        // Force a load attempt
        _ = isFluxAvailable

        // Should have an error message
        let error = fluxLoadError
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("Failed to load") ?? false)
    }

    func testWhoopToHsiDailyReturnsNilWhenNativeLibraryNotAvailable() {
        let result = whoopToHsiDaily("{}", timezone: "America/New_York", deviceId: "device-123")
        XCTAssertNil(result)
    }

    func testGarminToHsiDailyReturnsNilWhenNativeLibraryNotAvailable() {
        let result = garminToHsiDaily("{}", timezone: "America/Los_Angeles", deviceId: "device-456")
        XCTAssertNil(result)
    }

    func testFluxProcessorMethodsReturnNilAfterClose() {
        let processor = FluxProcessor()

        // Close the processor
        processor.close()

        // Methods should return nil
        XCTAssertFalse(processor.isAvailable)
        XCTAssertNil(processor.saveBaselines())
        XCTAssertNil(processor.processWhoop("{}", timezone: "UTC", deviceId: "device-123"))
    }

    func testFluxProcessorCanBeClosedMultipleTimesSafely() {
        let processor = FluxProcessor()

        // Should not crash on multiple closes
        processor.close()
        processor.close()
        processor.close()
    }

    func testFluxFfiStaticMethodsAreSafeWhenLibraryUnavailable() {
        // These should not crash
        let available = FluxFfi.shared.isAvailable
        let error = FluxFfi.shared.loadError
        let lastError = FluxFfi.shared.getLastError()

        XCTAssertFalse(available)
        // Error message should be set after load attempt
        XCTAssertNotNil(error)
        // lastError is nil when no native error occurred
        XCTAssertNil(lastError)
    }

    func testStaticIsFluxAvailableProperty() {
        XCTAssertFalse(FluxProcessor.isFluxAvailable)
    }

    func testStaticFluxLoadErrorProperty() {
        // Force load attempt
        _ = FluxFfi.shared.isAvailable

        // Should have error info
        let error = FluxProcessor.fluxLoadError
        XCTAssertNotNil(error)
    }
}
