import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Oura ring cloud provider.
///
/// OAuth is mediated by the Synheart Wear API: the client never sees Oura
/// access tokens. After authorize, the cloud delivers a `vendor_user_id`
/// to the app via a deep-link callback. Pass it to
/// `connectWithCode(code:state:redirectUri:)` (the `code` parameter carries
/// the `vendor_user_id`; `state` and `redirectUri` are unused).
public class OuraProvider: WearableProvider {
    public let vendor: DeviceAdapter = .oura

    private let appId: String
    private let baseUrl: URL
    private let redirectUri: String
    private let projectId: String?
    private var userId: String?
    private let api: WearServiceAPI
    private let keychainService = "ai.synheart.wear.oura"
    private static let vendorName = "oura"

    public init(
        appId: String,
        baseUrl: URL? = nil,
        redirectUri: String = "synheart://oauth/callback",
        projectId: String? = nil
    ) {
        self.appId = appId
        self.baseUrl = baseUrl ?? URL(string: "https://api.synheart.ai/wear")!
        self.redirectUri = redirectUri
        self.projectId = projectId
        self.api = WearServiceAPI(baseURL: self.baseUrl)
        self.userId = loadUserId()
    }

    public func isConnected() -> Bool { userId != nil }
    public func getUserId() -> String? { userId }

    public func connect() async throws {
        guard let uid = userId, !uid.isEmpty else {
            throw SynheartWearError.apiError("OuraProvider: setUserId(_:) is required before connect().")
        }
        do {
            let resp = try await api.initiateVendorOAuth(
                vendor: Self.vendorName,
                userId: uid,
                appId: appId,
                redirectUri: redirectUri,
                projectId: projectId
            )
            guard let url = URL(string: resp.authUrl) else {
                throw SynheartWearError.invalidResponse
            }
            #if os(iOS)
            await MainActor.run {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            }
            #elseif canImport(AppKit)
            NSWorkspace.shared.open(url)
            #else
            throw SynheartWearError.apiError("Cannot open URL on this platform")
            #endif
        } catch let error as NetworkError {
            throw convertNetworkError(error)
        } catch {
            throw SynheartWearError.apiError(error.localizedDescription)
        }
    }

    public func connectWithCode(code: String, state: String, redirectUri: String) async throws {
        guard !code.isEmpty else { throw SynheartWearError.authenticationFailed }
        userId = code
        saveUserId(code)
    }

    public func setUserId(_ id: String) { userId = id }

    public func disconnect() async throws {
        guard let uid = userId else { return }
        userId = nil
        clearUserId()
        do {
            _ = try await api.disconnectVendor(vendor: Self.vendorName, userId: uid, appId: appId)
        } catch {}
    }

    // MARK: - Data

    public func fetchReadiness(start: Date? = nil, end: Date? = nil, limit: Int? = 50) async throws -> [WearMetrics] {
        try await fetchData(dataType: "readiness", start: start, end: end, limit: limit)
    }

    public func fetchSleep(start: Date? = nil, end: Date? = nil, limit: Int? = 50) async throws -> [WearMetrics] {
        try await fetchData(dataType: "sleep", start: start, end: end, limit: limit)
    }

    public func fetchHrv(start: Date? = nil, end: Date? = nil, limit: Int? = 200) async throws -> [WearMetrics] {
        try await fetchData(dataType: "hrv", start: start, end: end, limit: limit)
    }

    public func fetchActivity(start: Date? = nil, end: Date? = nil, limit: Int? = 50) async throws -> [WearMetrics] {
        try await fetchData(dataType: "activity", start: start, end: end, limit: limit)
    }

    private func fetchData(dataType: String, start: Date?, end: Date?, limit: Int?) async throws -> [WearMetrics] {
        guard let uid = userId else { throw SynheartWearError.notConnected }
        do {
            let resp = try await api.fetchVendorData(
                vendor: Self.vendorName,
                userId: uid,
                dataType: dataType,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                projectId: projectId
            )
            return resp.records.compactMap { recordToMetrics($0, dataType: dataType) }
        } catch let error as NetworkError {
            throw convertNetworkError(error)
        }
    }

    private func recordToMetrics(_ record: DataRecord, dataType: String) -> WearMetrics? {
        let data = record.fields
        let ts = extractTimestamp(from: data) ?? Date()

        var metrics: [String: Double] = [:]
        func putNum(_ key: String, _ field: String) {
            if let v = data[field]?.value as? Double { metrics[key] = v }
            else if let v = data[field]?.value as? Int { metrics[key] = Double(v) }
        }
        putNum("hr", "average_heart_rate")
        putNum("hr", "heart_rate")
        putNum("hrv", "rmssd")
        putNum("hrv", "average_hrv")
        putNum("steps", "steps")
        putNum("calories", "active_calories")
        putNum("readiness_score", "score")
        putNum("sleep_duration_s", "total_sleep_duration")
        putNum("deep_sleep_s", "deep_sleep_duration")
        putNum("rem_sleep_s", "rem_sleep_duration")
        putNum("light_sleep_s", "light_sleep_duration")

        var meta: [String: String] = ["data_type": dataType, "vendor": "oura"]
        if let oid = data["object_id"]?.value as? String { meta["object_id"] = oid }
        else if let oid = data["id"]?.value as? String { meta["object_id"] = oid }

        return WearMetrics(
            timestamp: ts,
            deviceId: "oura",
            source: "oura_\(dataType)",
            metrics: metrics,
            meta: meta
        )
    }

    private func extractTimestamp(from data: [String: AnyCodable]) -> Date? {
        let keys = ["timestamp", "day", "summary_date"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]
        let formatterDate = DateFormatter()
        formatterDate.dateFormat = "yyyy-MM-dd"
        formatterDate.timeZone = TimeZone(identifier: "UTC")
        for key in keys {
            if let s = data[key]?.value as? String {
                if let d = formatter.date(from: s) { return d }
                if let d = formatterNoFrac.date(from: s) { return d }
                if let d = formatterDate.date(from: s) { return d }
            }
        }
        return nil
    }

    // MARK: - Keychain

    private var userIdKey: String { "synheart_oura_user_id_\(appId)" }

    private func saveUserId(_ id: String) {
        let data = id.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadUserId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let id = String(data: data, encoding: .utf8) else { return nil }
        return id
    }

    private func clearUserId() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}
