import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Garmin wearable device provider
///
/// Handles OAuth PKCE connection and data fetching from Garmin devices
/// via the Wear Service backend.
///
/// Key differences from WHOOP:
/// - Uses OAuth2 PKCE flow (handled by service)
/// - Intermediate redirect flow (Garmin doesn't accept deep links)
/// - GET callback (browser redirect) instead of POST
/// - Data is primarily delivered via webhooks
/// - 12 summary types available (dailies, epochs, sleeps, etc.)
/// - Backfill API for historical data
public class GarminProvider: WearableProvider {
    // MARK: - Summary Types

    /// Garmin summary types available for data fetching
    public enum SummaryType: String, CaseIterable {
        case dailies = "dailies"                 // Daily summaries (steps, calories, heart rate, stress, body battery)
        case epochs = "epochs"                   // 15-minute granular activity periods
        case sleeps = "sleeps"                   // Sleep duration, levels (deep/light/REM), scores
        case stressDetails = "stressDetails"     // Detailed stress values and body battery events
        case hrv = "hrv"                         // Heart rate variability metrics
        case userMetrics = "userMetrics"         // VO2 Max, Fitness Age
        case bodyComps = "bodyComps"             // Body composition (weight, BMI, body fat, etc.)
        case pulseox = "pulseox"                 // Pulse oximetry data
        case respiration = "respiration"         // Respiration rate data
        case healthSnapshot = "healthSnapshot"   // Health snapshot data
        case bloodPressures = "bloodPressures"   // Blood pressure measurements
        case skinTemp = "skinTemp"               // Skin temperature data
    }

    // MARK: - Properties

    /// The vendor type this provider supports
    public let vendor: DeviceAdapter = .garmin

    /// Application ID for the Wear Service
    private let appId: String

    /// Base URL for the Wear Service API
    private let baseUrl: URL

    /// Redirect URI for OAuth callback (deep link)
    private let redirectUri: String

    /// Connected user ID (stored securely)
    private var userId: String?

    /// API client for making requests to Wear Service
    private let api: WearServiceAPI

    /// Keychain service name for storing user ID
    private let keychainService: String

    /// State parameter for OAuth flow (CSRF protection)
    private var oauthState: String?

    // MARK: - Initialization

    /// Initialize Garmin provider
    ///
    /// - Parameters:
    ///   - appId: Application ID for the Wear Service
    ///   - baseUrl: Base URL for the Wear Service API (default: production URL)
    ///   - redirectUri: Deep link URI for OAuth callback (default: "synheart://oauth/callback")
    public init(
        appId: String,
        baseUrl: URL? = nil,
        redirectUri: String = "synheart://oauth/callback"
    ) {
        self.appId = appId
        self.baseUrl = baseUrl ?? URL(string: "https://synheart-wear-service-leatest.onrender.com")!
        self.redirectUri = redirectUri
        self.api = WearServiceAPI(baseURL: self.baseUrl)
        self.keychainService = "com.synheart.wear.garmin"

        // Try to load existing user ID from keychain
        self.userId = loadUserId()
    }

    // MARK: - WearableProvider Protocol

    /// Check if a user account is currently connected
    public func isConnected() -> Bool {
        return userId != nil
    }

    /// Get the connected user ID
    public func getUserId() -> String? {
        return userId
    }

