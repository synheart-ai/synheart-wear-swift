import Foundation
import HealthKit
import Combine

/// Main SynheartWear SDK class implementing RFC specifications
///
/// Provides unified access to biometric data from wearable devices
/// with standardized output format, encryption, and privacy controls.
public class SynheartWear {
    private var initialized = false
    private let config: SynheartWearConfig
    private let normalizer = Normalizer()
    private let consentManager: ConsentManager
    private let localCache: LocalCache
    private let healthStore = HKHealthStore()

    private var streamCancellables = Set<AnyCancellable>()
    
    // Wear Service providers
    private var whoopProvider: WhoopProvider?

    /// Initialize SynheartWear with configuration
    ///
    /// - Parameter config: SDK configuration
    public init(config: SynheartWearConfig = SynheartWearConfig()) {
        self.config = config
        self.consentManager = ConsentManager()
        self.localCache = LocalCache(enableEncryption: config.enableEncryption)
        
        // Initialize providers if configuration is provided
        if let appId = config.appId {
            let baseUrl = config.baseUrl ?? URL(string: "https://api.wear.synheart.io")!
            let redirectUri = config.redirectUri ?? "synheart://oauth/callback"
            
            if config.enabledAdapters.contains(.whoop) {
                self.whoopProvider = WhoopProvider(
                    appId: appId,
                    baseUrl: baseUrl,
                    redirectUri: redirectUri
                )
            }
        }
    }
    
    /// Get a wearable provider by adapter type
    ///
    /// - Parameter adapter: Device adapter type
    /// - Returns: Provider instance if available and configured, nil otherwise
    /// - Throws: SynheartWearError if provider is not configured
    public func getProvider(_ adapter: DeviceAdapter) throws -> WearableProvider {
        switch adapter {
        case .whoop:
            guard let provider = whoopProvider else {
                throw SynheartWearError.apiError("WHOOP provider not configured. Please provide appId in SynheartWearConfig.")
            }
            return provider
        case .appleHealthKit, .fitbit, .garmin:
            throw SynheartWearError.apiError("Provider for \(adapter) not yet implemented.")
        }
    }

    /// Initialize the SDK with permissions and setup
    ///
    /// This must be called before any other SDK methods.
    /// Requests necessary HealthKit permissions.
    ///
    /// - Throws: SynheartWearError if initialization fails
    public func initialize() async throws {
        if initialized { return }

        guard HKHealthStore.isHealthDataAvailable() else {
            throw SynheartWearError.healthKitNotAvailable
        }

        try await consentManager.initialize()

        initialized = true
    }

