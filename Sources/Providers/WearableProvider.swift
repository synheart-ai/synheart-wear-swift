import Foundation

/// Protocol defining the interface for all wearable device providers
///
/// All wearable providers (WHOOP, Garmin, Fitbit, etc.) must implement this protocol
/// to ensure consistent interface across different vendors.
public protocol WearableProvider {
    /// The vendor/device type this provider supports
    var vendor: DeviceAdapter { get }
    
    /// Check if a user account is currently connected
    ///
    /// - Returns: True if connected, false otherwise
    func isConnected() -> Bool
    
    /// Get the connected user ID
    ///
    /// - Returns: User ID if connected, nil otherwise
    func getUserId() -> String?
    
    /// Connect the user's account (initiates OAuth flow)
    ///
    /// This method will:
    /// 1. Get authorization URL from Wear Service
    /// 2. Open browser for user to authorize
    /// 3. Return - user must handle deep link callback separately
    ///
    /// - Throws: SynheartWearError if connection fails
    func connect() async throws
    
    /// Complete the OAuth connection with authorization code
    ///
    /// This method should be called when the app receives the OAuth callback
    /// via deep link with the authorization code.
    ///
    /// - Parameters:
    ///   - code: Authorization code from OAuth callback
    ///   - state: State parameter from OAuth callback (for CSRF protection)
    ///   - redirectUri: The redirect URI that was used in the authorization request
    /// - Throws: SynheartWearError if connection fails
    func connectWithCode(code: String, state: String, redirectUri: String) async throws
    
    /// Disconnect the user's account
    ///
    /// Removes the connection and clears stored credentials.
    ///
    /// - Throws: SynheartWearError if disconnection fails
    func disconnect() async throws
}

