import XCTest
@testable import SynheartWear

final class RealtimeReadGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testFirstReadIsAllowed() {
        XCTAssertTrue(RealtimeReadGate(minInterval: 60).tryAcquire(now: t0))
    }

    func testReadsInsideTheIntervalAreSkipped() {
        let gate = RealtimeReadGate(minInterval: 60)
        XCTAssertTrue(gate.tryAcquire(now: t0))
        XCTAssertFalse(gate.tryAcquire(now: t0.addingTimeInterval(3)))
        XCTAssertFalse(gate.tryAcquire(now: t0.addingTimeInterval(59.9)))
    }

    func testAReadAtTheIntervalIsAllowedAgain() {
        let gate = RealtimeReadGate(minInterval: 60)
        XCTAssertTrue(gate.tryAcquire(now: t0))
        XCTAssertTrue(gate.tryAcquire(now: t0.addingTimeInterval(60)))
    }

    func testAThreeSecondStreamReadsOncePerInterval() {
        let gate = RealtimeReadGate(minInterval: 60)
        let reads = (0..<100).filter { gate.tryAcquire(now: t0.addingTimeInterval(Double($0) * 3)) }.count
        XCTAssertEqual(reads, 5) // 300 s of ticks, one read per 60 s
    }
}
