import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Garmin wearable device provider
///
/// Handles OAuth connection and data fetching from Garmin devices
/// via the Wear Service backend.
public class GarminProvider: WearableProvider {
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
            let response = try await api.getGarminAuthorizationURL(
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
            let response = try await api.exchangeGarminCode(
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
            _ = try await api.disconnectGarmin(userId: userId, appId: appId)
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
    
    /// Fetch daily summary data from Garmin
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
    /// - Returns: Array of daily summary records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    ///   - `.notConnected` if user hasn't connected
    ///   - `.tokenExpired` if token expired and refresh failed (user needs to reconnect)
    ///   - Network errors for connection issues
    public func fetchDailies(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminDailies(
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
            
            let metrics = convertDataResponseToMetrics(response, dataType: "dailies")
            
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
    
    /// Fetch sleep data from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of sleep records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchSleeps(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminSleeps(
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
    
    /// Fetch HRV data from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of HRV records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchHRV(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminHRV(
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
            
            let metrics = convertDataResponseToMetrics(response, dataType: "hrv")
            
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
    
    /// Fetch stress details from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of stress records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchStressDetails(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminStressDetails(
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
            
            let metrics = convertDataResponseToMetrics(response, dataType: "stress")
            
            // Validate converted metrics - filter out any invalid ones
            let validMetrics = metrics.filter { metric in
                metric.timestamp.timeIntervalSince1970 > 0
            }
            
            // If we had records but no valid metrics, log a warning
            if !response.records.isEmpty && validMetrics.isEmpty {
                print("[GarminProvider] Warning: Received \(response.records.count) stress record(s) but none could be converted to valid metrics. This may indicate a data format issue.")
            }
            
            return validMetrics
        } catch let error as NetworkError {
            // Convert network errors with better context
            let convertedError = convertNetworkError(error)
            print("[GarminProvider] fetchStressDetails failed: \(convertedError.errorDescription ?? "Unknown error")")
            throw convertedError
        } catch let error as SynheartWearError {
            print("[GarminProvider] fetchStressDetails failed: \(error.errorDescription ?? "Unknown error")")
            throw error
        } catch {
            let errorMessage = "Unexpected error in fetchStressDetails: \(error.localizedDescription)"
            print("[GarminProvider] \(errorMessage)")
            throw SynheartWearError.apiError(errorMessage)
        }
    }
    
    /// Fetch pulse ox (SpO2) data from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of pulse ox records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchPulseOx(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminPulseOx(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            guard !response.records.isEmpty else {
                return []
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "pulseox")
            
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
    
    /// Fetch respiration data from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of respiration records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchRespiration(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminRespiration(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            guard !response.records.isEmpty else {
                return []
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "respiration")
            
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
    