    /// Connect the user's Garmin account (initiates OAuth flow)
    ///
    /// This method will:
    /// 1. Generate a state parameter for CSRF protection
    /// 2. Get authorization URL from Wear Service
    /// 3. Open browser for user to authorize
    ///
    /// After user authorizes, Garmin redirects to service HTTPS URL,
    /// then service redirects to app's deep link with success/error.
    ///
    /// - Throws: SynheartWearError if connection fails
    public func connect() async throws {
        // Generate state parameter for CSRF protection
        let state = generateState()
        oauthState = state

        // Store state temporarily (will be validated in connectWithCode)
        UserDefaults.standard.set(state, forKey: stateKey)

        do {
            // Get authorization URL from Wear Service
            // The service handles PKCE code_verifier/challenge generation
            let response = try await api.getGarminAuthorizationURL(
                redirectUri: redirectUri,
                state: state,
                appId: appId,
                userId: userId
            )

            // Open authorization URL in browser
            guard let url = URL(string: response.authorizationUrl) else {
                throw SynheartWearError.invalidResponse
            }

            #if os(iOS)
            await MainActor.run {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            }
            #elseif canImport(AppKit)
            // macOS: Use NSWorkspace
            NSWorkspace.shared.open(url)
            #else
            // Fallback for other platforms (watchOS, etc.)
            throw SynheartWearError.apiError("Cannot open URL on this platform")
            #endif

        } catch let error as NetworkError {
            throw convertNetworkError(error)
        } catch {
            throw SynheartWearError.apiError(error.localizedDescription)
        }
    }

    /// Complete the OAuth connection from deep link callback
    ///
    /// For Garmin, the service handles the intermediate redirect and token exchange.
    /// The app receives a deep link with query parameters:
    /// - success=true&user_id=xxx (on success)
    /// - success=false&error=message (on error)
    ///
    /// The `code` parameter here is actually the `user_id` for Garmin,
    /// since the service already exchanged the code for tokens.
    ///
    /// - Parameters:
    ///   - code: User ID from deep link callback (for Garmin, code is actually userId)
    ///   - state: State parameter from deep link (for validation)
    ///   - redirectUri: The redirect URI that was used in the authorization request
    /// - Throws: SynheartWearError if connection fails
    public func connectWithCode(code: String, state: String, redirectUri: String) async throws {
        // Validate that an OAuth flow was initiated
        guard UserDefaults.standard.string(forKey: stateKey) != nil else {
            throw SynheartWearError.notConnected
        }

        // Validate state parameter (CSRF protection)
        // For Garmin, state validation is less strict since state may be encoded differently
        if let storedState = UserDefaults.standard.string(forKey: stateKey),
           storedState != state {
            print("[GarminProvider] Warning: State mismatch - saved: \(storedState), received: \(state)")
            // Don't throw for Garmin since state is encoded differently in intermediate redirect
        }

        // Clear stored state
        UserDefaults.standard.removeObject(forKey: stateKey)
        oauthState = nil

        // For Garmin, the 'code' parameter is actually the user_id
        // The service already exchanged the authorization code for tokens
        userId = code
        saveUserId(code)
    }

    /// Handle OAuth callback from deep link
    ///
    /// This is a convenience method specifically for Garmin's intermediate redirect flow.
    /// Call this when you receive the deep link after user authorization.
    ///
    /// - Parameters:
    ///   - success: Whether the OAuth was successful
    ///   - userId: User ID (if success=true)
    ///   - error: Error message (if success=false)
    /// - Returns: User ID if successful
    /// - Throws: SynheartWearError if callback indicates failure
    @discardableResult
    public func handleDeepLinkCallback(
        success: Bool,
        userId: String?,
        error: String?
    ) async throws -> String {
        if success, let userId = userId {
            self.userId = userId
            saveUserId(userId)

            // Clear stored OAuth state
            UserDefaults.standard.removeObject(forKey: stateKey)
            oauthState = nil

            return userId
        } else {
            throw SynheartWearError.apiError("Garmin OAuth failed: \(error ?? "Unknown error")")
        }
    }

    /// Disconnect the user's Garmin account
    ///
    /// Removes the connection and clears stored credentials.
    /// For Garmin, this also calls Garmin's DELETE /user/registration API via the service.
    /// This method will succeed even if the API call fails, ensuring local
    /// state is always cleared.
    ///
    /// - Throws: SynheartWearError if disconnection fails (but local state is still cleared)
    public func disconnect() async throws {
        guard let userId = userId else {
            // Already disconnected - not an error
            return
        }

        // Always clear local state first
        self.userId = nil
        clearUserId()

        // Then try to notify the server
        do {
            _ = try await api.disconnectGarmin(userId: userId, appId: appId)
        } catch let error as NetworkError {
            // Log but don't throw - local state is already cleared
            let convertedError = convertNetworkError(error)
            print("Warning: Failed to notify server of Garmin disconnection: \(convertedError.errorDescription ?? "Unknown error")")
            // Don't throw - disconnection is complete locally
        } catch {
            print("Warning: Unexpected error during Garmin disconnect: \(error.localizedDescription)")
            // Don't throw - disconnection is complete locally
        }
    }

