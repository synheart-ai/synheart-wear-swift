import Foundation

/// API models and endpoints for the Wear Service
///
/// Defines all request/response models and endpoint paths for communicating
/// with the Wear Service backend.
internal struct WearServiceAPI {
    let networkClient: NetworkClient
    
    /// Initialize with base URL
    init(baseURL: URL) {
        self.networkClient = NetworkClient(baseURL: baseURL)
    }
    
    // MARK: - OAuth Endpoints
    
    /// Get OAuth authorization URL
    ///
    /// - Parameters:
    ///   - redirectUri: Deep link URI for OAuth callback
    ///   - state: State parameter for CSRF protection
    ///   - appId: Application ID
    ///   - userId: Optional user ID (defaults to state if not provided)
    /// - Returns: Authorization URL response
    func getAuthorizationURL(
        redirectUri: String,
        state: String,
        appId: String,
        userId: String? = nil
    ) async throws -> AuthorizationURLResponse {
        var queryParams: [String: String] = [
            "redirect_uri": redirectUri,
            "state": state,
            "app_id": appId
        ]
        
        if let userId = userId {
            queryParams["user_id"] = userId
        }
        
        return try await networkClient.get(
            path: "/v1/whoop/oauth/authorize",
            queryParameters: queryParams
        )
    }
    
    /// Exchange authorization code for access token
    ///
    /// - Parameters:
    ///   - code: Authorization code from OAuth callback
    ///   - state: State parameter from OAuth callback
    ///   - redirectUri: Redirect URI used in authorization
    /// - Returns: OAuth callback response with user_id
    func exchangeCode(
        code: String,
        state: String,
        redirectUri: String
    ) async throws -> OAuthCallbackResponse {
        let body = OAuthCallbackRequest(
            code: code,
            state: state,
            redirectUri: redirectUri
        )
        
        return try await networkClient.post(
            path: "/v1/whoop/oauth/callback",
            body: body
        )
    }
    
    /// Disconnect user account
    ///
    /// - Parameters:
    ///   - userId: User ID to disconnect
    ///   - appId: Application ID
    func disconnect(userId: String, appId: String) async throws -> DisconnectResponse {
        let queryParams: [String: String] = [
            "user_id": userId,
            "app_id": appId
        ]
        
        return try await networkClient.delete(
            path: "/v1/whoop/oauth/disconnect",
            queryParameters: queryParams
        )
    }
    
    // MARK: - Data Endpoints
    
    /// Fetch recovery data
    ///
    /// - Parameters:
    ///   - userId: User ID
    ///   - appId: Application ID
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Recovery data response
    func fetchRecovery(
        userId: String,
        appId: String,
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> DataResponse {
        var queryParams: [String: String] = [
            "app_id": appId
        ]
        
        if let start = start {
            let formatter = ISO8601DateFormatter()
            queryParams["start"] = formatter.string(from: start)
        }
        
        if let end = end {
            let formatter = ISO8601DateFormatter()
            queryParams["end"] = formatter.string(from: end)
        }
        
        if let limit = limit {
            queryParams["limit"] = String(limit)
        }
        
        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }
        
        return try await networkClient.get(
            path: "/v1/whoop/data/\(userId)/recovery",
            queryParameters: queryParams
        )
    }
    
    /// Fetch sleep data
    ///
    /// - Parameters:
    ///   - userId: User ID
    ///   - appId: Application ID
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Sleep data response
    func fetchSleep(
        userId: String,
        appId: String,
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> DataResponse {
        var queryParams: [String: String] = [
            "app_id": appId
        ]
        
        if let start = start {
            let formatter = ISO8601DateFormatter()
            queryParams["start"] = formatter.string(from: start)
        }
        
        if let end = end {
            let formatter = ISO8601DateFormatter()
            queryParams["end"] = formatter.string(from: end)
        }
        
        if let limit = limit {
            queryParams["limit"] = String(limit)
        }
        
        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }
        
        return try await networkClient.get(
            path: "/v1/whoop/data/\(userId)/sleep",
            queryParameters: queryParams
        )
    }
    
    /// Fetch workout data
    ///
    /// - Parameters:
    ///   - userId: User ID
    ///   - appId: Application ID
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Workout data response
    func fetchWorkouts(
        userId: String,
        appId: String,
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> DataResponse {
        var queryParams: [String: String] = [
            "app_id": appId
        ]
        
        if let start = start {
            let formatter = ISO8601DateFormatter()
            queryParams["start"] = formatter.string(from: start)
        }
        
        if let end = end {
            let formatter = ISO8601DateFormatter()
            queryParams["end"] = formatter.string(from: end)
        }
        
        if let limit = limit {
            queryParams["limit"] = String(limit)
        }
        
        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }
        
        return try await networkClient.get(
            path: "/v1/whoop/data/\(userId)/workouts",
            queryParameters: queryParams
        )
    }
    
