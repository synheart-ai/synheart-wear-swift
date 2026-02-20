import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// WHOOP wearable device provider
///
/// Handles OAuth connection and data fetching from WHOOP devices
/// via the Wear Service backend.
public class WhoopProvider: WearableProvider {
    // MARK: - Properties
    
    /// The vendor type this provider supports
    public let vendor: DeviceAdapter = .whoop
    
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
    
    /// Initialize WHOOP provider
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
        self.baseUrl = baseUrl ?? URL(string: "https://api.synheart.ai/wear")!
        self.redirectUri = redirectUri
        self.api = WearServiceAPI(baseURL: self.baseUrl)
        self.keychainService = "com.synheart.wear.whoop"
        
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
    
    /// Connect the user's account (initiates OAuth flow)
    ///
    /// This method will:
    /// 1. Generate a state parameter for CSRF protection
    /// 2. Get authorization URL from Wear Service
    /// 3. Open browser for user to authorize
    ///
    /// Note: The actual OAuth callback must be handled by the app via deep link,
    /// and then `connectWithCode()` should be called.
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
            let response = try await api.getAuthorizationURL(
                redirectUri: redirectUri,
                state: state,
                appId: appId
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
    
    /// Complete the OAuth connection with authorization code
    ///
    /// This method should be called when the app receives the OAuth callback
    /// via deep link with the authorization code.
    ///
    /// **Important**: Your app must handle deep links. See README for setup instructions.
    ///
    /// - Parameters:
    ///   - code: Authorization code from OAuth callback
    ///   - state: State parameter from OAuth callback (for CSRF protection)
    ///   - redirectUri: The redirect URI that was used in the authorization request
    /// - Throws: SynheartWearError if connection fails
    ///   - `.authenticationFailed` if state validation fails
    ///   - `.notConnected` if no OAuth flow was initiated
    ///   - Network errors if API call fails
    public func connectWithCode(code: String, state: String, redirectUri: String) async throws {
        // Validate that an OAuth flow was initiated
        guard UserDefaults.standard.string(forKey: stateKey) != nil else {
            throw SynheartWearError.notConnected
        }
        
        // Validate state parameter (CSRF protection)
        guard let storedState = UserDefaults.standard.string(forKey: stateKey),
              storedState == state else {
            // Clear invalid state
            UserDefaults.standard.removeObject(forKey: stateKey)
            throw SynheartWearError.authenticationFailed
        }
        
        // Clear stored state
        UserDefaults.standard.removeObject(forKey: stateKey)
        oauthState = nil
        
        do {
            // Exchange code for access token
            let response = try await api.exchangeCode(
                code: code,
                state: state,
                redirectUri: redirectUri
            )
            
            // Store user ID securely
            userId = response.userId
            saveUserId(response.userId)
            
        } catch let error as NetworkError {
            throw convertNetworkError(error)
        } catch {
            throw SynheartWearError.apiError(error.localizedDescription)
        }
    }
    
    /// Disconnect the user's account
    ///
    /// Removes the connection and clears stored credentials.
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
            _ = try await api.disconnect(userId: userId, appId: appId)
        } catch let error as NetworkError {
            // Log but don't throw - local state is already cleared
            // This handles cases where user is offline or account already disconnected
            let convertedError = convertNetworkError(error)
            print("Warning: Failed to notify server of disconnection: \(convertedError.errorDescription ?? "Unknown error")")
            // Don't throw - disconnection is complete locally
        } catch {
            print("Warning: Unexpected error during disconnect: \(error.localizedDescription)")
            // Don't throw - disconnection is complete locally
        }
    }
    
    // MARK: - Data Fetching Methods
    
    /// Fetch recovery data from WHOOP
    ///
    /// The Wear Service automatically handles token refresh if needed.
    /// If token refresh fails, this method will throw `.tokenExpired` error,
    /// and the user will need to reconnect by calling `connect()` again.
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of recovery records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    ///   - `.notConnected` if user hasn't connected
    ///   - `.tokenExpired` if token expired and refresh failed (user needs to reconnect)
    ///   - Network errors for connection issues
    public func fetchRecovery(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchRecovery(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            // Validate response
            guard !response.records.isEmpty else {
                return [] // Empty response is valid, just return empty array
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "recovery")
            
            // Validate converted metrics
            let validMetrics = metrics.filter { metric in
                // Basic validation - ensure we have at least a timestamp
                metric.timestamp.timeIntervalSince1970 > 0
            }
            
            return validMetrics
        } catch let error as NetworkError {
            throw convertNetworkError(error)
        } catch let error as SynheartWearError {
            throw error
        } catch {
            throw SynheartWearError.apiError("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    /// Fetch sleep data from WHOOP
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of sleep records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchSleep(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchSleep(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            // Validate response
            guard !response.records.isEmpty else {
                return [] // Empty response is valid
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "sleep")
            
            // Validate converted metrics
            let validMetrics = metrics.filter { metric in
                metric.timestamp.timeIntervalSince1970 > 0
            }
            
            return validMetrics
        } catch let error as NetworkError {
            throw convertNetworkError(error)
        } catch let error as SynheartWearError {
            throw error
        } catch {
            throw SynheartWearError.apiError("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    /// Fetch workout data from WHOOP
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of workout records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchWorkouts(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchWorkouts(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            // Validate response
            guard !response.records.isEmpty else {
                return [] // Empty response is valid
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "workout")
            
            // Validate converted metrics
            let validMetrics = metrics.filter { metric in
                metric.timestamp.timeIntervalSince1970 > 0
            }
            
            return validMetrics
        } catch let error as NetworkError {
            throw convertNetworkError(error)
        } catch let error as SynheartWearError {
            throw error
        } catch {
            throw SynheartWearError.apiError("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    /// Fetch cycle data from WHOOP
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of cycle records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchCycles(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchCycles(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            // Empty response is valid - return empty array
            guard !response.records.isEmpty else {
                return []
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "cycle")
            
            // Validate converted metrics - filter out any invalid ones
            let validMetrics = metrics.filter { metric in
                metric.timestamp.timeIntervalSince1970 > 0
            }
            
            // If we had records but no valid metrics, log a warning
            if !response.records.isEmpty && validMetrics.isEmpty {
                print("[WhoopProvider] Warning: Received \(response.records.count) cycle record(s) but none could be converted to valid metrics. This may indicate a data format issue.")
            }
            
            return validMetrics
        } catch let error as NetworkError {
            // Convert network errors with better context
            let convertedError = convertNetworkError(error)
            print("[WhoopProvider] fetchCycles failed: \(convertedError.errorDescription ?? "Unknown error")")
            throw convertedError
        } catch let error as SynheartWearError {
            print("[WhoopProvider] fetchCycles failed: \(error.errorDescription ?? "Unknown error")")
            throw error
        } catch {
            let errorMessage = "Unexpected error in fetchCycles: \(error.localizedDescription)"
            print("[WhoopProvider] \(errorMessage)")
            throw SynheartWearError.apiError(errorMessage)
        }
    }
    
    // MARK: - Private Methods
    
    /// Convert DataResponse from API to array of WearMetrics
    ///
    /// - Parameters:
    ///   - response: DataResponse from Wear Service API
    ///   - dataType: Type of data (recovery, sleep, workout, cycle)
    /// - Returns: Array of WearMetrics
    private func convertDataResponseToMetrics(_ response: DataResponse, dataType: String) -> [WearMetrics] {
        // Use vendor from response or fallback to "whoop"
        let vendor = response.vendor ?? "whoop"
        return response.records.compactMap { record in
            convertDataRecordToMetrics(record, dataType: dataType, vendor: vendor, userId: response.userId)
        }
    }
    
    /// Convert a single DataRecord to WearMetrics
    ///
    /// - Parameters:
    ///   - record: DataRecord from API
    ///   - dataType: Type of data (recovery, sleep, workout, cycle)
    ///   - vendor: Vendor name (e.g., "whoop")
    ///   - userId: User ID
    /// - Returns: WearMetrics or nil if conversion fails
    private func convertDataRecordToMetrics(_ record: DataRecord, dataType: String, vendor: String, userId: String) -> WearMetrics? {
        let data = record.fields
        
        // Extract timestamp (try multiple common field names)
        let timestamp = extractTimestamp(from: data) ?? Date()
        
        // Extract device ID (use record ID or generate one)
        let deviceId = extractString(from: data, keys: ["device_id", "deviceId", "id"]) ?? "\(vendor)_\(userId.prefix(8))"
        
        // Build metrics dictionary
        var metrics: [String: Double] = [:]
        var meta: [String: String] = [:]
        
        // Extract common metrics based on data type
        switch dataType {
        case "recovery":
            extractRecoveryMetrics(from: data, into: &metrics, meta: &meta)
        case "sleep":
            extractSleepMetrics(from: data, into: &metrics, meta: &meta)
        case "workout":
            extractWorkoutMetrics(from: data, into: &metrics, meta: &meta)
        case "cycle":
            extractCycleMetrics(from: data, into: &metrics, meta: &meta)
        default:
            extractGenericMetrics(from: data, into: &metrics, meta: &meta)
        }
        
        // Add data type to meta
        meta["data_type"] = dataType
        meta["vendor"] = vendor
        
        return WearMetrics(
            timestamp: timestamp,
            deviceId: deviceId,
            source: "\(vendor)_\(dataType)",
            metrics: metrics,
            meta: meta,
            rrIntervals: extractRRIntervals(from: data)
        )
    }
    
    /// Extract timestamp from data record
    private func extractTimestamp(from data: [String: AnyCodable]) -> Date? {
        // Try common timestamp field names (created_at is most common in WHOOP API)
        let timestampKeys = ["created_at", "timestamp", "start_time", "start", "end_time", "end", "date", "time", "updated_at"]
        
        for key in timestampKeys {
            if let value = data[key]?.value {
                if let stringValue = value as? String {
                    // Try ISO8601 format with fractional seconds
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: stringValue) {
                        return date
                    }
                    // Try without fractional seconds
                    formatter.formatOptions = [.withInternetDateTime]
                    if let date = formatter.date(from: stringValue) {
                        return date
                    }
                } else if let doubleValue = value as? Double {
                    // Unix timestamp
                    return Date(timeIntervalSince1970: doubleValue)
                } else if let intValue = value as? Int {
                    // Unix timestamp as integer
                    return Date(timeIntervalSince1970: TimeInterval(intValue))
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
    /// Also checks nested score object (e.g., score.recovery_score)
    private func extractDouble(from data: [String: AnyCodable], keys: [String]) -> Double? {
        // First try direct keys at top level
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
        
        // If not found, try nested in score object
        if let scoreObj = data["score"]?.value as? [String: Any] {
            let scoreDict = scoreObj.mapValues { AnyCodable($0) }
            for key in keys {
                if let value = scoreDict[key]?.value {
                    if let doubleValue = value as? Double {
                        return doubleValue
                    } else if let intValue = value as? Int {
                        return Double(intValue)
                    } else if let stringValue = value as? String, let doubleValue = Double(stringValue) {
                        return doubleValue
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Extract recovery-specific metrics
    private func extractRecoveryMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Get the score object (nested structure)
        var scoreData = data
        if let scoreObj = data["score"]?.value as? [String: Any] {
            // Extract from nested score object
            scoreData = scoreObj.mapValues { AnyCodable($0) }
        }
        
        // Recovery score - from score.recovery_score
        if let score = extractDouble(from: scoreData, keys: ["recovery_score", "recoveryScore"]) {
            metrics["recovery_score"] = score
        }
        
        // HRV metrics - from score.hrv_rmssd_milli (in milliseconds, convert to seconds)
        if let hrvMilli = extractDouble(from: scoreData, keys: ["hrv_rmssd_milli", "hrv_rmssd", "hrvRmssd", "rmssd"]) {
            metrics["hrv_rmssd"] = hrvMilli / 1000.0  // Convert milliseconds to seconds
        }
        if let sdnn = extractDouble(from: scoreData, keys: ["hrv_sdnn", "hrvSdnn", "sdnn"]) {
            metrics["hrv_sdnn"] = sdnn
        }
        
        // Resting Heart Rate - from score.resting_heart_rate
        if let rhr = extractDouble(from: scoreData, keys: ["resting_heart_rate", "restingHeartRate", "rhr", "resting_hr", "restingHr"]) {
            metrics["rhr"] = rhr
            metrics["hr"] = rhr  // Also set as hr for consistency
        }
        
        // Skin temperature - from score.skin_temp_celsius
        if let skinTemp = extractDouble(from: scoreData, keys: ["skin_temp_celsius", "skinTemp"]) {
            metrics["skin_temperature"] = skinTemp
        }
        
        // SpO2 - from score.spo2_percentage
        if let spo2 = extractDouble(from: scoreData, keys: ["spo2_percentage", "spo2"]) {
            metrics["spo2"] = spo2
        }
        
        // Store additional recovery metadata
        if let cycleId = extractDouble(from: data, keys: ["cycle_id", "cycleId"]) {
            meta["cycle_id"] = String(Int(cycleId))
        }
        if let sleepId = extractString(from: data, keys: ["sleep_id", "sleepId"]) {
            meta["sleep_id"] = sleepId
        }
        if let scoreState = extractString(from: data, keys: ["score_state", "scoreState"]) {
            meta["score_state"] = scoreState
        }
        
        // Store user_calibrating flag from score object
        if let scoreObj = data["score"]?.value as? [String: Any],
           let userCalibrating = scoreObj["user_calibrating"] as? Bool {
            meta["user_calibrating"] = userCalibrating ? "true" : "false"
        }
    }
    
    /// Extract sleep-specific metrics
    private func extractSleepMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Get the score object (nested structure)
        var scoreData = data
        if let scoreObj = data["score"]?.value as? [String: Any] {
            scoreData = scoreObj.mapValues { AnyCodable($0) }
        }
        
        // Sleep duration - calculate from start/end or use stage_summary.total_in_bed_time_milli
        if let startStr = extractString(from: data, keys: ["start"]),
           let endStr = extractString(from: data, keys: ["end"]),
           let start = parseDate(from: startStr),
           let end = parseDate(from: endStr) {
            let duration = end.timeIntervalSince(start)
            metrics["sleep_duration_hours"] = duration / 3600.0
        }
        
        // Sleep efficiency - from score.sleep_efficiency_percentage
        if let efficiency = extractDouble(from: scoreData, keys: ["sleep_efficiency_percentage", "sleep_efficiency", "sleepEfficiency", "efficiency"]) {
            metrics["sleep_efficiency"] = efficiency
        }
        
        // Sleep performance - from score.sleep_performance_percentage
        if let performance = extractDouble(from: scoreData, keys: ["sleep_performance_percentage", "sleep_performance"]) {
            metrics["sleep_performance"] = performance
        }
        
        // Sleep consistency - from score.sleep_consistency_percentage
        if let consistency = extractDouble(from: scoreData, keys: ["sleep_consistency_percentage", "sleep_consistency"]) {
            metrics["sleep_consistency"] = consistency
        }
        
        // Respiratory rate - from score.respiratory_rate
        if let respRate = extractDouble(from: scoreData, keys: ["respiratory_rate", "respiratoryRate"]) {
            metrics["respiratory_rate"] = respRate
        }
        
        // Extract stage_summary for sleep stages
        if let stageSummary = data["score"]?.value as? [String: Any],
           let stageDict = stageSummary["stage_summary"] as? [String: Any] {
            let stageData = stageDict.mapValues { AnyCodable($0) }
            
            // REM sleep - from score.stage_summary.total_rem_sleep_time_milli
            if let remMilli = extractDouble(from: stageData, keys: ["total_rem_sleep_time_milli", "rem", "rem_duration"]) {
                metrics["rem_duration_minutes"] = remMilli / 60000.0  // Convert milliseconds to minutes
            }
            
            // Deep/Slow Wave sleep - from score.stage_summary.total_slow_wave_sleep_time_milli
            if let deepMilli = extractDouble(from: stageData, keys: ["total_slow_wave_sleep_time_milli", "deep", "deep_duration", "slow_wave"]) {
                metrics["deep_duration_minutes"] = deepMilli / 60000.0
            }
            
            // Light sleep - from score.stage_summary.total_light_sleep_time_milli
            if let lightMilli = extractDouble(from: stageData, keys: ["total_light_sleep_time_milli", "light", "light_duration"]) {
                metrics["light_duration_minutes"] = lightMilli / 60000.0
            }
            
            // Total in bed time
            if let inBedMilli = extractDouble(from: stageData, keys: ["total_in_bed_time_milli"]) {
                metrics["sleep_duration_hours"] = inBedMilli / 3600000.0  // Convert milliseconds to hours
            }
            
            // Awake time
            if let awakeMilli = extractDouble(from: stageData, keys: ["total_awake_time_milli"]) {
                metrics["awake_duration_minutes"] = awakeMilli / 60000.0
            }
            
            // Additional stage_summary metrics
            if let disturbanceCount = extractDouble(from: stageData, keys: ["disturbance_count", "disturbanceCount"]) {
                metrics["disturbance_count"] = disturbanceCount
            }
            if let sleepCycleCount = extractDouble(from: stageData, keys: ["sleep_cycle_count", "sleepCycleCount"]) {
                metrics["sleep_cycle_count"] = sleepCycleCount
            }
            if let noDataMilli = extractDouble(from: stageData, keys: ["total_no_data_time_milli", "noDataTime"]) {
                metrics["no_data_duration_minutes"] = noDataMilli / 60000.0
            }
        }
        
        // Extract sleep_needed object
        if let scoreObj = data["score"]?.value as? [String: Any],
           let sleepNeeded = scoreObj["sleep_needed"] as? [String: Any] {
            let sleepNeededData = sleepNeeded.mapValues { AnyCodable($0) }
            
            if let baselineMilli = extractDouble(from: sleepNeededData, keys: ["baseline_milli", "baseline"]) {
                metrics["sleep_needed_baseline_hours"] = baselineMilli / 3600000.0  // Convert to hours
            }
            if let needFromNap = extractDouble(from: sleepNeededData, keys: ["need_from_recent_nap_milli", "needFromNap"]) {
                metrics["sleep_needed_from_nap_hours"] = needFromNap / 3600000.0
            }
            if let needFromStrain = extractDouble(from: sleepNeededData, keys: ["need_from_recent_strain_milli", "needFromStrain"]) {
                metrics["sleep_needed_from_strain_hours"] = needFromStrain / 3600000.0
            }
            if let needFromDebt = extractDouble(from: sleepNeededData, keys: ["need_from_sleep_debt_milli", "needFromDebt"]) {
                metrics["sleep_needed_from_debt_hours"] = needFromDebt / 3600000.0
            }
        }
        
        // Nap indicator
        if let nap = data["nap"]?.value as? Bool {
            meta["nap"] = nap ? "true" : "false"
        }
        
        // Store additional sleep metadata
        if let cycleId = extractDouble(from: data, keys: ["cycle_id", "cycleId"]) {
            meta["cycle_id"] = String(Int(cycleId))
        }
        if let sleepId = extractString(from: data, keys: ["id", "sleep_id", "sleepId"]) {
            meta["sleep_id"] = sleepId
        }
        if let scoreState = extractString(from: data, keys: ["score_state", "scoreState"]) {
            meta["score_state"] = scoreState
        }
        if let timezoneOffset = extractString(from: data, keys: ["timezone_offset", "timezoneOffset"]) {
            meta["timezone_offset"] = timezoneOffset
        }
    }
    
    /// Helper to parse date from ISO8601 string
    private func parseDate(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    
    /// Extract workout-specific metrics
    private func extractWorkoutMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Get the score object (nested structure)
        var scoreData = data
        if let scoreObj = data["score"]?.value as? [String: Any] {
            scoreData = scoreObj.mapValues { AnyCodable($0) }
        }
        
        // Duration - calculate from start/end times
        if let startStr = extractString(from: data, keys: ["start"]),
           let endStr = extractString(from: data, keys: ["end"]),
           let start = parseDate(from: startStr),
           let end = parseDate(from: endStr) {
            let duration = end.timeIntervalSince(start)
            metrics["workout_duration_minutes"] = duration / 60.0
        }
        
        // Calories/Energy - from score.kilojoule (convert to calories: 1 kJ = 0.239006 kcal)
        if let kilojoule = extractDouble(from: scoreData, keys: ["kilojoule", "kilojoules"]) {
            metrics["calories"] = kilojoule * 0.239006  // Convert kJ to kcal
        } else if let calories = extractDouble(from: scoreData, keys: ["calories", "calories_burned", "caloriesBurned", "energy"]) {
            metrics["calories"] = calories
        }
        
        // Strain - from score.strain
        if let strain = extractDouble(from: scoreData, keys: ["strain", "strain_score", "strainScore"]) {
            metrics["strain"] = strain
        }
        
        // Average Heart Rate - from score.average_heart_rate
        if let avgHr = extractDouble(from: scoreData, keys: ["average_heart_rate", "averageHeartRate", "avg_hr", "avgHr"]) {
            metrics["hr"] = avgHr
        }
        
        // Max Heart Rate - from score.max_heart_rate
        if let maxHr = extractDouble(from: scoreData, keys: ["max_heart_rate", "maxHeartRate", "max_hr", "maxHr"]) {
            metrics["max_hr"] = maxHr
        }
        
        // Distance - from score.distance_meter
        if let distance = extractDouble(from: scoreData, keys: ["distance_meter", "distance_meters", "distanceMeters", "distance"]) {
            metrics["distance"] = distance
        }
        
        // Altitude gain - from score.altitude_gain_meter
        if let altitudeGain = extractDouble(from: scoreData, keys: ["altitude_gain_meter", "altitudeGain"]) {
            metrics["altitude_gain"] = altitudeGain
        }
        
        // Percent recorded - from score.percent_recorded (data quality metric)
        if let percentRecorded = extractDouble(from: scoreData, keys: ["percent_recorded", "percentRecorded"]) {
            metrics["percent_recorded"] = percentRecorded
        }
        
        // Extract zone_durations for heart rate zones
        if let scoreObj = data["score"]?.value as? [String: Any],
           let zoneDurations = scoreObj["zone_durations"] as? [String: Any] {
            let zoneData = zoneDurations.mapValues { AnyCodable($0) }
            
            // Zone 0 (Rest)
            if let zoneZeroMilli = extractDouble(from: zoneData, keys: ["zone_zero_milli", "zoneZero"]) {
                metrics["hr_zone_zero_minutes"] = zoneZeroMilli / 60000.0
            }
            
            // Zone 1 (Fat Burn)
            if let zoneOneMilli = extractDouble(from: zoneData, keys: ["zone_one_milli", "zoneOne"]) {
                metrics["hr_zone_one_minutes"] = zoneOneMilli / 60000.0
            }
            
            // Zone 2 (Aerobic)
            if let zoneTwoMilli = extractDouble(from: zoneData, keys: ["zone_two_milli", "zoneTwo"]) {
                metrics["hr_zone_two_minutes"] = zoneTwoMilli / 60000.0
            }
            
            // Zone 3 (Anaerobic)
            if let zoneThreeMilli = extractDouble(from: zoneData, keys: ["zone_three_milli", "zoneThree"]) {
                metrics["hr_zone_three_minutes"] = zoneThreeMilli / 60000.0
            }
            
            // Zone 4 (VO2 Max)
            if let zoneFourMilli = extractDouble(from: zoneData, keys: ["zone_four_milli", "zoneFour"]) {
                metrics["hr_zone_four_minutes"] = zoneFourMilli / 60000.0
            }
            
            // Zone 5 (Neuromuscular Power)
            if let zoneFiveMilli = extractDouble(from: zoneData, keys: ["zone_five_milli", "zoneFive"]) {
                metrics["hr_zone_five_minutes"] = zoneFiveMilli / 60000.0
            }
        }
        
        // Workout type - from sport_name
        if let workoutType = extractString(from: data, keys: ["sport_name", "sportName", "type", "workout_type", "workoutType", "sport"]) {
            meta["workout_type"] = workoutType
        }
        
        // Sport ID
        if let sportId = extractDouble(from: data, keys: ["sport_id", "sportId"]) {
            meta["sport_id"] = String(Int(sportId))
        }
        
        // Store additional workout metadata
        if let workoutId = extractString(from: data, keys: ["id", "workout_id", "workoutId"]) {
            meta["workout_id"] = workoutId
        }
        if let scoreState = extractString(from: data, keys: ["score_state", "scoreState"]) {
            meta["score_state"] = scoreState
        }
        if let timezoneOffset = extractString(from: data, keys: ["timezone_offset", "timezoneOffset"]) {
            meta["timezone_offset"] = timezoneOffset
        }
    }
    
    /// Extract cycle-specific metrics
    private func extractCycleMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Cycle ID - store in meta
        if let cycleId = extractDouble(from: data, keys: ["cycle_id", "cycleId"]) {
            meta["cycle_id"] = String(Int(cycleId))
        }
        
        // Cycle day
        if let day = extractDouble(from: data, keys: ["day", "cycle_day", "cycleDay"]) {
            metrics["cycle_day"] = day
        }
        
        // Strain - may be in score object or at top level
        if let strain = extractDouble(from: data, keys: ["strain", "strain_score", "strainScore"]) {
            metrics["strain"] = strain
        }
        
        // Recovery - may be in score object or at top level
        if let recovery = extractDouble(from: data, keys: ["recovery", "recovery_score", "recoveryScore"]) {
            metrics["recovery_score"] = recovery
        }
        
        // Note: Cycles data structure may vary - this handles common fields
        // Actual structure depends on WHOOP API response format
    }
    
    /// Extract generic metrics (fallback)
    private func extractGenericMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Try to extract any numeric values as metrics
        for (key, value) in data {
            if let doubleValue = value.value as? Double {
                metrics[key] = doubleValue
            } else if let intValue = value.value as? Int {
                metrics[key] = Double(intValue)
            } else if let stringValue = value.value as? String {
                meta[key] = stringValue
            }
        }
    }
    
    /// Extract RR intervals from data
    private func extractRRIntervals(from data: [String: AnyCodable]) -> [Double]? {
        // Try common field names for RR intervals
        let rrKeys = ["rr_ms", "rr_intervals", "rrIntervals", "rri", "intervals"]
        
        for key in rrKeys {
            if let value = data[key]?.value {
                if let array = value as? [Double] {
                    return array
                } else if let array = value as? [Int] {
                    return array.map { Double($0) }
                } else if let array = value as? [Any] {
                    return array.compactMap { item in
                        if let double = item as? Double {
                            return double
                        } else if let int = item as? Int {
                            return Double(int)
                        }
                        return nil
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Generate a random state parameter for OAuth flow
    private func generateState() -> String {
        return UUID().uuidString
    }
    
    /// Key for storing OAuth state in UserDefaults
    private var stateKey: String {
        return "synheart_whoop_oauth_state_\(appId)"
    }
    
    /// Key for storing user ID in Keychain
    private var userIdKey: String {
        return "synheart_whoop_user_id_\(appId)"
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

