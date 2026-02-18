import Foundation

// MARK: - Vendor Types

/// Supported wearable vendors for Flux processing
public enum Vendor: String, Codable {
    case whoop
    case garmin
}

// MARK: - HSI 1.0 Core Types

/// HSI 1.0 compliant payload
///
/// This is the top-level structure for HSI output containing all metadata,
/// windows, sources, axes, and privacy information.
public struct HsiPayload: Codable {
    public let hsiVersion: String
    public let observedAtUtc: String
    public let computedAtUtc: String
    public let producer: HsiProducer
    public let windowIds: [String]
    public let windows: [String: HsiWindow]
    public let sourceIds: [String]
    public let sources: [String: HsiSource]
    public let axes: HsiAxes
    public let privacy: HsiPrivacy
    public let meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case hsiVersion = "hsi_version"
        case observedAtUtc = "observed_at_utc"
        case computedAtUtc = "computed_at_utc"
        case producer
        case windowIds = "window_ids"
        case windows
        case sourceIds = "source_ids"
        case sources
        case axes
        case privacy
        case meta
    }

    public init(
        hsiVersion: String = "1.0",
        observedAtUtc: String,
        computedAtUtc: String,
        producer: HsiProducer,
        windowIds: [String],
        windows: [String: HsiWindow],
        sourceIds: [String],
        sources: [String: HsiSource],
        axes: HsiAxes,
        privacy: HsiPrivacy,
        meta: [String: AnyCodable]? = nil
    ) {
        self.hsiVersion = hsiVersion
        self.observedAtUtc = observedAtUtc
        self.computedAtUtc = computedAtUtc
        self.producer = producer
        self.windowIds = windowIds
        self.windows = windows
        self.sourceIds = sourceIds
        self.sources = sources
        self.axes = axes
        self.privacy = privacy
        self.meta = meta
    }

    /// Parse from JSON string
    public static func fromJson(_ jsonString: String) throws -> HsiPayload {
        let decoder = JSONDecoder()
        guard let data = jsonString.data(using: .utf8) else {
            throw FluxError.invalidJson("Failed to convert string to data")
        }
        return try decoder.decode(HsiPayload.self, from: data)
    }

    /// Convert to JSON string
    public func toJson() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(self)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw FluxError.invalidJson("Failed to convert data to string")
        }
        return jsonString
    }
}

/// HSI producer metadata
public struct HsiProducer: Codable {
    public let name: String
    public let version: String
    public let instanceId: String

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case instanceId = "instance_id"
    }

    public init(name: String, version: String, instanceId: String) {
        self.name = name
        self.version = version
        self.instanceId = instanceId
    }
}

/// HSI time window
public struct HsiWindow: Codable {
    public let start: String
    public let end: String
    public let label: String?

    public init(start: String, end: String, label: String? = nil) {
        self.start = start
        self.end = end
        self.label = label
    }
}

/// HSI source type
public enum HsiSourceType: String, Codable {
    case sensor
    case app
    case selfReport = "self_report"
    case observer
    case derived
    case other
}

/// HSI data source
public struct HsiSource: Codable {
    public let type: HsiSourceType
    public let quality: Double
    public let degraded: Bool

    public init(type: HsiSourceType, quality: Double, degraded: Bool) {
        self.type = type
        self.quality = quality
        self.degraded = degraded
    }
}

/// HSI direction indicator
public enum HsiDirection: String, Codable {
    case higherIsMore = "higher_is_more"
    case higherIsLess = "higher_is_less"
    case bidirectional
}

/// HSI axis reading
public struct HsiAxisReading: Codable {
    public let axis: String
    public let score: Double
    public let confidence: Double
    public let windowId: String
    public let direction: HsiDirection
    public let unit: String?
    public let evidenceSourceIds: [String]?
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case axis
        case score
        case confidence
        case windowId = "window_id"
        case direction
        case unit
        case evidenceSourceIds = "evidence_source_ids"
        case notes
    }

    public init(
        axis: String,
        score: Double,
        confidence: Double,
        windowId: String,
        direction: HsiDirection,
        unit: String? = nil,
        evidenceSourceIds: [String]? = nil,
        notes: String? = nil
    ) {
        self.axis = axis
        self.score = score
        self.confidence = confidence
        self.windowId = windowId
        self.direction = direction
        self.unit = unit
        self.evidenceSourceIds = evidenceSourceIds
        self.notes = notes
    }
}