    /// Fetch cycle data
    ///
    /// - Parameters:
    ///   - userId: User ID
    ///   - appId: Application ID
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    ///   - limit: Maximum number of records (optional, default: 100)
    ///   - cursor: Pagination cursor (optional)
    /// - Returns: Cycle data response
    func fetchCycles(
        userId: String,
        appId: String,
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> DataResponse {
        var queryParams: [String: String] = [
            "app_id": appId
        ]

        if let start = start {
            let formatter = ISO8601DateFormatter()
            queryParams["start"] = formatter.string(from: start)
        }

        if let end = end {
            let formatter = ISO8601DateFormatter()
            queryParams["end"] = formatter.string(from: end)
        }

        if let limit = limit {
            queryParams["limit"] = String(limit)
        }

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        return try await networkClient.get(
            path: "/v1/whoop/data/\(userId)/cycles",
            queryParameters: queryParams
        )
    }

    // MARK: - Garmin OAuth Endpoints

    /// Get Garmin OAuth authorization URL
    ///
    /// The service handles PKCE code_verifier/challenge generation.
    /// After user authorizes, Garmin redirects to service HTTPS URL,
    /// then service redirects to app's deep link with success/error.
    ///
    /// - Parameters:
    ///   - redirectUri: Deep link URI for OAuth callback
    ///   - state: State parameter for CSRF protection
    ///   - appId: Application ID
    ///   - userId: Optional user ID (for re-authorization)
    /// - Returns: Authorization URL response
    func getGarminAuthorizationURL(
        redirectUri: String,
        state: String,
        appId: String,
        userId: String? = nil
    ) async throws -> AuthorizationURLResponse {
        var queryParams: [String: String] = [
            "redirect_uri": redirectUri,
            "state": state,
            "app_id": appId
        ]

        if let userId = userId {
            queryParams["user_id"] = userId
        }

        return try await networkClient.get(
            path: "/v1/garmin/oauth/authorize",
            queryParameters: queryParams
        )
    }

    /// Exchange Garmin authorization code for access token
    ///
    /// Note: For Garmin, the service handles the intermediate redirect
    /// and token exchange. This is called by the service internally,
    /// but exposed for completeness.
    ///
    /// - Parameters:
    ///   - code: Authorization code from Garmin callback
    ///   - state: State parameter from callback
    ///   - redirectUri: Redirect URI used in authorization
    /// - Returns: OAuth callback response with user_id
    func exchangeGarminCode(
        code: String,
        state: String,
        redirectUri: String
    ) async throws -> OAuthCallbackResponse {
        let body = OAuthCallbackRequest(
            code: code,
            state: state,
            redirectUri: redirectUri
        )

        return try await networkClient.post(
            path: "/v1/garmin/oauth/callback",
            body: body
        )
    }

    /// Disconnect Garmin user account
    ///
    /// This also calls Garmin's DELETE /user/registration API
    /// to deregister the user from receiving webhook data.
    ///
    /// - Parameters:
    ///   - userId: User ID to disconnect
    ///   - appId: Application ID
    func disconnectGarmin(userId: String, appId: String) async throws -> DisconnectResponse {
        let queryParams: [String: String] = [
            "user_id": userId,
            "app_id": appId
        ]

        return try await networkClient.delete(
            path: "/v1/garmin/oauth/disconnect",
            queryParameters: queryParams
        )
    }

    // MARK: - Garmin Data Endpoints

    /// Fetch Garmin data by summary type
    ///
    /// - Parameters:
    ///   - userId: User ID
    ///   - summaryType: Garmin summary type (e.g., "dailies", "sleeps", "hrv")
    ///   - appId: Application ID
    ///   - start: Start date (optional)
    ///   - end: End date (optional)
    /// - Returns: Data response with Garmin records
    func fetchGarminData(
        userId: String,
        summaryType: String,
        appId: String,
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> DataResponse {
        var queryParams: [String: String] = [
            "app_id": appId
        ]

        if let start = start {
            let formatter = ISO8601DateFormatter()
            queryParams["start"] = formatter.string(from: start)
        }

        if let end = end {
            let formatter = ISO8601DateFormatter()
            queryParams["end"] = formatter.string(from: end)
        }

        return try await networkClient.get(
            path: "/v1/garmin/data/\(userId)/\(summaryType)",
            queryParameters: queryParams
        )
    }

    /// Request Garmin historical data backfill
    ///
    /// Garmin uses webhook-based data delivery, so historical data
    /// must be requested via the backfill API. Data is delivered
    /// asynchronously via webhooks.
    ///
    /// - Parameters:
    ///   - userId: User ID
    ///   - summaryType: Garmin summary type to backfill
    ///   - appId: Application ID
    ///   - start: Start of date range (max 90 days from end)
    ///   - end: End of date range
    /// - Returns: Backfill response
    func requestGarminBackfill(
        userId: String,
        summaryType: String,
        appId: String,
        start: Date,
        end: Date
    ) async throws -> GarminBackfillResponse {
        let formatter = ISO8601DateFormatter()
        let body = GarminBackfillRequest(
            appId: appId,
            start: formatter.string(from: start),
            end: formatter.string(from: end)
        )

        return try await networkClient.post(
            path: "/v1/garmin/data/\(userId)/backfill/\(summaryType)",
            body: body
        )
    }

    /// Get Garmin webhook URLs
    ///
    /// Returns webhook endpoint URLs that should be configured
    /// in the Garmin Developer Portal.
    ///
    /// - Parameter appId: Application ID
    /// - Returns: Webhook URLs response
    func getGarminWebhookUrls(
        appId: String
    ) async throws -> GarminWebhookUrlsResponse {
        let queryParams: [String: String] = [
            "app_id": appId
        ]

        return try await networkClient.get(
            path: "/v1/garmin/webhooks",
            queryParameters: queryParams
        )
    }
}

// MARK: - Request Models

/// OAuth callback request
internal struct OAuthCallbackRequest: Codable {
    let code: String
    let state: String
    let redirectUri: String
    
    enum CodingKeys: String, CodingKey {
        case code
        case state
        case redirectUri = "redirect_uri"
    }
}

// MARK: - Response Models

/// Authorization URL response
internal struct AuthorizationURLResponse: Codable {
    let authorizationUrl: String
    
    enum CodingKeys: String, CodingKey {
        case authorizationUrl = "authorization_url"
    }
}

/// OAuth callback response
internal struct OAuthCallbackResponse: Codable {
    let status: String
    let userId: String
    
    enum CodingKeys: String, CodingKey {
        case status
        case userId = "user_id"
    }
}

/// Disconnect response
internal struct DisconnectResponse: Codable {
    let status: String
}

/// Generic data response from Wear Service
internal struct DataResponse: Codable {
    let vendor: String?
    let appId: String
    let userId: String
    let records: [DataRecord]
    let cursor: String?
    let organizationId: String?  // Optional field that may be present in some responses
    
    enum CodingKeys: String, CodingKey {
        case vendor
        case appId = "app_id"
        case userId = "user_id"
        case records
        case cursor
        case organizationId = "organization_id"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode required fields
        appId = try container.decode(String.self, forKey: .appId)
        userId = try container.decode(String.self, forKey: .userId)
        
        // Decode records - standard field name is "records"
        // Try standard "records" first
        do {
            records = try container.decode([DataRecord].self, forKey: .records)
        } catch {
            // If "records" fails, provide a detailed error message
            let availableKeys = container.allKeys.map { $0.stringValue }.joined(separator: ", ")
            throw DecodingError.keyNotFound(
                CodingKeys.records,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Failed to decode 'records' field. Available keys: \(availableKeys). Error: \(error.localizedDescription)"
                )
            )
        }
        
        // Decode optional fields
        vendor = try container.decodeIfPresent(String.self, forKey: .vendor)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(vendor, forKey: .vendor)
        try container.encode(appId, forKey: .appId)
        try container.encode(userId, forKey: .userId)
        try container.encode(records, forKey: .records)
        try container.encodeIfPresent(cursor, forKey: .cursor)
        try container.encodeIfPresent(organizationId, forKey: .organizationId)
    }
}

/// Individual data record (structure depends on data type)
internal struct DataRecord: Codable {
    // Generic structure - records are flexible dictionaries
    // The record itself is the data object (not nested under a "data" key)
    let fields: [String: AnyCodable]
    
    init(from decoder: Decoder) throws {
        // Strategy 1: Try to decode as a direct dictionary (most common case)
        // Records in the API response are JSON objects, so we decode them as dictionaries
        let container = try decoder.singleValueContainer()
        fields = try container.decode([String: AnyCodable].self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }
}

// MARK: - Garmin Request/Response Models

/// Garmin backfill request
internal struct GarminBackfillRequest: Codable {
    let appId: String
    let start: String
    let end: String

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case start
        case end
    }
}

/// Garmin backfill response
internal struct GarminBackfillResponse: Codable {
    let status: String
}

/// Garmin webhook URLs response
internal struct GarminWebhookUrlsResponse: Codable {
    let endpoints: [String: String]
}

