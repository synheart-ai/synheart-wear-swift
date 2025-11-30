import Foundation

/// Network client for making HTTP requests to the Wear Service
///
/// Handles all HTTP communication including GET, POST, and DELETE requests,
/// JSON encoding/decoding, error handling, and timeout management.
internal class NetworkClient {
    private let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval
    
    /// Initialize the network client
    ///
    /// - Parameters:
    ///   - baseURL: Base URL for the Wear Service API
    ///   - timeout: Request timeout in seconds (default: 30)
    init(baseURL: URL, timeout: TimeInterval = 30.0) {
        self.baseURL = baseURL
        self.timeout = timeout
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: configuration)
    }
    
    /// Perform a GET request
    ///
    /// - Parameters:
    ///   - path: API endpoint path (e.g., "/v1/whoop/oauth/authorize")
    ///   - queryParameters: Optional query parameters
    /// - Returns: Decoded response of type T
    /// - Throws: NetworkError if request fails
    func get<T: Decodable>(
        path: String,
        queryParameters: [String: String]? = nil
    ) async throws -> T {
        var url = baseURL.appendingPathComponent(path)
        
        // Add query parameters if provided
        if let queryParams = queryParameters, !queryParams.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let finalURL = components?.url {
                url = finalURL
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return try await performRequest(request: request)
    }
    
    /// Perform a POST request
    ///
    /// - Parameters:
    ///   - path: API endpoint path
    ///   - body: Encodable body to send
    ///   - queryParameters: Optional query parameters
    /// - Returns: Decoded response of type T
    /// - Throws: NetworkError if request fails
    func post<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        queryParameters: [String: String]? = nil
    ) async throws -> T {
        var url = baseURL.appendingPathComponent(path)
        
        // Add query parameters if provided
        if let queryParams = queryParameters, !queryParams.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let finalURL = components?.url {
                url = finalURL
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Encode body
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)
        
        return try await performRequest(request: request)
    }
    
    /// Perform a DELETE request
    ///
    /// - Parameters:
    ///   - path: API endpoint path
    ///   - queryParameters: Optional query parameters
    /// - Returns: Decoded response of type T
    /// - Throws: NetworkError if request fails
    func delete<T: Decodable>(
        path: String,
        queryParameters: [String: String]? = nil
    ) async throws -> T {
        var url = baseURL.appendingPathComponent(path)
        
        // Add query parameters if provided
        if let queryParams = queryParameters, !queryParams.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let finalURL = components?.url {
                url = finalURL
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return try await performRequest(request: request)
    }
    
    // MARK: - Private Methods
    
    /// Perform the actual HTTP request
    private func performRequest<T: Decodable>(request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            
            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            // Handle HTTP status codes
            switch httpResponse.statusCode {
            case 200...299:
                // Success - decode response
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                // Handle empty response body
                if data.isEmpty {
                    // Try to decode as empty dictionary or use default
                    if T.self == EmptyResponse.self {
                        return EmptyResponse() as! T
                    }
                    throw NetworkError.invalidResponse
                }
                
                // Log raw JSON response for debugging - BEFORE attempting to decode
                if let jsonString = String(data: data, encoding: .utf8) {
                    let separator = String(repeating: "=", count: 80)
                    print(separator)
                    print("[NetworkClient] RAW JSON RESPONSE (Status: \(httpResponse.statusCode)):")
                    print("[NetworkClient] URL: \(request.url?.absoluteString ?? "unknown")")
                    print("[NetworkClient] Full Response Body:")
                    print(jsonString)
                    print(separator)
                    
                    // Also try to pretty-print it if possible for easier reading
                    if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                       let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
                       let prettyString = String(data: prettyData, encoding: .utf8) {
                        print("[NetworkClient] Pretty-printed JSON:")
                        print(prettyString)
                        print(separator)
                    }
                }
                
                do {
                    return try decoder.decode(T.self, from: data)
                } catch let decodingError as DecodingError {
                    // Enhanced error logging with detailed context
                    var errorContext = "Decoding error: \(decodingError.localizedDescription)"
                    if let jsonString = String(data: data, encoding: .utf8) {
                        // Include response body in error for debugging
                        let preview = jsonString.count > 500 ? String(jsonString.prefix(500)) + "..." : jsonString
                        errorContext += "\nResponse preview: \(preview)"
                        
                        // Try to identify the specific decoding issue
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            errorContext += "\nMissing key: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                        case .typeMismatch(let type, let context):
                            errorContext += "\nType mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                        case .valueNotFound(let type, let context):
                            errorContext += "\nValue not found: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                        case .dataCorrupted(let context):
                            errorContext += "\nData corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: ".")) - \(context.debugDescription)"
                        @unknown default:
                            break
                        }
                    }
                    print("[NetworkClient] \(errorContext)")
                    throw NetworkError.decodingError(decodingError)
                } catch {
                    // Log decoding error for debugging
                    if let jsonString = String(data: data, encoding: .utf8) {
                        let preview = jsonString.count > 500 ? String(jsonString.prefix(500)) + "..." : jsonString
                        print("[NetworkClient] Failed to decode response: \(error.localizedDescription)\nResponse preview: \(preview)")
                    }
                    throw NetworkError.decodingError(error)
                }
                
            case 401:
                throw NetworkError.unauthorized
                
            case 404:
                throw NetworkError.notFound
                
            case 400...499:
                // Client error - try to decode error message
                let errorMessage = try? decodeErrorMessage(from: data)
                throw NetworkError.clientError(httpResponse.statusCode, errorMessage)
                
            case 500...599:
                // Server error
                let errorMessage = try? decodeErrorMessage(from: data)
                throw NetworkError.serverError(httpResponse.statusCode, errorMessage)
                
            default:
                throw NetworkError.unexpectedStatusCode(httpResponse.statusCode)
            }
            
        } catch let error as NetworkError {
            throw error
        } catch let urlError as URLError {
            // Handle URL errors (network issues, timeouts, etc.)
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw NetworkError.noConnection
            case .timedOut:
                throw NetworkError.timeout
            case .cannotFindHost, .cannotConnectToHost:
                throw NetworkError.hostUnreachable
            default:
                throw NetworkError.urlError(urlError)
            }
        } catch {
            throw NetworkError.unknown(error)
        }
    }
    
    /// Decode error message from response body
    private func decodeErrorMessage(from data: Data) throws -> String? {
        struct ErrorResponse: Decodable {
            let error: String?
            let message: String?
        }
        
        let decoder = JSONDecoder()
        if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
            return errorResponse.error ?? errorResponse.message
        }
        
        // Try to get any string from response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String ?? json["error"] as? String {
            return message
        }
        
        return nil
    }
}