    /// Request specific permissions from the user
    ///
    /// - Parameter permissions: Set of permission types to request
    /// - Returns: Dictionary mapping permission types to granted status
    /// - Throws: SynheartWearError if permissions cannot be requested
    public func requestPermissions(_ permissions: Set<PermissionType>) async throws -> [PermissionType: Bool] {
        try ensureInitialized()

        let healthKitTypes = permissions.compactMap { $0.toHealthKitType() }
        let readTypes = Set(healthKitTypes)

        if #available(iOS 15.0, *) {
            try await healthStore.requestAuthorization(
                toShare: Set<HKSampleType>(),
                read: readTypes
            )
        } else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.requestAuthorization(
                    toShare: Set<HKSampleType>(),
                    read: readTypes
                ) { success, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard success else {
                        continuation.resume(throwing: SynheartWearError.permissionDenied)
                        return
                    }

                    continuation.resume()
                }
            }
        }

        var results: [PermissionType: Bool] = [:]
        for permission in permissions {
            if let hkType = permission.toHealthKitType() {
                let status = healthStore.authorizationStatus(for: hkType)
                results[permission] = status == .sharingAuthorized
            }
        }

        return results
    }

    /// Get current permission status
    ///
    /// - Returns: Dictionary mapping permission types to granted status
    public func getPermissionStatus() -> [PermissionType: Bool] {
        var status: [PermissionType: Bool] = [:]

        for permission in PermissionType.allCases {
            if let hkType = permission.toHealthKitType() {
                status[permission] = healthStore.authorizationStatus(for: hkType) == .sharingAuthorized
            }
        }

        return status
    }

    /// Read current biometric metrics
    ///
    /// Reads metrics from all available sources (HealthKit and connected cloud providers)
    /// and merges them into a unified WearMetrics object.
    ///
    /// - Parameter isRealTime: Whether to read real-time data or historical snapshot
    /// - Returns: Unified WearMetrics containing all available biometric data from all sources
    /// - Throws: SynheartWearError if metrics cannot be read
    public func readMetrics(isRealTime: Bool = false) async throws -> WearMetrics {
        try ensureInitialized()

        var allMetrics: [WearMetrics] = []

        // Read from HealthKit if enabled
        if config.enabledAdapters.contains(.appleHealthKit) {
            do {
                let heartRate = try await readHeartRate(isRealTime: isRealTime)
                let steps = try await readSteps()

                let healthKitMetrics = WearMetrics(
                    timestamp: Date(),
                    deviceId: "applewatch_\(UUID().uuidString.prefix(8))",
                    source: "apple_healthkit",
                    metrics: [
                        "hr": heartRate,
                        "steps": steps
                    ],
                    meta: [
                        "synced": "true"
                    ],
                    rrIntervals: nil
                )
                allMetrics.append(healthKitMetrics)
            } catch {
                // Log but don't fail - continue with other sources
                print("Warning: Failed to read HealthKit metrics: \(error)")
            }
        }

        // Read from WHOOP if connected
        if config.enabledAdapters.contains(.whoop),
           let whoopProvider = whoopProvider,
           whoopProvider.isConnected() {
            do {
                // Fetch latest recovery data (most recent record)
                let recoveryData = try await whoopProvider.fetchRecovery(
                    start: Date().addingTimeInterval(-24 * 60 * 60), // Last 24 hours
                    end: Date(),
                    limit: 1
                )
                
                if let latestRecovery = recoveryData.first {
                    allMetrics.append(latestRecovery)
                }
            } catch SynheartWearError.tokenExpired {
                // Token expired - mark provider as disconnected but continue
                print("Warning: WHOOP token expired. User needs to reconnect.")
                // Clear the connection state
                try? await whoopProvider.disconnect()
            } catch SynheartWearError.notConnected {
                // Already disconnected - just continue
            } catch {
                // Other errors (network, etc.) - log but don't fail
                print("Warning: Failed to read WHOOP metrics: \(error)")
            }
        }

        // Merge all metrics from different sources
        let mergedMetrics: WearMetrics
        if allMetrics.isEmpty {
            // No data available from any source
            mergedMetrics = WearMetrics(
                timestamp: Date(),
                deviceId: "unknown",
                source: "none",
                metrics: [:],
                meta: ["error": "No data sources available"],
                rrIntervals: nil
            )
        } else if allMetrics.count == 1 {
            // Only one source available
            mergedMetrics = allMetrics[0]
        } else {
            // Multiple sources - merge them
            mergedMetrics = normalizer.mergeSnapshots(allMetrics)
        }

        // Cache if enabled
        if config.enableLocalCaching {
            try await localCache.storeSession(mergedMetrics)
        }

        return mergedMetrics
    }
    
    /// Read metrics from a specific provider
    ///
    /// Fetches data from a specific wearable provider (e.g., WHOOP) without merging
    /// with other sources. Useful for provider-specific data or historical queries.
    ///
    /// - Parameters:
    ///   - adapter: Device adapter type (e.g., .whoop)
    ///   - start: Start date for data range (optional)
    ///   - end: End date for data range (optional)
    ///   - limit: Maximum number of records (optional)
    /// - Returns: Array of WearMetrics from the specified provider
    /// - Throws: SynheartWearError if provider is not configured or fetch fails
    public func readMetricsFromProvider(
        _ adapter: DeviceAdapter,
        start: Date? = nil,
        end: Date? = nil,
        limit: Int? = nil
    ) async throws -> [WearMetrics] {
        try ensureInitialized()
        
        switch adapter {
        case .whoop:
            guard let whoopProvider = whoopProvider else {
                throw SynheartWearError.apiError("WHOOP provider not configured. Please provide appId in SynheartWearConfig.")
            }
            guard whoopProvider.isConnected() else {
                throw SynheartWearError.notConnected
            }
            return try await whoopProvider.fetchRecovery(start: start, end: end, limit: limit)
        case .appleHealthKit:
            // For HealthKit, return current metrics
            let metrics = try await readMetrics()
            return [metrics]
        case .fitbit, .garmin:
            throw SynheartWearError.apiError("Provider for \(adapter) not yet implemented.")
        }
    }

    /// Stream real-time heart rate data
    ///
    /// - Parameter interval: Polling interval in seconds
    /// - Returns: Publisher of WearMetrics with updated HR data
    public func streamHR(interval: TimeInterval = 3.0) -> AnyPublisher<WearMetrics, Error> {
        let timerPublisher = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
        
        return createMetricsPublisher(from: timerPublisher)
    }

    /// Stream HRV data in configurable windows
    ///
    /// - Parameter window: Window size in seconds for HRV calculation
    /// - Returns: Publisher of WearMetrics with updated HRV data
    public func streamHRV(window: TimeInterval = 5.0) -> AnyPublisher<WearMetrics, Error> {
        let timerPublisher = Timer.publish(every: window, on: .main, in: .common)
            .autoconnect()
        
        return createMetricsPublisher(from: timerPublisher)
    }

    /// Stream HR data using AsyncStream (modern Swift concurrency)
    ///
    /// - Parameter interval: Polling interval in seconds
    /// - Returns: AsyncStream of WearMetrics
    public func streamHRAsync(interval: TimeInterval = 3.0) -> AsyncStream<WearMetrics> {
        AsyncStream { continuation in
            Task {
                while !Task.isCancelled {
                    do {
                        let metrics = try await readMetrics(isRealTime: true)
                        continuation.yield(metrics)
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    } catch {
                        continuation.finish()
                        break
                    }
                }
            }
        }
    }

    /// Get cached biometric sessions
    ///
    /// - Parameters:
    ///   - startDate: Start date for query
    ///   - endDate: End date for query (defaults to now)
    ///   - limit: Maximum number of sessions to return
    /// - Returns: Array of cached WearMetrics
    /// - Throws: SynheartWearError if cache cannot be accessed
    public func getCachedSessions(
        startDate: Date,
        endDate: Date = Date(),
        limit: Int = 100
    ) async throws -> [WearMetrics] {
        try ensureInitialized()
        return try await localCache.getSessions(startDate: startDate, endDate: endDate, limit: limit)
    }

    /// Get cache statistics
    ///
    /// - Returns: Dictionary containing cache statistics
    /// - Throws: SynheartWearError if cache cannot be accessed
    public func getCacheStats() async throws -> [String: Any] {
        try ensureInitialized()
        return try await localCache.getStats()
    }

    /// Clear old cached data
    ///
    /// - Parameter maxAge: Maximum age of data to keep in seconds
    /// - Throws: SynheartWearError if cache cannot be cleared
    public func clearOldCache(maxAge: TimeInterval = 30 * 24 * 60 * 60) async throws {
        try ensureInitialized()
        try await localCache.clearOldData(maxAge: maxAge)
    }

    /// Purge all cached data (GDPR compliance)
    ///
    /// - Throws: SynheartWearError if data cannot be purged
    public func purgeAllData() async throws {
        try ensureInitialized()
        try await localCache.purgeAll()
        try await consentManager.revokeAllConsents()
    }

    // MARK: - Private Methods

    private func createMetricsPublisher(from publisher: Publishers.Autoconnect<Timer.TimerPublisher>) -> AnyPublisher<WearMetrics, Error> {
        if #available(iOS 14.0, *) {
            return createMetricsPublisherModern(from: publisher)
        } else {
            return createMetricsPublisherLegacy(from: publisher)
        }
    }

    private func makeMetricsTransform() -> (Date) -> AnyPublisher<WearMetrics, Error> {
        { [weak self] _ in
            guard let self = self else {
                return Fail(error: SynheartWearError.notInitialized)
                    .eraseToAnyPublisher()
            }
            return Future { promise in
                Task {
                    do {
                        let metrics = try await self.readMetrics(isRealTime: true)
                        promise(.success(metrics))
                    } catch {
                        promise(.failure(error))
                    }
                }
            }
            .eraseToAnyPublisher()
        }
    }

    @available(iOS 14.0, *)
    private func createMetricsPublisherModern(from publisher: Publishers.Autoconnect<Timer.TimerPublisher>) -> AnyPublisher<WearMetrics, Error> {
        let transform = makeMetricsTransform()
        return publisher
            .flatMap(maxPublishers: .unlimited, transform)
            .eraseToAnyPublisher()
    }

    private func createMetricsPublisherLegacy(from publisher: Publishers.Autoconnect<Timer.TimerPublisher>) -> AnyPublisher<WearMetrics, Error> {
        let transform = makeMetricsTransform()
        return publisher
            .setFailureType(to: Error.self)
            .map(transform)
            .switchToLatest()
            .eraseToAnyPublisher()
    }

    private func ensureInitialized() throws {
        guard initialized else {
            throw SynheartWearError.notInitialized
        }
    }

    private func readHeartRate(isRealTime: Bool) async throws -> Double {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw SynheartWearError.healthKitTypeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(isRealTime ? -60 : -3600),
            end: Date(),
            options: .strictEndDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(throwing: SynheartWearError.invalidData)
                    return
                }
                
                let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
                let heartRate = sample.quantity.doubleValue(for: heartRateUnit)
                continuation.resume(returning: heartRate)
            }
            
            healthStore.execute(query)
        }
    }

    private func readSteps() async throws -> Double {
        guard let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw SynheartWearError.healthKitTypeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-24 * 60 * 60), // Last 24 hours
            end: Date(),
            options: .strictEndDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: 0.0)
                    return
                }
                
                let steps = sum.doubleValue(for: HKUnit.count())
                continuation.resume(returning: steps)
            }
            
            healthStore.execute(query)
        }
    }
}

