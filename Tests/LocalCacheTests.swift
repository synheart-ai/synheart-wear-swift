import CryptoKit
import XCTest
@testable import SynheartWear

private struct FixedKey: CacheKeyProviding {
    let value: SymmetricKey
    func key() throws -> SymmetricKey { value }
}

private struct FailingKey: CacheKeyProviding {
    func key() throws -> SymmetricKey { throw SynheartWearError.cacheError("no key") }
}

final class LocalCacheTests: XCTestCase {
    private var dir: URL!
    private let key = FixedKey(value: SymmetricKey(size: .bits256))

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wear-cache-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func metrics(_ ms: Int64, hr: Double = 60) -> WearMetrics {
        WearMetrics(
            timestamp: Date(timeIntervalSince1970: Double(ms) / 1000),
            deviceId: "device-a",
            source: "apple_healthkit",
            metrics: ["hr": hr, "hrv_rmssd": 42.5],
            meta: ["note": "x"],
            rrIntervals: [800, 810]
        )
    }

    private func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    }

    private let all = (Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 100))

    func testEncryptedRoundTrip() async throws {
        let cache = LocalCache(enableEncryption: true, directory: dir, keyProvider: key)
        try await cache.storeSession(metrics(1_000))

        let sessions = try await cache.getSessions(startDate: all.0, endDate: all.1, limit: 10)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].timestamp, metrics(1_000).timestamp)
        XCTAssertEqual(sessions[0].metrics, ["hr": 60, "hrv_rmssd": 42.5])
        XCTAssertEqual(sessions[0].rrIntervals, [800, 810])
    }

    func testEncryptedRecordsDoNotContainPlaintext() async throws {
        let cache = LocalCache(enableEncryption: true, directory: dir, keyProvider: key)
        try await cache.storeSession(metrics(1_000))

        let stored = try files()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].pathExtension, "enc")
        let text = String(decoding: try Data(contentsOf: stored[0]), as: UTF8.self)
        XCTAssertFalse(text.contains("apple_healthkit"))
        XCTAssertFalse(text.contains("device-a"))
        XCTAssertFalse(text.contains("hrv_rmssd"))
    }

    func testTamperedRecordIsDropped() async throws {
        let cache = LocalCache(enableEncryption: true, directory: dir, keyProvider: key)
        try await cache.storeSession(metrics(1_000))
        let url = try files()[0]
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: url)

        let sessions = try await cache.getSessions(startDate: all.0, endDate: all.1, limit: 10)
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecordFromAnotherKeyIsDropped() async throws {
        try await LocalCache(enableEncryption: true, directory: dir, keyProvider: key).storeSession(metrics(1_000))
        let other = LocalCache(enableEncryption: true, directory: dir, keyProvider: FixedKey(value: SymmetricKey(size: .bits256)))

        let sessions = try await other.getSessions(startDate: all.0, endDate: all.1, limit: 10)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testNothingIsWrittenWhenTheKeyIsUnavailable() async throws {
        let cache = LocalCache(enableEncryption: true, directory: dir, keyProvider: FailingKey())
        try await cache.storeSession(metrics(1_000))

        XCTAssertTrue(try files().isEmpty)
    }

    func testPlaintextLeftoversAreDeletedWhenEncryptionIsOn() async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = dir.appendingPathComponent("session_1.5.json")
        try Data("{}".utf8).write(to: legacy)

        let cache = LocalCache(enableEncryption: true, directory: dir, keyProvider: key)
        try await cache.storeSession(metrics(1_000))

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testUnencryptedModeWritesReadableJson() async throws {
        let cache = LocalCache(enableEncryption: false, directory: dir, keyProvider: FailingKey())
        try await cache.storeSession(metrics(1_000))

        let url = try files()[0]
        XCTAssertEqual(url.pathExtension, "json")
        XCTAssertTrue(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("apple_healthkit"))
        let sessions = try await cache.getSessions(startDate: all.0, endDate: all.1, limit: 10)
        XCTAssertEqual(sessions.count, 1)
    }

    func testSessionsAreFilteredSortedNewestFirstAndLimited() async throws {
        let cache = LocalCache(enableEncryption: true, directory: dir, keyProvider: key)
        for ms: Int64 in [1_000, 5_000, 3_000, 9_000, 7_000] {
            try await cache.storeSession(metrics(ms))
        }

        let sessions = try await cache.getSessions(
            startDate: Date(timeIntervalSince1970: 2),
            endDate: Date(timeIntervalSince1970: 8),
            limit: 2
        )
        XCTAssertEqual(sessions.map { $0.timestamp.timeIntervalSince1970 }, [7, 5])
    }

    func testPurgeRemovesEverything() async throws {
        let cache = LocalCache(enableEncryption: true, directory: dir, keyProvider: key)
        try await cache.storeSession(metrics(1_000))
        try await cache.purgeAll()

        XCTAssertTrue(try files().isEmpty)
    }
}
