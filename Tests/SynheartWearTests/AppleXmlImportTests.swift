// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import SynheartWear

final class AppleXmlImportTests: XCTestCase {

    // MARK: - Metric mapping

    func testMetricFromKnownIdentifier() {
        XCTAssertEqual(
            AppleHealthMetric.fromAppleIdentifier("HKQuantityTypeIdentifierHeartRate"),
            .heartRate
        )
        XCTAssertEqual(
            AppleHealthMetric.fromAppleIdentifier(
                "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"),
            .hrvSdnn
        )
        XCTAssertEqual(
            AppleHealthMetric.fromAppleIdentifier(
                "HKCategoryTypeIdentifierSleepAnalysis"),
            .sleepStage
        )
    }

    func testMetricFromUnknownIdentifier() {
        XCTAssertNil(AppleHealthMetric.fromAppleIdentifier("HKWorkoutTypeIdentifier"))
        XCTAssertNil(AppleHealthMetric.fromAppleIdentifier("garbage"))
    }

    func testMetricRawValuesArePinned() {
        // These strings are part of the SHA-256 idempotency key.
        // Renaming requires a backfill migration.
        XCTAssertEqual(AppleHealthMetric.heartRate.rawValue, "heart_rate")
        XCTAssertEqual(AppleHealthMetric.hrvSdnn.rawValue, "hrv_sdnn")
        XCTAssertEqual(AppleHealthMetric.sleepStage.rawValue, "sleep_stage")
    }

    // MARK: - Sleep stage mapping

    func testSleepStageMapping() {
        XCTAssertEqual(
            SleepStage.fromAppleValue("HKCategoryValueSleepAnalysisInBed"),
            .inBed
        )
        XCTAssertEqual(
            SleepStage.fromAppleValue("HKCategoryValueSleepAnalysisAsleepREM"),
            .rem
        )
        XCTAssertEqual(
            SleepStage.fromAppleValue("HKCategoryValueSleepAnalysisAsleep"),
            .asleep
        )
        XCTAssertNil(SleepStage.fromAppleValue("HKCategoryValueFutureUnknown"))
    }

    // MARK: - Parser