    // MARK: - Data Fetching Methods

    /// Fetch recovery data from Garmin
    ///
    /// Note: For Garmin, "recovery" is not a native concept.
    /// This fetches HRV data which is most similar to recovery metrics.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of HRV records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchRecovery(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        // For Garmin, recovery is best represented by HRV data
        return try await fetchHRV(start: start, end: end)
    }

    /// Fetch daily summaries from Garmin
    ///
    /// Contains steps, calories, heart rate, stress levels, body battery.
    /// Corresponds to the "My Day" section of Garmin Connect.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of daily summary records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchDailies(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .dailies, start: start, end: end)
    }

    /// Fetch epoch summaries from Garmin
    ///
    /// 15-minute granular activity periods with activity types,
    /// steps, distance, calories, MET values, and intensity.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of epoch records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchEpochs(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .epochs, start: start, end: end)
    }

    /// Fetch sleep summaries from Garmin
    ///
    /// Sleep duration, levels (deep/light/REM), awake time,
    /// sleep scores, SpO2 values, respiration data.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of sleep records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchSleeps(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .sleeps, start: start, end: end)
    }

    /// Fetch stress details from Garmin
    ///
    /// Detailed stress level values, body battery values,
    /// and body battery activity events.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of stress records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchStressDetails(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .stressDetails, start: start, end: end)
    }

    /// Fetch HRV summaries from Garmin
    ///
    /// Heart rate variability metrics collected during overnight sleep
    /// including lastNightAvg, lastNight5MinHigh, and RMSSD measurements.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of HRV records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchHRV(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .hrv, start: start, end: end)
    }

    /// Fetch user metrics from Garmin
    ///
    /// Fitness metrics including VO2 Max, VO2 Max Cycling, and Fitness Age.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of user metric records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchUserMetrics(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .userMetrics, start: start, end: end)
    }

    /// Fetch body composition from Garmin
    ///
    /// Weight, BMI, muscle mass, bone mass, body water percentage, body fat percentage.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of body composition records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchBodyComps(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .bodyComps, start: start, end: end)
    }

    /// Fetch pulse ox data from Garmin
    ///
    /// Blood oxygen saturation (SpO2) data.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of pulse ox records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchPulseOx(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .pulseox, start: start, end: end)
    }

    /// Fetch respiration data from Garmin
    ///
    /// Breathing rate data throughout the day, during sleep, and activities.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of respiration records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchRespiration(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .respiration, start: start, end: end)
    }

    /// Fetch health snapshot from Garmin
    ///
    /// Collection of key health insights from a 2-minute session
    /// including HR, HRV, Pulse Ox, respiration, and stress metrics.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of health snapshot records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchHealthSnapshot(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .healthSnapshot, start: start, end: end)
    }

    /// Fetch blood pressure data from Garmin
    ///
    /// Blood pressure readings including systolic, diastolic, and pulse values.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of blood pressure records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchBloodPressures(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .bloodPressures, start: start, end: end)
    }

    /// Fetch skin temperature data from Garmin
    ///
    /// Skin temperature changes during sleep window.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Array of skin temperature records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchSkinTemp(
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [WearMetrics] {
        return try await fetchGarminData(summaryType: .skinTemp, start: start, end: end)
    }

    // MARK: - Backfill API

    /// Request historical data backfill from Garmin
    ///
    /// Garmin uses webhook-based data delivery, so historical data
    /// must be requested via the backfill API. Data is delivered
    /// asynchronously via webhooks to your configured app_webhook_url.
    ///
    /// - Parameters:
    ///   - summaryType: Type of data to backfill
    ///   - startDate: Start of date range (max 90 days from end)
    ///   - endDate: End of date range
    /// - Returns: True if backfill request was accepted
    /// - Throws: SynheartWearError if request fails
    @discardableResult
    public func requestBackfill(
        summaryType: SummaryType,
        startDate: Date,
        endDate: Date
    ) async throws -> Bool {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }

        do {
            let response = try await api.requestGarminBackfill(
                userId: userId,
                summaryType: summaryType.rawValue,
                appId: appId,
                start: startDate,
                end: endDate
            )

            return response.status == "ok" || response.status == "accepted"
        } catch let error as NetworkError {
            throw convertNetworkError(error)
        } catch let error as SynheartWearError {
            throw error
        } catch {
            throw SynheartWearError.apiError("Failed to request Garmin backfill: \(error.localizedDescription)")
        }
    }

    // MARK: - Webhook URLs

    /// Get webhook URLs to configure in Garmin Developer Portal
    ///
    /// Returns a dictionary of summary type to webhook URL.
    /// These URLs should be configured in your Garmin Developer Portal
    /// at https://apis.garmin.com/tools/endpoints/
    ///
    /// - Returns: Dictionary mapping summary types to webhook endpoint URLs
    /// - Throws: SynheartWearError if request fails
    public func getWebhookUrls() async throws -> [String: String] {
        do {
            let response = try await api.getGarminWebhookUrls(appId: appId)
            return response.endpoints
        } catch let error as NetworkError {
            throw convertNetworkError(error)
        } catch {
            throw SynheartWearError.apiError("Failed to get Garmin webhook URLs: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    /// Generic data fetching for any Garmin summary type
    private func fetchGarminData(
        summaryType: SummaryType,
        start: Date?,
        end: Date?
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }

        do {
            let response = try await api.fetchGarminData(
                userId: userId,
                summaryType: summaryType.rawValue,
                appId: appId,
                start: start,
                end: end
            )

            // Validate response
            guard !response.records.isEmpty else {
                return [] // Empty response is valid, just return empty array
            }

            let vendor = response.vendor ?? "garmin"
            let metrics = response.records.compactMap { record in
                convertGarminRecordToMetrics(record, summaryType: summaryType, vendor: vendor, userId: response.userId)
            }

            // Validate converted metrics
            let validMetrics = metrics.filter { metric in
                metric.timestamp.timeIntervalSince1970 > 0
            }

            return validMetrics
        } catch let error as NetworkError {
            // Handle 501 - webhook required
            if case .serverError(501, _) = error {
                print("[GarminProvider] Direct data queries not supported for \(summaryType.rawValue). Data is delivered via webhooks. Use requestBackfill() for historical data.")
                return []
            }
            throw convertNetworkError(error)
        } catch let error as SynheartWearError {
            throw error
        } catch {
            throw SynheartWearError.apiError("Unexpected error: \(error.localizedDescription)")
        }
    }

    /// Convert a Garmin data record to WearMetrics
    private func convertGarminRecordToMetrics(
        _ record: DataRecord,
        summaryType: SummaryType,
        vendor: String,
        userId: String
    ) -> WearMetrics? {
        let data = record.fields

        // Extract timestamp
        let timestamp = extractTimestamp(from: data) ?? Date()

        // Extract device ID
        let deviceId = extractString(from: data, keys: ["summaryId", "userAccessToken", "id"]) ?? "\(vendor)_\(userId.prefix(8))"

        // Build metrics dictionary
        var metrics: [String: Double] = [:]
        var meta: [String: String] = [:]

        // Extract metrics based on summary type
        switch summaryType {
        case .dailies:
            extractDailiesMetrics(from: data, into: &metrics, meta: &meta)
        case .epochs:
            extractEpochsMetrics(from: data, into: &metrics, meta: &meta)
        case .sleeps:
            extractSleepsMetrics(from: data, into: &metrics, meta: &meta)
        case .stressDetails:
            extractStressMetrics(from: data, into: &metrics, meta: &meta)
        case .hrv:
            extractHRVMetrics(from: data, into: &metrics, meta: &meta)
        case .userMetrics:
            extractUserMetricsMetrics(from: data, into: &metrics, meta: &meta)
        case .bodyComps:
            extractBodyCompMetrics(from: data, into: &metrics, meta: &meta)
        case .pulseox:
            extractPulseOxMetrics(from: data, into: &metrics, meta: &meta)
        case .respiration:
            extractRespirationMetrics(from: data, into: &metrics, meta: &meta)
        case .healthSnapshot:
            extractHealthSnapshotMetrics(from: data, into: &metrics, meta: &meta)
        case .bloodPressures:
            extractBloodPressureMetrics(from: data, into: &metrics, meta: &meta)
        case .skinTemp:
            extractSkinTempMetrics(from: data, into: &metrics, meta: &meta)
        }

        // Add data type to meta
        meta["summary_type"] = summaryType.rawValue
        meta["vendor"] = vendor

        return WearMetrics(
            timestamp: timestamp,
            deviceId: deviceId,
            source: "\(vendor)_\(summaryType.rawValue)",
            metrics: metrics,
            meta: meta,
            rrIntervals: nil
        )
    }

    // MARK: - Timestamp Extraction

    /// Extract timestamp from Garmin data record
    private func extractTimestamp(from data: [String: AnyCodable]) -> Date? {
        let timestampKeys = [
            "startTimeInSeconds", "calendarDate", "summaryId",
            "startTimeGMT", "sleepStartTimestampGMT", "measurementTimeGMT"
        ]

        for key in timestampKeys {
            if let value = data[key]?.value {
                if let numberValue = value as? Double {
                    // Garmin uses seconds, convert if needed
                    let timestamp = numberValue < 10_000_000_000 ? numberValue : numberValue / 1000.0
                    return Date(timeIntervalSince1970: timestamp)
                } else if let intValue = value as? Int {
                    // Garmin uses seconds
                    let timestamp = intValue < 10_000_000_000 ? TimeInterval(intValue) : TimeInterval(intValue) / 1000.0
                    return Date(timeIntervalSince1970: timestamp)
                } else if let stringValue = value as? String {
                    // Try date format (YYYY-MM-DD)
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    dateFormatter.timeZone = TimeZone(identifier: "UTC")
                    if let date = dateFormatter.date(from: stringValue) {
                        return date
                    }
                    // Try ISO8601 format
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = isoFormatter.date(from: stringValue) {
                        return date
                    }
                    isoFormatter.formatOptions = [.withInternetDateTime]
                    if let date = isoFormatter.date(from: stringValue) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    /// Extract string value from data using multiple possible keys
    private func extractString(from data: [String: AnyCodable], keys: [String]) -> String? {
        for key in keys {
            if let value = data[key]?.value as? String {
                return value
            }
        }
        return nil
    }

    /// Extract double value from data using multiple possible keys
    private func extractDouble(from data: [String: AnyCodable], keys: [String]) -> Double? {
        for key in keys {
            if let value = data[key]?.value {
                if let doubleValue = value as? Double {
                    return doubleValue
                } else if let intValue = value as? Int {
                    return Double(intValue)
                } else if let stringValue = value as? String, let doubleValue = Double(stringValue) {
                    return doubleValue
                }
            }
        }
        return nil
    }

    // MARK: - Garmin-Specific Metric Extractors

    /// Extract dailies metrics (steps, calories, heart rate, stress, body battery)
    private func extractDailiesMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Steps
        if let steps = extractDouble(from: data, keys: ["steps", "totalSteps"]) {
            metrics["steps"] = steps
        }

        // Calories
        if let calories = extractDouble(from: data, keys: ["activeKilocalories", "totalKilocalories", "bmrKilocalories"]) {
            metrics["calories"] = calories
        }

        // Heart rate
        if let rhr = extractDouble(from: data, keys: ["restingHeartRate", "restingHeartRateInBeatsPerMinute"]) {
            metrics["hr"] = rhr
        }
        if let maxHr = extractDouble(from: data, keys: ["maxHeartRate", "maxHeartRateInBeatsPerMinute"]) {
            meta["max_hr"] = String(maxHr)
        }
        if let minHr = extractDouble(from: data, keys: ["minHeartRate", "minHeartRateInBeatsPerMinute"]) {
            meta["min_hr"] = String(minHr)
        }

        // Stress
        if let avgStress = extractDouble(from: data, keys: ["averageStressLevel"]) {
            metrics["stress"] = avgStress / 100.0  // Normalize to 0-1
        }
        if let maxStress = extractDouble(from: data, keys: ["maxStressLevel"]) {
            meta["max_stress"] = String(maxStress / 100.0)
        }

        // Body battery
        if let bbCharged = extractDouble(from: data, keys: ["bodyBatteryChargedValue"]) {
            meta["body_battery_charged"] = String(bbCharged)
        }
        if let bbDrained = extractDouble(from: data, keys: ["bodyBatteryDrainedValue"]) {
            meta["body_battery_drained"] = String(bbDrained)
        }

        // Distance
        if let distance = extractDouble(from: data, keys: ["distanceInMeters"]) {
            metrics["distance"] = distance
        }

        // Active time
        if let activeTime = extractDouble(from: data, keys: ["activeTimeInSeconds", "activeSeconds"]) {
            meta["active_time_minutes"] = String(activeTime / 60.0)
        }
    }

    /// Extract epochs metrics (15-minute activity periods)
    private func extractEpochsMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Activity type
        if let activityType = extractString(from: data, keys: ["activityType"]) {
            meta["activity_type"] = activityType
        }

        // Steps
        if let steps = extractDouble(from: data, keys: ["steps"]) {
            metrics["steps"] = steps
        }

        // Distance
        if let distance = extractDouble(from: data, keys: ["distanceInMeters"]) {
            metrics["distance"] = distance
        }

        // Calories
        if let calories = extractDouble(from: data, keys: ["activeKilocalories"]) {
            metrics["calories"] = calories
        }

        // MET
        if let met = extractDouble(from: data, keys: ["met"]) {
            meta["met"] = String(met)
        }

        // Intensity
        if let intensity = extractDouble(from: data, keys: ["intensity"]) {
            meta["intensity"] = String(intensity)
        }
    }

    /// Extract sleeps metrics (sleep duration, stages, scores)
    private func extractSleepsMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Duration
        if let duration = extractDouble(from: data, keys: ["durationInSeconds"]) {
            meta["sleep_duration_hours"] = String(duration / 3600.0)
        }

        // Sleep stages
        if let deep = extractDouble(from: data, keys: ["deepSleepDurationInSeconds"]) {
            meta["deep_duration_minutes"] = String(deep / 60.0)
        }
        if let light = extractDouble(from: data, keys: ["lightSleepDurationInSeconds"]) {
            meta["light_duration_minutes"] = String(light / 60.0)
        }
        if let rem = extractDouble(from: data, keys: ["remSleepInSeconds"]) {
            meta["rem_duration_minutes"] = String(rem / 60.0)
        }
        if let awake = extractDouble(from: data, keys: ["awakeDurationInSeconds"]) {
            meta["awake_duration_minutes"] = String(awake / 60.0)
        }

        // Sleep score
        if let score = extractDouble(from: data, keys: ["overallSleepScore", "sleepScores"]) {
            meta["sleep_score"] = String(score)
        }

        // Validation
        if let validation = extractString(from: data, keys: ["validation"]) {
            meta["validation"] = validation
        }
    }

    /// Extract stress metrics (stress levels, body battery)
    private func extractStressMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Stress level
        if let stress = extractDouble(from: data, keys: ["overallStressLevel", "averageStressLevel"]) {
            metrics["stress"] = stress / 100.0  // Normalize to 0-1
        }

        // Rest stress duration
        if let restStress = extractDouble(from: data, keys: ["restStressDurationInSeconds"]) {
            meta["rest_stress_minutes"] = String(restStress / 60.0)
        }

        // Activity stress duration
        if let activityStress = extractDouble(from: data, keys: ["activityStressDurationInSeconds"]) {
            meta["activity_stress_minutes"] = String(activityStress / 60.0)
        }

        // Body battery
        if let bbCharged = extractDouble(from: data, keys: ["bodyBatteryChargedValue"]) {
            meta["body_battery_charged"] = String(bbCharged)
        }
        if let bbDrained = extractDouble(from: data, keys: ["bodyBatteryDrainedValue"]) {
            meta["body_battery_drained"] = String(bbDrained)
        }
    }

    /// Extract HRV metrics (heart rate variability)
    private func extractHRVMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // HRV RMSSD
        if let hrv = extractDouble(from: data, keys: ["lastNightAvg", "hrvValue", "weeklyAvg"]) {
            metrics["hrv_rmssd"] = hrv
        }

        // Last night 5-min high
        if let fiveMinHigh = extractDouble(from: data, keys: ["lastNight5MinHigh"]) {
            meta["last_night_5min_high"] = String(fiveMinHigh)
        }

        // Baseline
        if let baseline = extractDouble(from: data, keys: ["baseline"]) {
            meta["baseline"] = String(baseline)
        }

        // Status
        if let status = extractString(from: data, keys: ["status"]) {
            meta["status"] = status
        }
    }

    /// Extract user metrics (VO2 Max, Fitness Age)
    private func extractUserMetricsMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // VO2 Max
        if let vo2Max = extractDouble(from: data, keys: ["vo2Max"]) {
            meta["vo2_max"] = String(vo2Max)
        }

        // VO2 Max Cycling
        if let vo2MaxCycling = extractDouble(from: data, keys: ["vo2MaxCycling"]) {
            meta["vo2_max_cycling"] = String(vo2MaxCycling)
        }

        // Fitness Age
        if let fitnessAge = extractDouble(from: data, keys: ["fitnessAge"]) {
            meta["fitness_age"] = String(fitnessAge)
        }

        // Enhanced flag
        if let enhanced = data["enhanced"]?.value as? Bool {
            meta["enhanced"] = enhanced ? "true" : "false"
        }
    }

    /// Extract body composition metrics (weight, BMI, body fat)
    private func extractBodyCompMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Weight (grams to kg)
        if let weightGrams = extractDouble(from: data, keys: ["weightInGrams"]) {
            meta["weight_kg"] = String(weightGrams / 1000.0)
        }

        // BMI
        if let bmi = extractDouble(from: data, keys: ["bmi"]) {
            meta["bmi"] = String(bmi)
        }

        // Body fat percentage
        if let bodyFat = extractDouble(from: data, keys: ["bodyFatPercentage"]) {
            meta["body_fat_percentage"] = String(bodyFat)
        }

        // Muscle mass
        if let muscleMass = extractDouble(from: data, keys: ["muscleMassInGrams"]) {
            meta["muscle_mass_kg"] = String(muscleMass / 1000.0)
        }

        // Bone mass
        if let boneMass = extractDouble(from: data, keys: ["boneMassInGrams"]) {
            meta["bone_mass_kg"] = String(boneMass / 1000.0)
        }

        // Body water percentage
        if let bodyWater = extractDouble(from: data, keys: ["bodyWaterPercentage"]) {
            meta["body_water_percentage"] = String(bodyWater)
        }
    }

    /// Extract pulse ox metrics (SpO2)
    private func extractPulseOxMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // SpO2 average
        if let spo2Avg = extractDouble(from: data, keys: ["averageSpo2", "spo2Value"]) {
            meta["spo2_average"] = String(spo2Avg)
        }

        // SpO2 lowest
        if let spo2Low = extractDouble(from: data, keys: ["lowestSpo2"]) {
            meta["spo2_lowest"] = String(spo2Low)
        }

        // Acclimation state
        if let acclimation = extractString(from: data, keys: ["acclimationState"]) {
            meta["acclimation_state"] = acclimation
        }
    }

    /// Extract respiration metrics (breathing rate)
    private func extractRespirationMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Average breathing rate
        if let avgResp = extractDouble(from: data, keys: ["avgWakingRespirationValue", "avgSleepRespirationValue"]) {
            meta["avg_respiration_rate"] = String(avgResp)
        }

        // Highest
        if let highest = extractDouble(from: data, keys: ["highestRespirationValue"]) {
            meta["highest_respiration_rate"] = String(highest)
        }

        // Lowest
        if let lowest = extractDouble(from: data, keys: ["lowestRespirationValue"]) {
            meta["lowest_respiration_rate"] = String(lowest)
        }
    }

    /// Extract health snapshot metrics (2-minute session insights)
    private func extractHealthSnapshotMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Heart rate
        if let hr = extractDouble(from: data, keys: ["heartRate", "avgHeartRate"]) {
            metrics["hr"] = hr
        }

        // HRV
        if let hrv = extractDouble(from: data, keys: ["hrv", "hrvSdnn"]) {
            metrics["hrv_sdnn"] = hrv
        }

        // SpO2
        if let spo2 = extractDouble(from: data, keys: ["spo2"]) {
            meta["spo2"] = String(spo2)
        }

        // Respiration
        if let respiration = extractDouble(from: data, keys: ["respiration"]) {
            meta["respiration_rate"] = String(respiration)
        }

        // Stress
        if let stress = extractDouble(from: data, keys: ["stress"]) {
            metrics["stress"] = stress / 100.0  // Normalize to 0-1
        }
    }

    /// Extract blood pressure metrics
    private func extractBloodPressureMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Systolic
        if let systolic = extractDouble(from: data, keys: ["systolic"]) {
            meta["systolic"] = String(systolic)
        }

        // Diastolic
        if let diastolic = extractDouble(from: data, keys: ["diastolic"]) {
            meta["diastolic"] = String(diastolic)
        }

        // Pulse
        if let pulse = extractDouble(from: data, keys: ["pulse"]) {
            metrics["hr"] = pulse
        }

        // Source type
        if let sourceType = extractString(from: data, keys: ["sourceType"]) {
            meta["source_type"] = sourceType
        }
    }

    /// Extract skin temperature metrics
    private func extractSkinTempMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Average deviation
        if let avgDeviation = extractDouble(from: data, keys: ["averageDeviation", "avgSkinTempDeviation"]) {
            meta["skin_temp_deviation_celsius"] = String(avgDeviation)
        }

        // Min deviation
        if let minDeviation = extractDouble(from: data, keys: ["minSkinTempDeviation"]) {
            meta["skin_temp_min_deviation"] = String(minDeviation)
        }

        // Max deviation
        if let maxDeviation = extractDouble(from: data, keys: ["maxSkinTempDeviation"]) {
            meta["skin_temp_max_deviation"] = String(maxDeviation)
        }
    }

    // MARK: - Utility Methods

    /// Generate a random state parameter for OAuth flow
    private func generateState() -> String {
        return UUID().uuidString
    }

    /// Key for storing OAuth state in UserDefaults
    private var stateKey: String {
        return "synheart_garmin_oauth_state_\(appId)"
    }

    /// Key for storing user ID in Keychain
    private var userIdKey: String {
        return "synheart_garmin_user_id_\(appId)"
    }

    /// Save user ID to Keychain
    private func saveUserId(_ userId: String) {
        let data = userId.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey,
            kSecValueData as String: data
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Load user ID from Keychain
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
              let userId = String(data: data, encoding: .utf8) else {
            return nil
        }

        return userId
    }

    /// Clear user ID from Keychain
    private func clearUserId() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey
        ]

        SecItemDelete(query as CFDictionary)
    }
}
