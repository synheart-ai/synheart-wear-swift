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
        self.baseUrl = baseUrl ?? URL(string: "https://api.wear.synheart.io")!
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
    ///
    /// - Throws: SynheartWearError if disconnection fails
    public func disconnect() async throws {
        guard let userId = userId else {
            throw SynheartWearError.notConnected
        }
        
        do {
            _ = try await api.disconnect(userId: userId, appId: appId)
            
            // Clear stored user ID
            self.userId = nil
            clearUserId()
            
        } catch let error as NetworkError {
            throw convertNetworkError(error)
        } catch {
            throw SynheartWearError.apiError(error.localizedDescription)
        }
    }
    
    // MARK: - Data Fetching Methods (Stubs - to be implemented in Phase 4)
    
    /// Fetch recovery data from WHOOP
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of recovery records
    /// - Throws: SynheartWearError if fetch fails
    public func fetchRecovery(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        // TODO: Implement in Phase 4
        throw SynheartWearError.notConnected
    }
    
    /// Fetch sleep data from WHOOP
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of sleep records
    /// - Throws: SynheartWearError if fetch fails
    public func fetchSleep(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        // TODO: Implement in Phase 4
        throw SynheartWearError.notConnected
    }
    
    /// Fetch workout data from WHOOP
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of workout records
    /// - Throws: SynheartWearError if fetch fails
    public func fetchWorkouts(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        // TODO: Implement in Phase 4
        throw SynheartWearError.notConnected
    }
    
    /// Fetch cycle data from WHOOP
    ///
    /// - Parameters:
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Array of cycle records
    /// - Throws: SynheartWearError if fetch fails
    public func fetchCycles(
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> [WearMetrics] {
        // TODO: Implement in Phase 4
        throw SynheartWearError.notConnected
    }
    
    // MARK: - Private Methods
    
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

