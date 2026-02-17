import Foundation

// MARK: - BLE HRM UUIDs

/// Standard Bluetooth SIG UUIDs for Heart Rate service
public enum BleHrmUUID {
    public static let heartRateService = "180D"
    public static let heartRateMeasurement = "2A37"
    public static let bodySensorLocation = "2A38"
    public static let batteryService = "180F"
    public static let batteryLevel = "2A19"
}

// MARK: - Heart Rate Sample

/// A single heart rate measurement from a BLE HRM device
public struct HeartRateSample {
    public let tsMs: Int64
    public let bpm: Int
    public let source: String
    public let deviceId: String
    public let deviceName: String?
    public let sessionId: String?
    public let rrIntervalsMs: [Double]?

    public init(
        tsMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        bpm: Int,
        source: String = "ble_hrm",
        deviceId: String,
        deviceName: String? = nil,
        sessionId: String? = nil,
        rrIntervalsMs: [Double]? = nil
    ) {
        self.tsMs = tsMs
        self.bpm = bpm
        self.source = source
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.sessionId = sessionId
        self.rrIntervalsMs = rrIntervalsMs
    }

    /// Convert to unified WearMetrics format
    public func toWearMetrics() -> WearMetrics {
        let metrics: [String: Double] = [
            MetricType.hr.rawValue: Double(bpm)
        ]

        var meta: [String: String] = [
            "source_type": source
        ]

        if let name = deviceName {
            meta["device_name"] = name
        }
        if let sid = sessionId {
            meta["session_id"] = sid
        }

        return WearMetrics(
            timestamp: Date(timeIntervalSince1970: Double(tsMs) / 1000.0),
            deviceId: deviceId,
            source: source,
            metrics: metrics,
            meta: meta,
            rrIntervals: rrIntervalsMs
        )
    }
}

// MARK: - BLE HRM Device

/// A discovered BLE heart rate monitor device
public struct BleHrmDevice {
    public let deviceId: String
    public let name: String?
    public let rssi: Int

    public init(deviceId: String, name: String?, rssi: Int) {
        self.deviceId = deviceId
        self.name = name
        self.rssi = rssi
    }
}

// MARK: - Error Codes

/// BLE HRM specific error codes matching RFC specification
public enum BleHrmErrorCode: String {
    case permissionDenied = "PERMISSION_DENIED"
    case bluetoothOff = "BLUETOOTH_OFF"
    case deviceNotFound = "DEVICE_NOT_FOUND"
    case subscribeFailed = "SUBSCRIBE_FAILED"
    case disconnected = "DISCONNECTED"
}

// MARK: - Heart Rate Parser

/// Parses BLE Heart Rate Measurement characteristic data per Bluetooth SIG spec
///
/// Flags byte (bit field):
/// - Bit 0: HR format — 0 = uint8, 1 = uint16
/// - Bit 4: RR-Interval present — 0 = no, 1 = yes
public struct HeartRateParser {

    /// Parse raw heart rate measurement data
    ///
    /// - Parameter data: Raw characteristic value from `0x2A37`
    /// - Returns: Tuple of (bpm, rrIntervalsMs) or nil values for invalid data
    public static func parse(_ data: Data) -> (bpm: Int, rrIntervalsMs: [Double]?) {
        guard data.count >= 2 else {
            return (bpm: 0, rrIntervalsMs: nil)
        }

        let flags = data[0]
        let isUint16 = (flags & 0x01) != 0
        let hasRR = (flags & 0x10) != 0

        var offset = 1
        let bpm: Int

        if isUint16 {
            guard data.count >= 3 else {
                return (bpm: 0, rrIntervalsMs: nil)
            }
            bpm = Int(data[1]) | (Int(data[2]) << 8)
            offset = 3
        } else {
            bpm = Int(data[1])
            offset = 2
        }

        // Skip Energy Expended field if present (bit 3)
        let hasEnergyExpended = (flags & 0x08) != 0
        if hasEnergyExpended {
            offset += 2
        }

        var rrIntervals: [Double]? = nil
        if hasRR && offset + 1 < data.count {
            var intervals: [Double] = []
            while offset + 1 < data.count {
                let rawRR = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                // RR values are in 1/1024 seconds, convert to milliseconds
                let rrMs = Double(rawRR) / 1024.0 * 1000.0
                intervals.append(rrMs)
                offset += 2
            }
            if !intervals.isEmpty {
                rrIntervals = intervals
            }
        }

        return (bpm: bpm, rrIntervalsMs: rrIntervals)
    }
}
