import Foundation

/// Local cache for biometric data with optional encryption
class LocalCache {
    private let enableEncryption: Bool
    private let cacheDirectory: URL

    init(enableEncryption: Bool) {
        self.enableEncryption = enableEncryption

        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cachesDirectory.appendingPathComponent("synheart_wear", isDirectory: true)

        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Store a biometric session
    func storeSession(_ metrics: WearMetrics) async throws {
        let filename = "session_\(metrics.timestamp.timeIntervalSince1970).json"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metrics)

        // In production, encrypt the data here if enableEncryption is true
        try data.write(to: fileURL)
    }

    /// Get cached sessions within time range
    func getSessions(startDate: Date, endDate: Date, limit: Int) async throws -> [WearMetrics] {
        let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var sessions: [WearMetrics] = []

        for file in files.prefix(limit) {
            if let data = try? Data(contentsOf: file),
               let metrics = try? decoder.decode(WearMetrics.self, from: data) {
                if metrics.timestamp >= startDate && metrics.timestamp <= endDate {
                    sessions.append(metrics)
                }
            }
        }

        return sessions.sorted { $0.timestamp > $1.timestamp }
    }

    /// Get cache statistics
    func getStats() async throws -> [String: Any] {
        let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])

        let totalSize = files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + size
        }

        let timestamps = files.compactMap { url -> Date? in
            return (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        }

        return [
            "total_sessions": files.count,
            "total_size_bytes": totalSize,
            "oldest_session": timestamps.min() ?? Date(),
            "newest_session": timestamps.max() ?? Date()
        ]
    }

    /// Clear old cached data
    func clearOldData(maxAge: TimeInterval) async throws {
        let cutoffDate = Date().addingTimeInterval(-maxAge)
        let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey])

        for file in files {
            if let creationDate = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
               creationDate < cutoffDate {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Purge all cached data
    func purgeAll() async throws {
        let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