/// HSI axes domain (contains readings for a category)
public struct HsiAxesDomain: Codable {
    public let readings: [HsiAxisReading]

    public init(readings: [HsiAxisReading] = []) {
        self.readings = readings
    }
}

/// HSI axes (all domains)
public struct HsiAxes: Codable {
    public let affect: HsiAxesDomain?
    public let engagement: HsiAxesDomain?
    public let behavior: HsiAxesDomain?

    public init(
        affect: HsiAxesDomain? = nil,
        engagement: HsiAxesDomain? = nil,
        behavior: HsiAxesDomain? = nil
    ) {
        self.affect = affect
        self.engagement = engagement
        self.behavior = behavior
    }
}

/// HSI privacy settings
public struct HsiPrivacy: Codable {
    public let containsPii: Bool
    public let rawBiosignalsAllowed: Bool
    public let derivedMetricsAllowed: Bool
    public let purposes: [String]?
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case containsPii = "contains_pii"
        case rawBiosignalsAllowed = "raw_biosignals_allowed"
        case derivedMetricsAllowed = "derived_metrics_allowed"
        case purposes
        case notes
    }

    public init(
        containsPii: Bool = false,
        rawBiosignalsAllowed: Bool = false,
        derivedMetricsAllowed: Bool = true,
        purposes: [String]? = nil,
        notes: String? = nil
    ) {
        self.containsPii = containsPii
        self.rawBiosignalsAllowed = rawBiosignalsAllowed
        self.derivedMetricsAllowed = derivedMetricsAllowed
        self.purposes = purposes
        self.notes = notes
    }
}

// MARK: - Baselines Types

/// Flux baseline state
///
/// Contains rolling baseline values computed from historical data
public struct Baselines: Codable {
    public let hrvBaselineMs: Double?
    public let rhrBaselineBpm: Int?
    public let sleepBaselineMinutes: Int?
    public let sleepEfficiencyBaseline: Double?
    public let baselineDays: Int

    enum CodingKeys: String, CodingKey {
        case hrvBaselineMs = "hrv_baseline_ms"
        case rhrBaselineBpm = "rhr_baseline_bpm"
        case sleepBaselineMinutes = "sleep_baseline_minutes"
        case sleepEfficiencyBaseline = "sleep_efficiency_baseline"
        case baselineDays = "baseline_days"
    }

    public init(
        hrvBaselineMs: Double? = nil,
        rhrBaselineBpm: Int? = nil,
        sleepBaselineMinutes: Int? = nil,
        sleepEfficiencyBaseline: Double? = nil,
        baselineDays: Int = 0
    ) {
        self.hrvBaselineMs = hrvBaselineMs
        self.rhrBaselineBpm = rhrBaselineBpm
        self.sleepBaselineMinutes = sleepBaselineMinutes
        self.sleepEfficiencyBaseline = sleepEfficiencyBaseline
        self.baselineDays = baselineDays
    }

    /// Parse from JSON string
    public static func fromJson(_ jsonString: String) throws -> Baselines {
        let decoder = JSONDecoder()
        guard let data = jsonString.data(using: .utf8) else {
            throw FluxError.invalidJson("Failed to convert string to data")
        }
        return try decoder.decode(Baselines.self, from: data)
    }

    /// Convert to JSON string
    public func toJson() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(self)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw FluxError.invalidJson("Failed to convert data to string")
        }
        return jsonString
    }
}

// MARK: - Flux Errors

/// Errors from Flux operations
public enum FluxError: LocalizedError {
    case notAvailable(String?)
    case processingFailed(String?)
    case invalidJson(String)
    case disabled

    public var errorDescription: String? {
        switch self {
        case .notAvailable(let reason):
            return "Flux native library not available\(reason.map { ": \($0)" } ?? "")"
        case .processingFailed(let reason):
            return "Flux processing failed\(reason.map { ": \($0)" } ?? "")"
        case .invalidJson(let message):
            return "Invalid JSON: \(message)"
        case .disabled:
            return "Flux is not enabled. Set enableFlux=true in SynheartWearConfig."
        }
    }

    public var code: String {
        switch self {
        case .notAvailable: return "FLUX_NOT_AVAILABLE"
        case .processingFailed: return "FLUX_PROCESSING_FAILED"
        case .invalidJson: return "FLUX_INVALID_JSON"
        case .disabled: return "FLUX_DISABLED"
        }
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper for dynamic JSON values
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode AnyCodable"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unable to encode AnyCodable"
                )
            )
        }
    }
}
