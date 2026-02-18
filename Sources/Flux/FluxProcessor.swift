import Foundation

/// Stateful processor for Synheart Flux with persistent baselines
///
/// Use this when you need to maintain baselines across multiple API calls.
/// This class wraps the native Rust FluxProcessor via FFI.
///
/// Flux is optional - if the native library is not available:
/// - `isAvailable` returns false
/// - Processing methods return nil
/// - Baseline methods return nil/false
///
/// Example:
/// ```swift
/// let processor = FluxProcessor()
///
/// guard processor.isAvailable else {
///     print("Flux not available, using fallback")
///     return
/// }
///
/// // Process WHOOP data
/// if let results = processor.processWhoop(whoopJson, timezone: "America/New_York", deviceId: "device-123") {
///     // Handle results
/// }
///
/// // Save baselines for later
/// let savedBaselines = processor.saveBaselines()
///
/// // ... later ...
///
/// // Load baselines and continue processing
/// if let baselines = savedBaselines {
///     processor.loadBaselines(baselines)
/// }
/// ```
public final class FluxProcessor {

    private var handle: UnsafeMutableRawPointer?
    private let ffi = FluxFfi.shared

    /// Create a new processor with default settings (14-day baseline window)
    ///
    /// If Flux native library is not available, `isAvailable` will return false
    /// and all processing methods will return nil (graceful degradation).
    public convenience init() {
        self.init(baselineWindowDays: 14)
    }

    /// Create a processor with a specific baseline window size
    ///
    /// - Parameter baselineWindowDays: Number of days for baseline calculations
    ///
    /// If Flux native library is not available, `isAvailable` will return false
    /// and all processing methods will return nil (graceful degradation).
    public init(baselineWindowDays: Int) {
        handle = ffi.createProcessor(baselineWindowDays: baselineWindowDays)
        if handle == nil {
            print("[FluxProcessor] Native library not available, running in degraded mode")
        }
    }

    deinit {
        close()
    }

    /// Check if this processor is available (native library loaded and not closed)
    public var isAvailable: Bool {
        handle != nil
    }

    /// Check if Flux native library is available (static check)
    public static var isFluxAvailable: Bool {
        FluxFfi.shared.isAvailable
    }

    /// Get the Flux load error if any
    public static var fluxLoadError: String? {
        FluxFfi.shared.loadError
    }

    /// Load baseline state from JSON
    ///
    /// - Parameter json: Baselines JSON string (from saveBaselines)
    /// - Returns: true if successful, false if failed or Flux unavailable
    @discardableResult
    public func loadBaselines(_ json: String) -> Bool {
        guard let handle = handle else {
            print("[FluxProcessor] Cannot load baselines - not available")
            return false
        }
        return ffi.loadBaselines(handle: handle, json: json)
    }

    /// Save baseline state to JSON
    ///
    /// - Returns: Baselines JSON string or nil if Flux is not available
    public func saveBaselines() -> String? {
        guard let handle = handle else {
            print("[FluxProcessor] Cannot save baselines - not available")
            return nil
        }
        return ffi.saveBaselines(handle: handle)
    }

    /// Get current baselines as typed object
    ///
    /// - Returns: Baselines object or nil if Flux is not available
    public var currentBaselines: Baselines? {
        guard let json = saveBaselines() else { return nil }
        return try? Baselines.fromJson(json)
    }

    /// Process WHOOP payload with persistent baselines
    ///
    /// - Parameters:
    ///   - rawJson: Raw WHOOP API response JSON
    ///   - timezone: User's timezone (e.g., "America/New_York")
    ///   - deviceId: Unique device identifier
    /// - Returns: List of HSI JSON payloads, or nil if Flux is not available
    public func processWhoop(_ rawJson: String, timezone: String, deviceId: String) -> [String]? {
        guard let handle = handle else {
            print("[FluxProcessor] Cannot process WHOOP - not available")
            return nil
        }
        guard let resultJson = ffi.processWhoop(handle: handle, json: rawJson, timezone: timezone, deviceId: deviceId) else {
            return nil
        }
        return parseJsonArray(resultJson)
    }