/// Errors thrown by SynheartWear SDK
public enum SynheartWearError: LocalizedError {
    case notInitialized
    case healthKitNotAvailable
    case healthKitTypeNotAvailable
    case permissionDenied
    case invalidData
    case cacheError(String)
    
    // Network errors
    case noConnection
    case timeout
    case hostUnreachable
    case invalidResponse
    
    // Authentication errors
    case notConnected
    case authenticationFailed
    case tokenExpired
    
    // API errors
    case apiError(String)
    case rateLimitExceeded
    case serverError(Int, String?)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "SDK not initialized. Call initialize() first."
        case .healthKitNotAvailable:
            return "HealthKit is not available on this device."
        case .healthKitTypeNotAvailable:
            return "Requested HealthKit data type is not available."
        case .permissionDenied:
            return "Permission denied for requested health data."
        case .invalidData:
            return "Invalid data received from HealthKit."
        case .cacheError(let message):
            return "Cache error: \(message)"
        case .noConnection:
            return "No internet connection available. Please check your network settings."
        case .timeout:
            return "Request timed out. Please try again."
        case .hostUnreachable:
            return "Cannot reach server. Please check your internet connection."
        case .notConnected:
            return "Account not connected. Please connect your wearable device first."
        case .authenticationFailed:
            return "Authentication failed. Please reconnect your account."
        case .tokenExpired:
            return "Session expired. Please reconnect your account."
        case .invalidResponse:
            return "Invalid response from server."
        case .apiError(let message):
            return "API error: \(message)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .serverError(let code, let message):
            return message ?? "Server error: \(code). Please try again later."
        }
    }
}

// MARK: - Network Error Conversion

/// Convert internal NetworkError to public SynheartWearError
internal func convertNetworkError(_ error: NetworkError) -> SynheartWearError {
    switch error {
    case .noConnection:
        return .noConnection
    case .timeout:
        return .timeout
    case .hostUnreachable:
        return .hostUnreachable
    case .unauthorized:
        // 401 Unauthorized typically means token expired
        // The Wear Service should handle refresh automatically, but if it fails,
        // the user needs to reconnect
        return .tokenExpired
    case .invalidResponse, .decodingError:
        return .invalidResponse
    case .clientError(let code, let message):
        // 401 is already handled above, but check for other auth-related codes
        if code == 401 {
            return .tokenExpired
        } else if code == 403 {
            return .authenticationFailed
        } else if code == 429 {
            return .rateLimitExceeded
        }
        return .apiError(message ?? "Unknown API error")
    case .serverError(let code, let message):
        return .serverError(code, message)
    case .notFound:
        return .notConnected
    default:
        return .apiError(error.errorDescription ?? "Network error occurred")
    }
}
