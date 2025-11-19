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
        self.baseUrl = baseUrl ?? URL(string: "https://synheart-wear-service-leatest.onrender.com")!
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
            
            #if canImport(UIKit)
            await MainActor.run {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            }
            #elseif canImport(AppKit)
            // macOS: Use NSWorkspace
            NSWorkspace.shared.open(url)
            #else
            // Fallback for other platforms
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
            
            // Validate response
            guard !response.records.isEmpty else {
                return [] // Empty response is valid
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "cycle")
            
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
    
    // MARK: - Private Methods
    
    /// Convert DataResponse from API to array of WearMetrics
    ///
    /// - Parameters:
    ///   - response: DataResponse from Wear Service API
    ///   - dataType: Type of data (recovery, sleep, workout, cycle)
    /// - Returns: Array of WearMetrics
    private func convertDataResponseToMetrics(_ response: DataResponse, dataType: String) -> [WearMetrics] {
        return response.records.compactMap { record in
            convertDataRecordToMetrics(record, dataType: dataType, vendor: response.vendor, userId: response.userId)
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
        // Try common timestamp field names
        let timestampKeys = ["timestamp", "created_at", "start_time", "end_time", "date", "time"]
        
        for key in timestampKeys {
            if let value = data[key]?.value {
                if let stringValue = value as? String {
                    // Try ISO8601 format
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
    
    /// Extract recovery-specific metrics
    private func extractRecoveryMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Recovery score
        if let score = extractDouble(from: data, keys: ["score", "recovery_score", "recoveryScore"]) {
            metrics["recovery_score"] = score
        }
        
        // HRV metrics
        if let hrv = extractDouble(from: data, keys: ["hrv", "hrv_rmssd", "hrvRmssd", "rmssd"]) {
            metrics["hrv_rmssd"] = hrv
        }
        if let sdnn = extractDouble(from: data, keys: ["hrv_sdnn", "hrvSdnn", "sdnn"]) {
            metrics["hrv_sdnn"] = sdnn
        }
        
        // Heart rate
        if let hr = extractDouble(from: data, keys: ["hr", "heart_rate", "heartRate", "resting_heart_rate", "restingHeartRate"]) {
            metrics["hr"] = hr
        }
        
        // RHR (Resting Heart Rate)
        if let rhr = extractDouble(from: data, keys: ["rhr", "resting_hr", "restingHr"]) {
            metrics["rhr"] = rhr
        }
        
        // Strain
        if let strain = extractDouble(from: data, keys: ["strain", "strain_score", "strainScore"]) {
            metrics["strain"] = strain
        }
    }
    
    /// Extract sleep-specific metrics
    private func extractSleepMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Sleep duration (in seconds, convert to hours for consistency)
        if let duration = extractDouble(from: data, keys: ["duration", "sleep_duration", "sleepDuration", "total_sleep_time", "totalSleepTime"]) {
            metrics["sleep_duration_hours"] = duration / 3600.0
        }
        
        // Sleep efficiency
        if let efficiency = extractDouble(from: data, keys: ["efficiency", "sleep_efficiency", "sleepEfficiency"]) {
            metrics["sleep_efficiency"] = efficiency
        }
        
        // Sleep score
        if let score = extractDouble(from: data, keys: ["score", "sleep_score", "sleepScore"]) {
            metrics["sleep_score"] = score
        }
        
        // Stages
        if let rem = extractDouble(from: data, keys: ["rem", "rem_duration", "remDuration"]) {
            metrics["rem_duration_minutes"] = rem / 60.0
        }
        if let deep = extractDouble(from: data, keys: ["deep", "deep_duration", "deepDuration", "slow_wave", "slowWave"]) {
            metrics["deep_duration_minutes"] = deep / 60.0
        }
        if let light = extractDouble(from: data, keys: ["light", "light_duration", "lightDuration"]) {
            metrics["light_duration_minutes"] = light / 60.0
        }
    }
    
    /// Extract workout-specific metrics
    private func extractWorkoutMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Duration
        if let duration = extractDouble(from: data, keys: ["duration", "workout_duration", "workoutDuration"]) {
            metrics["workout_duration_minutes"] = duration / 60.0
        }
        
        // Calories
        if let calories = extractDouble(from: data, keys: ["calories", "calories_burned", "caloriesBurned", "energy"]) {
            metrics["calories"] = calories
        }
        
        // Heart rate
        if let avgHr = extractDouble(from: data, keys: ["avg_hr", "avgHr", "average_heart_rate", "averageHeartRate"]) {
            metrics["hr"] = avgHr
        }
        if let maxHr = extractDouble(from: data, keys: ["max_hr", "maxHr", "max_heart_rate", "maxHeartRate"]) {
            metrics["max_hr"] = maxHr
        }
        
        // Distance
        if let distance = extractDouble(from: data, keys: ["distance", "distance_meters", "distanceMeters"]) {
            metrics["distance"] = distance
        }
        
        // Workout type
        if let workoutType = extractString(from: data, keys: ["type", "workout_type", "workoutType", "sport"]) {
            meta["workout_type"] = workoutType
        }
    }
    
    /// Extract cycle-specific metrics
    private func extractCycleMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Cycle day
        if let day = extractDouble(from: data, keys: ["day", "cycle_day", "cycleDay"]) {
            metrics["cycle_day"] = day
        }
        
        // Strain
        if let strain = extractDouble(from: data, keys: ["strain", "strain_score", "strainScore"]) {
            metrics["strain"] = strain
        }
        
        // Recovery
        if let recovery = extractDouble(from: data, keys: ["recovery", "recovery_score", "recoveryScore"]) {
            metrics["recovery_score"] = recovery
        }
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
        let rrKeys = ["rr_intervals", "rrIntervals", "rri", "intervals"]
        
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

