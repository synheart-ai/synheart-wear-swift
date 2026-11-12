import Foundation
import CryptoKit
import Security

/// Supplies the key that seals cache records.
protocol CacheKeyProviding {
    func key() throws -> SymmetricKey
}

/// Keeps a 256-bit cache key in the Keychain, readable after first unlock and
/// never synced or migrated to another device.
struct KeychainCacheKey: CacheKeyProviding {
    private let service = "ai.synheart.wear.cache"
    private let account = "v1"

    func key() throws -> SymmetricKey {
        if let existing = try read() { return existing }
        let fresh = SymmetricKey(size: .bits256)
        try store(fresh)
        return fresh
    }

    private func read() throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else {
                throw SynheartWearError.cacheError("Cache key is malformed")
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw SynheartWearError.cacheError("Keychain read failed (\(status))")
        }
    }

    private func store(_ key: SymmetricKey) throws {
        var query = baseQuery
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SynheartWearError.cacheError("Keychain write failed (\(status))")
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Local cache for biometric data with optional encryption.
///
/// With encryption on, each session is sealed with AES-256-GCM under a key
/// held in the Keychain and written as `session_<ms>.enc`. If the key can't be
/// obtained, the session is not cached rather than written in the clear. With
/// encryption off, sessions are plain JSON (`session_<ms>.json`).
class LocalCache {
    private let enableEncryption: Bool
    private let cacheDirectory: URL
    private let keyProvider: CacheKeyProviding
    private let lock = NSLock()
    private var cachedKey: SymmetricKey?
    private var prepared = false

    private static let prefix = "session_"
    private static let encryptedExtension = "enc"
    private static let plainExtension = "json"
    private static let recordVersion: UInt8 = 1

    private var fileExtension: String {
        enableEncryption ? Self.encryptedExtension : Self.plainExtension
    }

    convenience init(enableEncryption: Bool) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.init(
            enableEncryption: enableEncryption,
            directory: caches.appendingPathComponent("synheart_wear", isDirectory: true),
            keyProvider: KeychainCacheKey()
        )
    }

    init(enableEncryption: Bool, directory: URL, keyProvider: CacheKeyProviding) {
        self.enableEncryption = enableEncryption
        self.cacheDirectory = directory
        self.keyProvider = keyProvider
    }

    /// Store a biometric session
    func storeSession(_ metrics: WearMetrics) async throws {
        try prepare()
        let json = try Self.encoder.encode(metrics)

        let payload: Data
        if enableEncryption {
            guard let key = try? self.key() else {
                // Never fall back to plaintext.
                return
            }
            let sealed = try AES.GCM.seal(json, using: key)
            guard let combined = sealed.combined else {
                throw SynheartWearError.cacheError("Failed to seal cache record")
            }
            payload = Data([Self.recordVersion]) + combined
        } else {
            payload = json
        }

        let ms = Int64((metrics.timestamp.timeIntervalSince1970 * 1000).rounded())
        let url = cacheDirectory.appendingPathComponent("\(Self.prefix)\(ms).\(fileExtension)")
        try payload.write(to: url, options: Self.writeOptions)
    }

    /// Get cached sessions within time range, newest first
    func getSessions(startDate: Date, endDate: Date, limit: Int) async throws -> [WearMetrics] {
        try prepare()
        guard limit > 0 else { return [] }
        let key: SymmetricKey?
        if enableEncryption {
            guard let k = try? self.key() else { return [] }
            key = k
        } else {
            key = nil
        }

        let startMs = Int64((startDate.timeIntervalSince1970 * 1000).rounded(.down))
        let endMs = Int64((endDate.timeIntervalSince1970 * 1000).rounded(.up))

        let candidates = try sessionFiles()
            .compactMap { url -> (Int64, URL)? in
                guard let ms = Self.timestamp(of: url) else { return nil }
                return (ms, url)
            }
            .filter { $0.0 >= startMs && $0.0 <= endMs }
            .sorted { $0.0 > $1.0 }

        var sessions: [WearMetrics] = []
        for (_, url) in candidates {
            if let metrics = read(url, key: key) {
                sessions.append(metrics)
                if sessions.count == limit { break }
            }
        }
        return sessions
    }

    /// Get cache statistics
    func getStats() async throws -> [String: Any] {
        try prepare()
        let files = try sessionFiles()

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
            "newest_session": timestamps.max() ?? Date(),
            "encryption_enabled": enableEncryption,
        ]
    }

    /// Clear old cached data
    func clearOldData(maxAge: TimeInterval) async throws {
        try prepare()
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
        try prepare()
        let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Private

    /// Creates the directory and, when encryption is on, deletes plaintext
    /// records left by earlier versions or by running with encryption off.
    private func prepare() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !prepared else { return }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        if enableEncryption {
            let files = (try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == Self.plainExtension {
                try? FileManager.default.removeItem(at: file)
            }
        }
        prepared = true
    }

    private func key() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let cachedKey { return cachedKey }
        let key = try keyProvider.key()
        cachedKey = key
        return key
    }

    private func sessionFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            .filter { $0.lastPathComponent.hasPrefix(Self.prefix) && $0.pathExtension == fileExtension }
    }

    private static func timestamp(of url: URL) -> Int64? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix(prefix) else { return nil }
        return Int64(name.dropFirst(prefix.count))
    }

    /// Reads one record; an unreadable or tampered record is dropped.
    private func read(_ url: URL, key: SymmetricKey?) -> WearMetrics? {
        do {
            let raw = try Data(contentsOf: url)
            let json: Data
            if let key {
                guard raw.count > 1, raw.first == Self.recordVersion else {
                    throw SynheartWearError.cacheError("Unknown record version")
                }
                let box = try AES.GCM.SealedBox(combined: raw.dropFirst())
                json = try AES.GCM.open(box, using: key)
            } else {
                json = raw
            }
            return try Self.decoder.decode(WearMetrics.self, from: json)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        return [.atomic]
        #endif
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