    func testParserEmitsHeartRateRecord() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="en_US">
            <Record type="HKQuantityTypeIdentifierHeartRate"
                    sourceName="Apple Watch"
                    unit="count/min"
                    startDate="2026-04-29 22:14:33 -0700"
                    endDate="2026-04-29 22:14:33 -0700"
                    value="58"/>
        </HealthData>
        """

        let url = try writeTempXml(xml)
        defer { try? FileManager.default.removeItem(at: url) }

        var samples: [AppleHealthSample] = []
        let parser = AppleHealthXmlParser(onSample: { samples.append($0) })
        try parser.parse(xmlURL: url)

        XCTAssertEqual(parser.recordsSeen, 1)
        XCTAssertEqual(parser.samplesEmitted, 1)
        XCTAssertEqual(parser.samplesSkipped, 0)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].metric, .heartRate)
        XCTAssertEqual(samples[0].source, "Apple Watch")
        XCTAssertEqual(samples[0].value, .quantity(58.0))
    }

    func testParserSkipsUnknownTypeSilently() throws {
        let xml = """
        <HealthData>
            <Record type="HKWorkoutTypeIdentifier"
                    startDate="2026-04-29 22:14:33 -0700"
                    endDate="2026-04-29 22:14:33 -0700"
                    value="42"/>
        </HealthData>
        """

        let url = try writeTempXml(xml)
        defer { try? FileManager.default.removeItem(at: url) }

        var samples: [AppleHealthSample] = []
        var unknownCount = 0
        let parser = AppleHealthXmlParser(
            onSample: { samples.append($0) },
            onUnknown: { _, _ in unknownCount += 1 }
        )
        try parser.parse(xmlURL: url)

        XCTAssertTrue(samples.isEmpty)
        XCTAssertEqual(parser.samplesSkipped, 1)
        XCTAssertEqual(unknownCount, 0,
                       "unmapped HK identifiers should not trigger onUnknown")
    }

    // MARK: - Idempotency key (cross-platform pinned)

    func testIdempotencyKeyDeterministic() {
        let sample = AppleHealthSample(
            metric: .heartRate,
            source: "Apple Watch",
            startMs: 1714435000000,
            endMs: 1714435000000,
            value: .quantity(58.0)
        )

        let k1 = IdempotencyKey.key(for: sample)
        let k2 = IdempotencyKey.key(for: sample)
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1.count, 32, "SHA-256 must be 32 bytes")
    }

    func testIdempotencyKeyDifferentValueDifferentKey() {
        let a = AppleHealthSample(
            metric: .heartRate, source: "Apple Watch",
            startMs: 1714435000000, endMs: 1714435000000,
            value: .quantity(58.0))
        let b = AppleHealthSample(
            metric: .heartRate, source: "Apple Watch",
            startMs: 1714435000000, endMs: 1714435000000,
            value: .quantity(59.0))
        XCTAssertNotEqual(IdempotencyKey.key(for: a), IdempotencyKey.key(for: b))
    }

    /// **MUST stay byte-for-byte equal to**
    /// `synheart-wear-flutter/test/apple_xml_test.dart::canonical key for a fixed sample is pinned cross-platform`.
    ///
    /// The same export.zip imported on iOS vs Android MUST produce
    /// the same idempotency key, otherwise the runtime will see
    /// duplicates.
    func testIdempotencyKeyPinnedCrossPlatform() {
        let sample = AppleHealthSample(
            metric: .heartRate,
            source: "Apple Watch",
            startMs: 1714435000000,
            endMs: 1714435000000,
            value: .quantity(58.0)
        )
        // Canonical input string:
        //   "heart_rate|Apple Watch|1714435000000|1714435000000|58.000000"
        let expected =
            "c041fb8df9fd751704ade89b8f07368393182bd97e2cbcbeb05fc37eb48e88d9"
        XCTAssertEqual(IdempotencyKey.hexKey(for: sample), expected)
    }

    // MARK: - Helpers

    private func writeTempXml(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple_xml_test_\(UUID().uuidString).xml")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Orchestrator (AppleHealthXmlImport + RecordingIngestSink)

    func testOrchestratorOpensInsertsAndFinalizes() throws {
        let xml = """
        <HealthData>
            <Record type="HKQuantityTypeIdentifierHeartRate"
                    sourceName="Apple Watch"
                    startDate="2026-04-29 22:14:33 -0700"
                    endDate="2026-04-29 22:14:33 -0700"
                    value="58"/>
            <Record type="HKQuantityTypeIdentifierStepCount"
                    sourceName="iPhone"
                    startDate="2026-04-29 22:00:00 -0700"
                    endDate="2026-04-29 22:30:00 -0700"
                    value="143"/>
        </HealthData>
        """
        let url = try writeTempXml(xml)
        defer { try? FileManager.default.removeItem(at: url) }

        let sink = RecordingIngestSink()
        let importer = AppleHealthXmlImport(xmlURL: url, sink: sink, importId: "test-orch-001")
        let result = try importer.parse()

        XCTAssertEqual(sink.openedImportId, "test-orch-001")
        XCTAssertTrue(sink.finalized)
        XCTAssertEqual(result.importId, "test-orch-001")
        XCTAssertEqual(result.totalSamples, 2)
        XCTAssertEqual(result.inserted, 2)
        XCTAssertEqual(result.skippedAsDuplicate, 0)
    }

    func testOrchestratorReportsProgress() throws {
        let xml = """
        <HealthData>
            <Record type="HKQuantityTypeIdentifierHeartRate"
                    startDate="2026-04-29 22:14:33 -0700"
                    endDate="2026-04-29 22:14:33 -0700"
                    value="58"/>
        </HealthData>
        """
        let url = try writeTempXml(xml)
        defer { try? FileManager.default.removeItem(at: url) }

        let sink = RecordingIngestSink()
        let importer = AppleHealthXmlImport(xmlURL: url, sink: sink, importId: "test-progress")
        var lastProgress: Double = -1
        _ = try importer.parse { p in lastProgress = p }
        XCTAssertEqual(lastProgress, 1.0, "final progress should be 1.0")
    }

    func testOrchestratorAutogeneratesImportIdWhenNil() throws {
        let xml = "<HealthData></HealthData>"
        let url = try writeTempXml(xml)
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = RecordingIngestSink()
        let importer = AppleHealthXmlImport(xmlURL: url, sink: sink)
        XCTAssertFalse(importer.importId.isEmpty)
        // UUIDs are 36 chars
        XCTAssertEqual(importer.importId.count, 36)
    }
}