// MARK: - Supporting Types

/// Empty response type for endpoints that return no body
internal struct EmptyResponse: Codable {
    init() {}
}

/// Network-related errors
internal enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case hostUnreachable
    case invalidResponse
    case decodingError(Error)
    case unauthorized
    case notFound
    case clientError(Int, String?)
    case serverError(Int, String?)
    case unexpectedStatusCode(Int)
    case urlError(URLError)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection available"
        case .timeout:
            return "Request timed out"
        case .hostUnreachable:
            return "Cannot reach server"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            var description = "Failed to decode response: \(error.localizedDescription)"
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    description += ". Missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                case .typeMismatch(let type, let context):
                    description += ". Type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                case .valueNotFound(let type, let context):
                    description += ". Value not found: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                case .dataCorrupted(let context):
                    description += ". Data corrupted: \(context.debugDescription)"
                @unknown default:
                    break
                }
            }
            return description
        case .unauthorized:
            return "Authentication failed. Please reconnect your account."
        case .notFound:
            return "Resource not found"
        case .clientError(let code, let message):
            return message ?? "Client error: \(code)"
        case .serverError(let code, let message):
            return message ?? "Server error: \(code)"
        case .unexpectedStatusCode(let code):
            return "Unexpected status code: \(code)"
        case .urlError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

