import XCTest
@testable import SynheartWear

final class OvernightPhysiologySummaryTests: XCTestCase {
    func testSdnnIsKeptApartFromRmssd() {
        let s = OvernightPhysiologySummary(hrvRmssdMs: nil, restingHrBpm: 58, hrvSdnnMs: 48)
        XCTAssertNil(s.hrvRmssdMs)
        XCTAssertEqual(s.hrvSdnnMs, 48)
        XCTAssertEqual(s.restingHrBpm, 58)
    }

    func testExistingInitializerLeavesSdnnNil() {
        let s = OvernightPhysiologySummary(hrvRmssdMs: 42, restingHrBpm: 60)
        XCTAssertEqual(s.hrvRmssdMs, 42)
        XCTAssertNil(s.hrvSdnnMs)
    }
}
