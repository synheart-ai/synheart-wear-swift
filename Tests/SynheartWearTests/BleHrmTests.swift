import XCTest
@testable import SynheartWear

final class BleHrmTests: XCTestCase {

    // MARK: - HeartRateSample Tests

    func testHeartRateSampleConstruction() {
        let sample = HeartRateSample(
            tsMs: 1700000000000,
            bpm: 72,
            source: "ble_hrm",
            deviceId: "ABC-123",
            deviceName: "Polar H10",
            sessionId: "session-1",
            rrIntervalsMs: [820.0, 835.0]
        )

        XCTAssertEqual(sample.tsMs, 1700000000000)
        XCTAssertEqual(sample.bpm, 72)
        XCTAssertEqual(sample.source, "ble_hrm")
        XCTAssertEqual(sample.deviceId, "ABC-123")
        XCTAssertEqual(sample.deviceName, "Polar H10")
        XCTAssertEqual(sample.sessionId, "session-1")
        XCTAssertEqual(sample.rrIntervalsMs, [820.0, 835.0])
    }

    func testHeartRateSampleDefaultSource() {
        let sample = HeartRateSample(bpm: 80, deviceId: "test")
        XCTAssertEqual(sample.source, "ble_hrm")
    }

    func testHeartRateSampleToWearMetrics() {
        let sample = HeartRateSample(
            tsMs: 1700000000000,
            bpm: 72,
            deviceId: "ABC-123",
            deviceName: "Polar H10",
            sessionId: "session-1",
            rrIntervalsMs: [820.0, 835.0]
        )

        let metrics = sample.toWearMetrics()

        XCTAssertEqual(metrics.deviceId, "ABC-123")
        XCTAssertEqual(metrics.source, "ble_hrm")
        XCTAssertEqual(metrics.getMetric(.hr), 72.0)
        XCTAssertEqual(metrics.meta["device_name"], "Polar H10")
        XCTAssertEqual(metrics.meta["session_id"], "session-1")
        XCTAssertEqual(metrics.rrIntervals, [820.0, 835.0])
    }

    func testHeartRateSampleToWearMetricsNoOptionals() {
        let sample = HeartRateSample(bpm: 60, deviceId: "DEF-456")
        let metrics = sample.toWearMetrics()

        XCTAssertEqual(metrics.deviceId, "DEF-456")
        XCTAssertEqual(metrics.getMetric(.hr), 60.0)
        XCTAssertNil(metrics.meta["device_name"])
        XCTAssertNil(metrics.meta["session_id"])
        XCTAssertNil(metrics.rrIntervals)
    }

    // MARK: - BleHrmDevice Tests

    func testBleHrmDeviceConstruction() {
        let device = BleHrmDevice(deviceId: "UUID-123", name: "Wahoo TICKR", rssi: -65)

        XCTAssertEqual(device.deviceId, "UUID-123")
        XCTAssertEqual(device.name, "Wahoo TICKR")
        XCTAssertEqual(device.rssi, -65)
    }

    func testBleHrmDeviceNilName() {
        let device = BleHrmDevice(deviceId: "UUID-456", name: nil, rssi: -80)
        XCTAssertNil(device.name)
    }

    // MARK: - BleHrmErrorCode Tests

    func testBleHrmErrorCodeRawValues() {
        XCTAssertEqual(BleHrmErrorCode.permissionDenied.rawValue, "PERMISSION_DENIED")
        XCTAssertEqual(BleHrmErrorCode.bluetoothOff.rawValue, "BLUETOOTH_OFF")
        XCTAssertEqual(BleHrmErrorCode.deviceNotFound.rawValue, "DEVICE_NOT_FOUND")
        XCTAssertEqual(BleHrmErrorCode.subscribeFailed.rawValue, "SUBSCRIBE_FAILED")
        XCTAssertEqual(BleHrmErrorCode.disconnected.rawValue, "DISCONNECTED")
    }

    // MARK: - HeartRateParser Tests

    func testParseUint8HeartRate() {
        // Flags: 0x00 (uint8, no RR)
        // BPM: 72
        let data = Data([0x00, 72])
        let result = HeartRateParser.parse(data)

        XCTAssertEqual(result.bpm, 72)
        XCTAssertNil(result.rrIntervalsMs)
    }