    /// Fetch blood pressure data from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of blood pressure records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchBloodPressures(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminBloodPressures(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            guard !response.records.isEmpty else {
                return []
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "bloodpressure")
            
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
    
    /// Fetch body composition data from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of body composition records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchBodyComps(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminBodyComps(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            guard !response.records.isEmpty else {
                return []
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "bodycomp")
            
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
    
    /// Fetch epoch (activity summary) data from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of epoch records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchEpochs(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminEpochs(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            guard !response.records.isEmpty else {
                return []
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "epochs")
            
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
    
    /// Fetch health snapshot data from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of health snapshot records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchHealthSnapshot(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminHealthSnapshot(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            guard !response.records.isEmpty else {
                return []
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "healthsnapshot")
            
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
    
    /// Fetch skin temperature data from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of skin temperature records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchSkinTemp(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminSkinTemp(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            guard !response.records.isEmpty else {
                return []
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "skintemp")
            
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
    
    /// Fetch user metrics (VO2 max, fitness age, etc.) data from Garmin
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of user metrics records as WearMetrics
    /// - Throws: SynheartWearError if fetch fails
    public func fetchUserMetrics(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            let response = try await api.fetchGarminUserMetrics(
                userId: userId,
                appId: appId,
                start: start,
                end: end,
                limit: limit,
                cursor: cursor
            )
            
            guard !response.records.isEmpty else {
                return []
            }
            
            let metrics = convertDataResponseToMetrics(response, dataType: "usermetrics")
            
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
    ///   - dataType: Type of data (dailies, sleep, hrv, stress, etc.)
    /// - Returns: Array of WearMetrics
    private func convertDataResponseToMetrics(_ response: DataResponse, dataType: String) -> [WearMetrics] {
        // Use vendor from response or fallback to "garmin"
        let vendor = response.vendor ?? "garmin"
        return response.records.compactMap { record in
            convertDataRecordToMetrics(record, dataType: dataType, vendor: vendor, userId: response.userId)
        }
    }
    
    /// Convert a single DataRecord to WearMetrics
    ///
    /// - Parameters:
    ///   - record: DataRecord from API
    ///   - dataType: Type of data (dailies, sleep, hrv, stress, etc.)
    ///   - vendor: Vendor name (e.g., "garmin")
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
        case "dailies":
            extractDailiesMetrics(from: data, into: &metrics, meta: &meta)
        case "sleep":
            extractSleepMetrics(from: data, into: &metrics, meta: &meta)
        case "hrv":
            extractHRVMetrics(from: data, into: &metrics, meta: &meta)
        case "stress":
            extractStressMetrics(from: data, into: &metrics, meta: &meta)
        case "pulseox":
            extractPulseOxMetrics(from: data, into: &metrics, meta: &meta)
        case "respiration":
            extractRespirationMetrics(from: data, into: &metrics, meta: &meta)
        case "bloodpressure":
            extractBloodPressureMetrics(from: data, into: &metrics, meta: &meta)
        case "bodycomp":
            extractBodyCompMetrics(from: data, into: &metrics, meta: &meta)
        case "epochs":
            extractEpochsMetrics(from: data, into: &metrics, meta: &meta)
        case "healthsnapshot":
            extractHealthSnapshotMetrics(from: data, into: &metrics, meta: &meta)
        case "skintemp":
            extractSkinTempMetrics(from: data, into: &metrics, meta: &meta)
        case "usermetrics":
            extractUserMetricsMetrics(from: data, into: &metrics, meta: &meta)
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
            rrIntervals: nil
        )
    }
    
    /// Extract timestamp from data record
    private func extractTimestamp(from data: [String: AnyCodable]) -> Date? {
        // Try common timestamp field names
        let timestampKeys = ["calendarDate", "summaryId", "startTimeInSeconds", "timestamp", "date", "time"]
        
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
                    // Try simple date format (YYYY-MM-DD)
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    if let date = dateFormatter.date(from: stringValue) {
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
    
    /// Extract dailies-specific metrics
    private func extractDailiesMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Steps
        if let steps = extractDouble(from: data, keys: ["steps", "totalSteps"]) {
            metrics["steps"] = steps
        }
        
        // Calories
        if let calories = extractDouble(from: data, keys: ["activeKilocalories", "calories", "totalCalories"]) {
            metrics["calories"] = calories
        }
        
        // Distance
        if let distance = extractDouble(from: data, keys: ["distanceInMeters", "distance"]) {
            metrics["distance"] = distance
        }
        
        // Heart rate
        if let minHR = extractDouble(from: data, keys: ["minHeartRateInBeatsPerMinute", "minHR"]) {
            metrics["min_hr"] = minHR
        }
        if let maxHR = extractDouble(from: data, keys: ["maxHeartRateInBeatsPerMinute", "maxHR"]) {
            metrics["max_hr"] = maxHR
        }
        if let restingHR = extractDouble(from: data, keys: ["restingHeartRateInBeatsPerMinute", "rhr"]) {
            metrics["rhr"] = restingHR
            metrics["hr"] = restingHR  // Also set as hr for consistency
        }
        
        // Stress
        if let avgStress = extractDouble(from: data, keys: ["averageStressLevel", "avgStress"]) {
            metrics["stress"] = avgStress
        }
        if let maxStress = extractDouble(from: data, keys: ["maxStressLevel", "maxStress"]) {
            metrics["max_stress"] = maxStress
        }
        
        // Store calendar date
        if let calendarDate = extractString(from: data, keys: ["calendarDate"]) {
            meta["calendar_date"] = calendarDate
        }
    }
    
    /// Extract sleep-specific metrics
    private func extractSleepMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Sleep duration
        if let durationSeconds = extractDouble(from: data, keys: ["durationInSeconds", "duration"]) {
            metrics["sleep_duration_hours"] = durationSeconds / 3600.0
        }
        
        // Sleep stages
        if let deepSleep = extractDouble(from: data, keys: ["deepSleepDurationInSeconds"]) {
            metrics["deep_duration_minutes"] = deepSleep / 60.0
        }
        if let lightSleep = extractDouble(from: data, keys: ["lightSleepDurationInSeconds"]) {
            metrics["light_duration_minutes"] = lightSleep / 60.0
        }
        if let remSleep = extractDouble(from: data, keys: ["remSleepInSeconds"]) {
            metrics["rem_duration_minutes"] = remSleep / 60.0
        }
        if let awakeDuration = extractDouble(from: data, keys: ["awakeDurationInSeconds"]) {
            metrics["awake_duration_minutes"] = awakeDuration / 60.0
        }
        
        // Average metrics
        if let avgRespiration = extractDouble(from: data, keys: ["averageRespirationValue", "avgRespiration"]) {
            metrics["respiratory_rate"] = avgRespiration
        }
        if let avgSpO2 = extractDouble(from: data, keys: ["averageSpO2Value", "avgSpO2"]) {
            metrics["spo2"] = avgSpO2
        }
        
        // Store sleep metadata
        if let summaryId = extractString(from: data, keys: ["summaryId", "sleepId"]) {
            meta["sleep_id"] = summaryId
        }
    }
    
    /// Extract HRV-specific metrics
    private func extractHRVMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // HRV values
        if let hrvValue = extractDouble(from: data, keys: ["hrvValue", "lastNightAvg"]) {
            metrics["hrv_rmssd"] = hrvValue / 1000.0  // Convert ms to seconds if needed
        }
        
        // HRV baseline
        if let baseline = extractDouble(from: data, keys: ["baselineLowUpper", "baseline"]) {
            metrics["hrv_baseline"] = baseline
        }
        
        // HRV status
        if let status = extractString(from: data, keys: ["hrvStatus"]) {
            meta["hrv_status"] = status
        }
    }
    
    /// Extract stress-specific metrics
    private func extractStressMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Stress level
        if let stressLevel = extractDouble(from: data, keys: ["stressLevel", "stress"]) {
            metrics["stress"] = stressLevel
        }
        
        // Body battery
        if let bodyBattery = extractDouble(from: data, keys: ["bodyBatteryValue", "bodyBattery"]) {
            metrics["body_battery"] = bodyBattery
        }
    }
    
    /// Extract pulse ox-specific metrics
    private func extractPulseOxMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // SpO2 value
        if let spo2 = extractDouble(from: data, keys: ["spo2Value", "spo2"]) {
            metrics["spo2"] = spo2
        }
    }
    
    /// Extract respiration-specific metrics
    private func extractRespirationMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Respiration rate
        if let respRate = extractDouble(from: data, keys: ["respirationValue", "respiration"]) {
            metrics["respiratory_rate"] = respRate
        }
    }
    
    /// Extract blood pressure-specific metrics
    private func extractBloodPressureMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Systolic blood pressure
        if let systolic = extractDouble(from: data, keys: ["systolic", "systolicBloodPressure"]) {
            metrics["systolic_bp"] = systolic
        }
        
        // Diastolic blood pressure
        if let diastolic = extractDouble(from: data, keys: ["diastolic", "diastolicBloodPressure"]) {
            metrics["diastolic_bp"] = diastolic
        }
        
        // Pulse (heart rate during measurement)
        if let pulse = extractDouble(from: data, keys: ["pulse", "pulseRate"]) {
            metrics["hr"] = pulse
        }
        
        // Source type (manual vs device)
        if let sourceType = extractString(from: data, keys: ["sourceType", "measurementSource"]) {
            meta["source_type"] = sourceType
        }
    }
    
    /// Extract body composition-specific metrics
    private func extractBodyCompMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Weight
        if let weight = extractDouble(from: data, keys: ["weight", "weightInGrams"]) {
            metrics["weight_kg"] = weight / 1000.0  // Convert grams to kg
        }
        
        // Body Mass Index
        if let bmi = extractDouble(from: data, keys: ["bmi", "bodyMassIndex"]) {
            metrics["bmi"] = bmi
        }
        
        // Body fat percentage
        if let bodyFat = extractDouble(from: data, keys: ["bodyFat", "bodyFatPercentage"]) {
            metrics["body_fat_percent"] = bodyFat
        }
        
        // Muscle mass
        if let muscleMass = extractDouble(from: data, keys: ["muscleMass", "muscleMassInGrams"]) {
            metrics["muscle_mass_kg"] = muscleMass / 1000.0  // Convert grams to kg
        }
        
        // Bone mass
        if let boneMass = extractDouble(from: data, keys: ["boneMass", "boneMassInGrams"]) {
            metrics["bone_mass_kg"] = boneMass / 1000.0  // Convert grams to kg
        }
        
        // Body water percentage
        if let bodyWater = extractDouble(from: data, keys: ["bodyWater", "bodyWaterPercentage"]) {
            metrics["body_water_percent"] = bodyWater
        }
    }
    
    /// Extract epochs (activity summary)-specific metrics
    private func extractEpochsMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Steps
        if let steps = extractDouble(from: data, keys: ["steps", "totalSteps"]) {
            metrics["steps"] = steps
        }
        
        // Active calories
        if let activeCalories = extractDouble(from: data, keys: ["activeKilocalories", "activeCalories"]) {
            metrics["active_calories"] = activeCalories
        }
        
        // Met value (metabolic equivalent)
        if let met = extractDouble(from: data, keys: ["met", "metValue"]) {
            metrics["met"] = met
        }
        
        // Intensity level
        if let intensity = extractDouble(from: data, keys: ["intensity", "intensityLevel"]) {
            metrics["intensity"] = intensity
        }
        
        // Duration in seconds
        if let duration = extractDouble(from: data, keys: ["duration", "durationInSeconds"]) {
            metrics["duration_minutes"] = duration / 60.0
        }
        
        // Activity type
        if let activityType = extractString(from: data, keys: ["activityType"]) {
            meta["activity_type"] = activityType
        }
    }
    
    /// Extract health snapshot-specific metrics
    private func extractHealthSnapshotMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Heart rate
        if let hr = extractDouble(from: data, keys: ["heartRate", "avgHeartRate"]) {
            metrics["hr"] = hr
        }
        
        // Respiration rate
        if let respRate = extractDouble(from: data, keys: ["respirationRate", "avgRespirationRate"]) {
            metrics["respiratory_rate"] = respRate
        }
        
        // SpO2
        if let spo2 = extractDouble(from: data, keys: ["spo2", "avgSpO2"]) {
            metrics["spo2"] = spo2
        }
        
        // Stress level
        if let stress = extractDouble(from: data, keys: ["stressLevel", "avgStress"]) {
            metrics["stress"] = stress
        }
        
        // Snapshot type
        if let snapshotType = extractString(from: data, keys: ["snapshotType"]) {
            meta["snapshot_type"] = snapshotType
        }
    }
    
    /// Extract skin temperature-specific metrics
    private func extractSkinTempMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // Skin temperature in Celsius
        if let skinTemp = extractDouble(from: data, keys: ["skinTempCelsius", "skinTemperature", "temperature"]) {
            metrics["skin_temp_celsius"] = skinTemp
        }
        
        // Skin temperature in Fahrenheit
        if let skinTempF = extractDouble(from: data, keys: ["skinTempFahrenheit"]) {
            metrics["skin_temp_fahrenheit"] = skinTempF
        }
    }
    
    /// Extract user metrics (VO2 max, fitness age, etc.)-specific metrics
    private func extractUserMetricsMetrics(from data: [String: AnyCodable], into metrics: inout [String: Double], meta: inout [String: String]) {
        // VO2 Max
        if let vo2max = extractDouble(from: data, keys: ["vo2Max", "vo2MaxValue"]) {
            metrics["vo2_max"] = vo2max
        }
        
        // Fitness age
        if let fitnessAge = extractDouble(from: data, keys: ["fitnessAge"]) {
            metrics["fitness_age"] = fitnessAge
        }
        
        // Lactate threshold
        if let lactateThreshold = extractDouble(from: data, keys: ["lactateThreshold", "lactateThresholdValue"]) {
            metrics["lactate_threshold"] = lactateThreshold
        }
        
        // FTP (Functional Threshold Power)
        if let ftp = extractDouble(from: data, keys: ["ftp", "functionalThresholdPower"]) {
            metrics["ftp"] = ftp
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

