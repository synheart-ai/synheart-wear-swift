import Foundation
import HealthKit

/// Device adapter types
public enum DeviceAdapter {
    case appleHealthKit
    case fitbit
    case garmin
    case whoop
}

/// Permission types for biometric data access
public enum PermissionType: CaseIterable {
    case heartRate
    case hrv
    case steps
    case calories
    case distance
    case exercise
    case sleep
    case stress

    /// Convert to HealthKit type
    func toHealthKitType() -> HKObjectType? {
        switch self {
        case .heartRate:
            return HKQuantityType.quantityType(forIdentifier: .heartRate)
        case .hrv:
            return HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .steps:
            return HKQuantityType.quantityType(forIdentifier: .stepCount)
        case .calories:
            return HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        case .distance:
            return HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        case .exercise:
            return HKObjectType.workoutType()
        case .sleep:
            return HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        case .stress:
            return nil // Not directly available in HealthKit
        }
    }
}

/// Metric types available from wearable devices
public enum MetricType: String, CaseIterable {
    case hr = "hr"
    case hrvRmssd = "hrv_rmssd"
    case hrvSdnn = "hrv_sdnn"
    case steps = "steps"
    case calories = "calories"
    case distance = "distance"
    case stress = "stress"
    case battery = "battery"
    case firmwareVersion = "firmware_version"
}

/// Unified biometric data structure following Synheart Data Schema v1.0
public struct WearMetrics: Codable {
    public let timestamp: Date
    public let deviceId: String
    public let source: String
    public let metrics: [String: Double]
    public let meta: [String: String]
    public let rrIntervals: [Double]?

    public init(
        timestamp: Date,
        deviceId: String,
        source: String,
        metrics: [String: Double],
        meta: [String: String] = [:],
        rrIntervals: [Double]? = nil
    ) {
        self.timestamp = timestamp
        self.deviceId = deviceId
        self.source = source
        self.metrics = metrics
        self.meta = meta
        self.rrIntervals = rrIntervals
    }

    /// Get a specific metric value
    ///
    /// - Parameter type: Metric type to retrieve
    /// - Returns: Metric value or nil if not available
    public func getMetric(_ type: MetricType) -> Double? {
        return metrics[type.rawValue]
    }

    /// Check if a metric is available
    ///
    /// - Parameter type: Metric type to check
    /// - Returns: True if metric is available
    public func hasMetric(_ type: MetricType) -> Bool {
        return metrics[type.rawValue] != nil
    }

    /// Convert to dictionary
    public func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "device_id": deviceId,
            "source": source,
            "metrics": metrics,
            "meta": meta
        ]

        if let intervals = rrIntervals {
            dict["rr_intervals"] = intervals
        }

        return dict
    }
}

/// Builder for WearMetrics
public class WearMetricsBuilder {
    private var timestamp: Date = Date()
    private var deviceId: String = "unknown"
    private var source: String = "unknown"
    private var metrics: [String: Double] = [:]
    private var meta: [String: String] = [:]
    private var rrIntervals: [Double]?

    public init() {}

    @discardableResult
    public func timestamp(_ value: Date) -> Self {
        self.timestamp = value
        return self
    }

    @discardableResult
    public func deviceId(_ value: String) -> Self {
        self.deviceId = value
        return self
    }

    @discardableResult
    public func source(_ value: String) -> Self {
        self.source = value
        return self
    }

    @discardableResult
    public func metric(_ type: MetricType, value: Double) -> Self {
        metrics[type.rawValue] = value
        return self
    }

    @discardableResult
    public func metrics(_ values: [MetricType: Double]) -> Self {
        for (type, value) in values {
            metrics[type.rawValue] = value
        }
        return self
    }

    @discardableResult
    public func metaData(key: String, value: String) -> Self {
        meta[key] = value
        return self
    }

    @discardableResult
    public func rrIntervals(_ intervals: [Double]) -> Self {
        self.rrIntervals = intervals
        return self
    }

    public func build() -> WearMetrics {
        return WearMetrics(
            timestamp: timestamp,
            deviceId: deviceId,
            source: source,
            metrics: metrics,
            meta: meta,
            rrIntervals: rrIntervals
        )
    }
}

/// Configuration for SynheartWear SDK
public struct SynheartWearConfig {
    public let enabledAdapters: Set<DeviceAdapter>
    public let enableLocalCaching: Bool
    public let enableEncryption: Bool
    public let streamInterval: TimeInterval
    public let maxCacheSize: Int64
    public let maxCacheAge: TimeInterval

    // Wear Service configuration
    public let baseUrl: URL?
    public let appId: String?
    public let redirectUri: String?

    // Flux configuration
    /// Whether to enable Flux (HSI processing) - requires native library
    public let enableFlux: Bool
    /// Number of days for Flux baseline calculations (default: 14)
    public let fluxBaselineWindowDays: Int

    public init(
        enabledAdapters: Set<DeviceAdapter> = [.appleHealthKit],
        enableLocalCaching: Bool = true,
        enableEncryption: Bool = true,
        streamInterval: TimeInterval = 3.0,
        maxCacheSize: Int64 = 100 * 1024 * 1024, // 100 MB
        maxCacheAge: TimeInterval = 30 * 24 * 60 * 60, // 30 days
        baseUrl: URL? = nil,
        appId: String? = nil,
        redirectUri: String? = nil,
        enableFlux: Bool = false,
        fluxBaselineWindowDays: Int = 14
    ) {
        self.enabledAdapters = enabledAdapters
        self.enableLocalCaching = enableLocalCaching
        self.enableEncryption = enableEncryption
        self.streamInterval = streamInterval
        self.maxCacheSize = maxCacheSize
        self.maxCacheAge = maxCacheAge
        self.baseUrl = baseUrl
        self.appId = appId
        self.redirectUri = redirectUri
        self.enableFlux = enableFlux
        self.fluxBaselineWindowDays = fluxBaselineWindowDays
    }
}