    func testParseUint16HeartRate() {
        // Flags: 0x01 (uint16, no RR)
        // BPM: 260 (little-endian: 0x04, 0x01)
        let data = Data([0x01, 0x04, 0x01])
        let result = HeartRateParser.parse(data)

        XCTAssertEqual(result.bpm, 260)
        XCTAssertNil(result.rrIntervalsMs)
    }

    func testParseUint8WithRRIntervals() {
        // Flags: 0x10 (uint8, RR present)
        // BPM: 75
        // RR: 0x0340 = 832 (in 1/1024s) → ~812.5 ms
        let data = Data([0x10, 75, 0x40, 0x03])
        let result = HeartRateParser.parse(data)

        XCTAssertEqual(result.bpm, 75)
        XCTAssertNotNil(result.rrIntervalsMs)
        XCTAssertEqual(result.rrIntervalsMs!.count, 1)

        let expectedMs = Double(0x0340) / 1024.0 * 1000.0
        XCTAssertEqual(result.rrIntervalsMs![0], expectedMs, accuracy: 0.01)
    }

    func testParseUint16WithRRIntervals() {
        // Flags: 0x11 (uint16, RR present)
        // BPM: 300 (0x2C, 0x01)
        // RR: 0x0380 = 896 (in 1/1024s)
        let data = Data([0x11, 0x2C, 0x01, 0x80, 0x03])
        let result = HeartRateParser.parse(data)

        XCTAssertEqual(result.bpm, 300)
        XCTAssertNotNil(result.rrIntervalsMs)
        XCTAssertEqual(result.rrIntervalsMs!.count, 1)
    }

    func testParseMultipleRRIntervals() {
        // Flags: 0x10 (uint8, RR present)
        // BPM: 80
        // RR1: 0x0340 = 832, RR2: 0x0360 = 864
        let data = Data([0x10, 80, 0x40, 0x03, 0x60, 0x03])
        let result = HeartRateParser.parse(data)

        XCTAssertEqual(result.bpm, 80)
        XCTAssertNotNil(result.rrIntervalsMs)
        XCTAssertEqual(result.rrIntervalsMs!.count, 2)
    }

    func testParseEmptyData() {
        let data = Data()
        let result = HeartRateParser.parse(data)

        XCTAssertEqual(result.bpm, 0)
        XCTAssertNil(result.rrIntervalsMs)
    }

    func testParseSingleByte() {
        let data = Data([0x00])
        let result = HeartRateParser.parse(data)

        XCTAssertEqual(result.bpm, 0)
        XCTAssertNil(result.rrIntervalsMs)
    }

    func testParseUint16TooShort() {
        // Flags say uint16 but only 1 byte of HR data
        let data = Data([0x01, 72])
        let result = HeartRateParser.parse(data)

        XCTAssertEqual(result.bpm, 0)
    }

    func testParseWithEnergyExpended() {
        // Flags: 0x18 (uint8, energy expended present, RR present)
        // BPM: 70
        // Energy: 2 bytes (skipped)
        // RR: 0x0340
        let data = Data([0x18, 70, 0x00, 0x00, 0x40, 0x03])
        let result = HeartRateParser.parse(data)

        XCTAssertEqual(result.bpm, 70)
        XCTAssertNotNil(result.rrIntervalsMs)
        XCTAssertEqual(result.rrIntervalsMs!.count, 1)
    }

    // MARK: - DeviceAdapter Tests

    func testDeviceAdapterBleHrmExists() {
        let adapter = DeviceAdapter.bleHrm
        XCTAssertNotNil(adapter)
    }

    // MARK: - SynheartWearError BLE HRM Tests

    func testBleHrmErrorDescription() {
        let error = SynheartWearError.bleHrm(.bluetoothOff, "Bluetooth is powered off")
        XCTAssertTrue(error.errorDescription!.contains("BLUETOOTH_OFF"))
        XCTAssertTrue(error.errorDescription!.contains("Bluetooth is powered off"))
    }
}
