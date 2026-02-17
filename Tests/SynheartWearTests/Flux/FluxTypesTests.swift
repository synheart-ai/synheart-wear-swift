import XCTest
@testable import SynheartWear

final class FluxTypesTests: XCTestCase {

    func testVendorEnumHasExpectedValues() {
        XCTAssertEqual(Vendor.whoop.rawValue, "whoop")
        XCTAssertEqual(Vendor.garmin.rawValue, "garmin")
    }

    func testBaselinesJsonRoundtrip() throws {
        let baselines = Baselines(
            hrvBaselineMs: 42.5,
            rhrBaselineBpm: 55,
            sleepBaselineMinutes: 420,
            sleepEfficiencyBaseline: 0.9,
            baselineDays: 14
        )

        let json = try baselines.toJson()
        let decoded = try Baselines.fromJson(json)

        XCTAssertEqual(decoded.hrvBaselineMs, 42.5)
        XCTAssertEqual(decoded.rhrBaselineBpm, 55)
        XCTAssertEqual(decoded.sleepBaselineMinutes, 420)
        XCTAssertEqual(decoded.sleepEfficiencyBaseline, 0.9)
        XCTAssertEqual(decoded.baselineDays, 14)
    }

    func testHsiPayloadToJsonIncludesRequiredKeys() throws {
        let payload = HsiPayload(
            hsiVersion: "1.0",
            observedAtUtc: "2026-01-01T00:00:00+00:00",
            computedAtUtc: "2026-01-01T00:00:01+00:00",
            producer: HsiProducer(
                name: "synheart_flux",
                version: "0.1.0",
                instanceId: "test-instance"
            ),
            windowIds: ["w_test"],
            windows: [
                "w_test": HsiWindow(
                    start: "2026-01-01T00:00:00+00:00",
                    end: "2026-01-01T23:59:59+00:00",
                    label: "test-window"
                )
            ],
            sourceIds: ["s_test"],
            sources: [
                "s_test": HsiSource(
                    type: .app,
                    quality: 0.95,
                    degraded: false
                )
            ],
            axes: HsiAxes(
                behavior: HsiAxesDomain(
                    readings: [
                        HsiAxisReading(
                            axis: "test_metric",
                            score: 0.5,
                            confidence: 0.95,
                            windowId: "w_test",
                            direction: .higherIsMore,
                            evidenceSourceIds: ["s_test"]
                        )
                    ]
                )
            ),
            privacy: HsiPrivacy(
                containsPii: false,
                rawBiosignalsAllowed: false,
                derivedMetricsAllowed: true
            )
        )

        let json = try payload.toJson()

        // Parse as dictionary to check keys
        let data = json.data(using: .utf8)!
        let dict = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        // HSI 1.0 required fields
        XCTAssertEqual(dict["hsi_version"] as? String, "1.0")
        XCTAssertNotNil(dict["observed_at_utc"])
        XCTAssertNotNil(dict["computed_at_utc"])
        XCTAssertNotNil(dict["producer"])
        XCTAssertNotNil(dict["window_ids"])
        XCTAssertNotNil(dict["windows"])
        XCTAssertNotNil(dict["source_ids"])
        XCTAssertNotNil(dict["sources"])
        XCTAssertNotNil(dict["axes"])
        XCTAssertNotNil(dict["privacy"])
    }

    func testHsiPayloadFromJsonRoundtripsCorrectly() throws {
        let original = HsiPayload(
            hsiVersion: "1.0",
            observedAtUtc: "2026-01-01T00:00:00+00:00",
            computedAtUtc: "2026-01-01T00:00:01+00:00",
            producer: HsiProducer(
                name: "test",
                version: "1.0.0",
                instanceId: "test-id"
            ),
            windowIds: ["w_1"],
            windows: [
                "w_1": HsiWindow(
                    start: "2026-01-01T00:00:00+00:00",
                    end: "2026-01-01T12:00:00+00:00"
                )
            ],
            sourceIds: ["s_1"],
            sources: [
                "s_1": HsiSource(
                    type: .sensor,
                    quality: 0.8,
                    degraded: false
                )
            ],
            axes: HsiAxes(),
            privacy: HsiPrivacy()
        )

        let json = try original.toJson()
        let decoded = try HsiPayload.fromJson(json)

        XCTAssertEqual(decoded.hsiVersion, "1.0")
        XCTAssertEqual(decoded.windowIds, ["w_1"])
        XCTAssertEqual(decoded.sourceIds, ["s_1"])
        XCTAssertEqual(decoded.producer.name, "test")
    }

    func testHsiDirectionSerializesToSnakeCase() throws {
        let reading = HsiAxisReading(
            axis: "test",
            score: 0.5,
            confidence: 0.9,
            windowId: "w_1",
            direction: .higherIsMore
        )

        let axes = HsiAxesDomain(readings: [reading])
        let payload = HsiPayload(
            hsiVersion: "1.0",
            observedAtUtc: "2026-01-01T00:00:00+00:00",
            computedAtUtc: "2026-01-01T00:00:01+00:00",
            producer: HsiProducer(name: "test", version: "1.0", instanceId: "id"),
            windowIds: ["w_1"],
            windows: ["w_1": HsiWindow(start: "2026-01-01T00:00:00+00:00", end: "2026-01-01T12:00:00+00:00")],
            sourceIds: [],
            sources: [:],
            axes: HsiAxes(behavior: axes),
            privacy: HsiPrivacy()
        )

        let json = try payload.toJson()
        XCTAssertTrue(json.contains("higher_is_more"))
    }

    func testHsiSourceTypeSerializesToSnakeCase() throws {
        let source = HsiSource(
            type: .selfReport,
            quality: 0.7,
            degraded: false
        )

        let payload = HsiPayload(
            hsiVersion: "1.0",
            observedAtUtc: "2026-01-01T00:00:00+00:00",
            computedAtUtc: "2026-01-01T00:00:01+00:00",
            producer: HsiProducer(name: "test", version: "1.0", instanceId: "id"),
            windowIds: [],
            windows: [:],
            sourceIds: ["s_1"],
            sources: ["s_1": source],
            axes: HsiAxes(),
            privacy: HsiPrivacy()
        )

        let json = try payload.toJson()
        XCTAssertTrue(json.contains("self_report"))
    }

    func testFluxErrorCodes() {
        XCTAssertEqual(FluxError.disabled.code, "FLUX_DISABLED")
        XCTAssertEqual(FluxError.notAvailable(nil).code, "FLUX_NOT_AVAILABLE")
        XCTAssertEqual(FluxError.processingFailed(nil).code, "FLUX_PROCESSING_FAILED")
        XCTAssertEqual(FluxError.invalidJson("test").code, "FLUX_INVALID_JSON")
    }
}
