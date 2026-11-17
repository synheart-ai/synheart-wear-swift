import XCTest
@testable import SynheartWear

final class OvernightSummarizerTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private var night: SleepWindow { SleepWindow(start: at("2026-03-01T22:00:00Z"), end: at("2026-03-02T06:00:00Z")) }
    private var wakeDay: Date { at("2026-03-02T00:00:00Z") }

    func testRestingHrComesFromTheSampleNotTheSleepHeartRate() {
        let out = summarizeOvernight(
            windows: [night],
            heartRate: [(at("2026-03-02T01:00:00Z"), 50), (at("2026-03-02T02:00:00Z"), 54)],
            hrvSdnn: [(at("2026-03-02T01:30:00Z"), 48)],
            restingHeartRate: [(at("2026-03-02T07:00:00Z"), 61)],
            timeZone: utc
        )
        let s = out[wakeDay]!
        XCTAssertEqual(s.overnightHrBpm, 52)
        XCTAssertEqual(s.restingHrBpm, 61)
        XCTAssertEqual(s.hrvSdnnMs, 48)
        XCTAssertNil(s.hrvRmssdMs)
    }

    func testNoRestingSampleMeansNoRestingHr() {
        let out = summarizeOvernight(
            windows: [night],
            heartRate: [(at("2026-03-02T01:00:00Z"), 50)],
            hrvSdnn: [],
            restingHeartRate: [],
            timeZone: utc
        )
        XCTAssertEqual(out[wakeDay]?.overnightHrBpm, 50)
        XCTAssertNil(out[wakeDay]?.restingHrBpm)
    }

    func testSamplesOutsideTheWindowAreIgnored() {
        let out = summarizeOvernight(
            windows: [night],
            heartRate: [
                (at("2026-03-01T21:59:59Z"), 90),
                (at("2026-03-02T03:00:00Z"), 50),
                (at("2026-03-02T06:00:00Z"), 95), // the end is exclusive
            ],
            hrvSdnn: [],
            restingHeartRate: [],
            timeZone: utc
        )
        XCTAssertEqual(out[wakeDay]?.overnightHrBpm, 50)
    }

    func testSeveralRestingSamplesGiveTheMedianAndADayWithoutSleepIsKept() {
        let out = summarizeOvernight(
            windows: [],
            heartRate: [],
            hrvSdnn: [],
            restingHeartRate: [
                (at("2026-03-02T05:00:00Z"), 58),
                (at("2026-03-02T09:00:00Z"), 90),
                (at("2026-03-02T13:00:00Z"), 60),
                (at("2026-03-02T17:00:00Z"), 0), // not a reading
            ],
            timeZone: utc
        )
        XCTAssertEqual(out[wakeDay]?.restingHrBpm, 60)
        XCTAssertNil(out[wakeDay]?.overnightHrBpm)
    }

    func testSamplesAreFiledUnderTheLocalDay() {
        let addis = TimeZone(identifier: "Africa/Addis_Ababa")! // UTC+3
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = addis
        let out = summarizeOvernight(
            windows: [], heartRate: [], hrvSdnn: [],
            restingHeartRate: [(at("2026-03-02T22:30:00Z"), 57)],
            timeZone: addis
        )
        XCTAssertEqual(Array(out.keys), [cal.startOfDay(for: at("2026-03-03T01:30:00Z"))])
    }

    func testNothingToReadGivesAnEmptyMap() {
        XCTAssertTrue(summarizeOvernight(windows: [], heartRate: [], hrvSdnn: [], restingHeartRate: [], timeZone: utc).isEmpty)
    }

    func testExistingInitializerLeavesOvernightHrNil() {
        XCTAssertNil(OvernightPhysiologySummary(hrvRmssdMs: nil, restingHrBpm: 58).overnightHrBpm)
    }
}
