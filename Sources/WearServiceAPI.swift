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
    let vendor: String
    let appId: String
    let userId: String
    let records: [DataRecord]
    let cursor: String?
    
    enum CodingKeys: String, CodingKey {
        case vendor
        case appId = "app_id"
        case userId = "user_id"
        case records
        case cursor
    }
}

/// Individual data record (structure depends on data type)
internal struct DataRecord: Codable {
    // Generic structure - records are flexible dictionaries
    // The record itself is the data object (not nested under a "data" key)
    let fields: [String: AnyCodable]
    
    init(from decoder: Decoder) throws {
        // Try to decode as a direct dictionary first (most common case)
        // Records in the API response are JSON objects, so we decode them as dictionaries
        do {
            let container = try decoder.singleValueContainer()
            fields = try container.decode([String: AnyCodable].self)
        } catch {
            // Fallback: try to decode as nested structure with "data" key
            // This handles cases where records might be wrapped
            let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
            if keyedContainer.contains(.data) {
                fields = try keyedContainer.decode([String: AnyCodable].self, forKey: .data)
            } else {
                // If no "data" key, try to decode all keys as a dictionary
                var decodedFields: [String: AnyCodable] = [:]
                let allKeys = keyedContainer.allKeys
                for key in allKeys {
                    if let value = try? keyedContainer.decode(AnyCodable.self, forKey: key) {
                        decodedFields[key.stringValue] = value
                    }
                }
                fields = decodedFields
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }
    
    enum CodingKeys: String, CodingKey {
        case data
    }
}

// MARK: - Supporting Types

/// Type-erased Codable for flexible JSON decoding
internal struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            let codableArray = array.map { AnyCodable($0) }
            try container.encode(codableArray)
        case let dict as [String: Any]:
            let codableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable value cannot be encoded"
                )
            )
        }
    }
}

