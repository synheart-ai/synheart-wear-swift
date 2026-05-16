import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Fitbit cloud provider.
///
/// OAuth is mediated by the Synheart Wear API: the client never sees
/// Fitbit access tokens. After a successful authorize, the cloud delivers
/// a `vendor_user_id` to the app via a deep-link callback (matching the
/// Flutter SDK contract).
///
/// `WearableProvider.connectWithCode(code:state:redirectUri:)` is overloaded
/// to accept that `vendor_user_id` as the `code` parameter — there is no
/// authorization-code exchange on the device side.
public class FitbitProvider: WearableProvider {
    public let vendor: DeviceAdapter = .fitbit

    private let appId: String
    private let baseUrl: URL
    private let redirectUri: String
    private let projectId: String?
    private var userId: String?
    private let api: WearServiceAPI
    private let keychainService = "ai.synheart.wear.fitbit"
    private static let vendorName = "fitbit"

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
            throw SynheartWearError.apiError("FitbitProvider: setUserId(_:) is required before connect() — Fitbit OAuth needs a user identifier to associate with the cloud account.")
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

    /// Complete the connection. For Fitbit, `code` is the `vendor_user_id`
    /// delivered by the deep-link callback (`?vendor=fitbit&user_id=...&status=success`).
    /// `state` and `redirectUri` are accepted for protocol parity but unused.
    public func connectWithCode(code: String, state: String, redirectUri: String) async throws {
        guard !code.isEmpty else {
            throw SynheartWearError.authenticationFailed
        }
        userId = code
        saveUserId(code)
    }

    /// Set the user identifier used to scope this Fitbit connection.
    /// Must be called before `connect()`.
    public func setUserId(_ id: String) {
        userId = id
    }

    public func disconnect() async throws {
        guard let uid = userId else { return }
        userId = nil
        clearUserId()
        do {
            _ = try await api.disconnectVendor(vendor: Self.vendorName, userId: uid, appId: appId)
        } catch {
            // local state already cleared
        }
    }

    // MARK: - Data

    public func fetchHrv(start: Date? = nil, end: Date? = nil, limit: Int? = 100) async throws -> [WearMetrics] {
        try await fetchData(dataType: "hrv", start: start, end: end, limit: limit)
    }

    public func fetchSleep(start: Date? = nil, end: Date? = nil, limit: Int? = 50) async throws -> [WearMetrics] {
        try await fetchData(dataType: "sleep", start: start, end: end, limit: limit)
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
        if let summary = data["summary"]?.value as? [String: Any] {
            if let steps = summary["steps"] as? Double { metrics["steps"] = steps }
            else if let steps = summary["steps"] as? Int { metrics["steps"] = Double(steps) }
            if let cal = summary["caloriesOut"] as? Double { metrics["calories"] = cal }
            else if let cal = summary["caloriesOut"] as? Int { metrics["calories"] = Double(cal) }
        }
        if let value = data["value"]?.value as? [String: Any] {
            if let rhr = value["restingHeartRate"] as? Double { metrics["hr_resting"] = rhr }
            else if let rhr = value["restingHeartRate"] as? Int { metrics["hr_resting"] = Double(rhr) }
        }

        return WearMetrics(
            timestamp: ts,
            deviceId: "fitbit",
            source: "fitbit_\(dataType)",
            metrics: metrics,
            meta: ["data_type": dataType, "vendor": "fitbit"]
        )
    }

    private func extractTimestamp(from data: [String: AnyCodable]) -> Date? {
        let keys = ["dateTime", "date", "timestamp", "created_at", "start_time"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]
        for key in keys {
            if let s = data[key]?.value as? String {
                if let d = formatter.date(from: s) { return d }
                if let d = formatterNoFrac.date(from: s) { return d }
            }
        }
        return nil
    }

    // MARK: - Keychain

    private var userIdKey: String { "synheart_fitbit_user_id_\(appId)" }

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