    /// Process Garmin payload with persistent baselines
    ///
    /// - Parameters:
    ///   - rawJson: Raw Garmin API response JSON
    ///   - timezone: User's timezone (e.g., "America/Los_Angeles")
    ///   - deviceId: Unique device identifier
    /// - Returns: List of HSI JSON payloads, or nil if Flux is not available
    public func processGarmin(_ rawJson: String, timezone: String, deviceId: String) -> [String]? {
        guard let handle = handle else {
            print("[FluxProcessor] Cannot process Garmin - not available")
            return nil
        }
        guard let resultJson = ffi.processGarmin(handle: handle, json: rawJson, timezone: timezone, deviceId: deviceId) else {
            return nil
        }
        return parseJsonArray(resultJson)
    }

    /// Close and release native resources
    ///
    /// After calling close, this processor can no longer be used.
    public func close() {
        if let handle = handle {
            ffi.freeProcessor(handle)
            self.handle = nil
        }
    }

    /// Parse a JSON array string into a list of JSON strings
    private func parseJsonArray(_ jsonArrayStr: String) -> [String] {
        guard let data = jsonArrayStr.data(using: .utf8) else { return [] }

        do {
            let decoded = try JSONSerialization.jsonObject(with: data, options: [])
            if let array = decoded as? [[String: Any]] {
                return array.compactMap { item -> String? in
                    guard let itemData = try? JSONSerialization.data(withJSONObject: item, options: []) else {
                        return nil
                    }
                    return String(data: itemData, encoding: .utf8)
                }
            } else {
                // Single object, wrap in list
                return [jsonArrayStr]
            }
        } catch {
            print("[FluxProcessor] Failed to parse JSON array: \(error)")
            return []
        }
    }
}

// MARK: - Stateless Functions

/// Convert raw WHOOP JSON payload to HSI 1.0 compliant daily payloads
///
/// - Parameters:
///   - rawJson: Raw WHOOP API response JSON
///   - timezone: User's timezone (e.g., "America/New_York")
///   - deviceId: Unique device identifier
/// - Returns: List of HSI JSON payloads (one per day in the input),
///            or nil if Flux is not available (graceful degradation)
///
/// Example:
/// ```swift
/// if let hsiPayloads = whoopToHsiDaily(whoopJson, timezone: "America/New_York", deviceId: "device-123") {
///     for payload in hsiPayloads {
///         print(payload)
///     }
/// } else {
///     print("Flux not available")
/// }
/// ```
public func whoopToHsiDaily(_ rawJson: String, timezone: String, deviceId: String) -> [String]? {
    guard let resultJson = FluxFfi.shared.whoopToHsi(rawJson, timezone: timezone, deviceId: deviceId) else {
        return nil
    }
    return parseJsonArrayStatic(resultJson)
}

/// Convert raw Garmin JSON payload to HSI 1.0 compliant daily payloads
///
/// - Parameters:
///   - rawJson: Raw Garmin API response JSON
///   - timezone: User's timezone (e.g., "America/Los_Angeles")
///   - deviceId: Unique device identifier
/// - Returns: List of HSI JSON payloads (one per day in the input),
///            or nil if Flux is not available (graceful degradation)
///
/// Example:
/// ```swift
/// if let hsiPayloads = garminToHsiDaily(garminJson, timezone: "America/Los_Angeles", deviceId: "garmin-device-456") {
///     for payload in hsiPayloads {
///         print(payload)
///     }
/// } else {
///     print("Flux not available")
/// }
/// ```
public func garminToHsiDaily(_ rawJson: String, timezone: String, deviceId: String) -> [String]? {
    guard let resultJson = FluxFfi.shared.garminToHsi(rawJson, timezone: timezone, deviceId: deviceId) else {
        return nil
    }
    return parseJsonArrayStatic(resultJson)
}

/// Parse a JSON array string into a list of JSON strings
private func parseJsonArrayStatic(_ jsonArrayStr: String) -> [String] {
    guard let data = jsonArrayStr.data(using: .utf8) else { return [] }

    do {
        let decoded = try JSONSerialization.jsonObject(with: data, options: [])
        if let array = decoded as? [[String: Any]] {
            return array.compactMap { item -> String? in
                guard let itemData = try? JSONSerialization.data(withJSONObject: item, options: []) else {
                    return nil
                }
                return String(data: itemData, encoding: .utf8)
            }
        } else {
            // Single object, wrap in list
            return [jsonArrayStr]
        }
    } catch {
        print("[Flux] Failed to parse JSON array: \(error)")
        return []
    }
}
