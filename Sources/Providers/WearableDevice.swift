import Foundation

/// Connection state for wearable devices
public enum DeviceConnectionState {
    case disconnected
    case connecting
    case connected
    case failed
    case unknown
}

/// A discovered wearable device during scanning
public struct ScannedDevice: Equatable {
    /// Platform BLE identifier (UUID on iOS, MAC on Android)
    public let identifier: String

    /// Device name
    public let name: String

    /// Model name if available
    public let modelName: String?

    /// Received signal strength indicator (RSSI)
    public let rssi: Int?

    /// Whether this device is already paired
    public let isPaired: Bool

    /// Which adapter discovered this device
    public let adapter: DeviceAdapter

    /// Timestamp when device was discovered
    public let discoveredAt: Date

    public init(
        identifier: String,
        name: String,
        modelName: String? = nil,
        rssi: Int? = nil,
        isPaired: Bool = false,
        adapter: DeviceAdapter,
        discoveredAt: Date = Date()
    ) {
        self.identifier = identifier
        self.name = name
        self.modelName = modelName
        self.rssi = rssi
        self.isPaired = isPaired
        self.adapter = adapter
        self.discoveredAt = discoveredAt
    }

    public static func == (lhs: ScannedDevice, rhs: ScannedDevice) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}

/// A paired wearable device
public struct PairedDevice: Equatable {
    /// Adapter-specific device ID (e.g., Garmin unitId as string)
    public let deviceId: String

    /// Platform BLE identifier
    public let identifier: String

    /// Device name
    public let name: String

    /// Model name if available
    public let modelName: String?

    /// Current connection state
    public let connectionState: DeviceConnectionState

    /// Battery level (0-100)
    public let batteryLevel: Int?

    /// Last sync timestamp
    public let lastSyncTime: Date?

    /// Whether the device supports real-time streaming
    public let supportsStreaming: Bool

    /// Which adapter manages this device
    public let adapter: DeviceAdapter

    public init(
        deviceId: String,
        identifier: String,
        name: String,
        modelName: String? = nil,
        connectionState: DeviceConnectionState = .disconnected,
        batteryLevel: Int? = nil,
        lastSyncTime: Date? = nil,
        supportsStreaming: Bool = false,
        adapter: DeviceAdapter
    ) {
        self.deviceId = deviceId
        self.identifier = identifier
        self.name = name
        self.modelName = modelName
        self.connectionState = connectionState
        self.batteryLevel = batteryLevel
        self.lastSyncTime = lastSyncTime
        self.supportsStreaming = supportsStreaming
        self.adapter = adapter
    }

    /// Whether the device is currently connected
    public var isConnected: Bool {
        return connectionState == .connected
    }

    public static func == (lhs: PairedDevice, rhs: PairedDevice) -> Bool {
        return lhs.deviceId == rhs.deviceId
    }
}

/// Connection state change event
public struct DeviceConnectionEvent {
    /// The current connection state
    public let state: DeviceConnectionState

    /// The device ID if applicable
    public let deviceId: String?

    /// Error message if state is failed
    public let error: String?

    /// Timestamp of the event
    public let timestamp: Date

    public init(
        state: DeviceConnectionState,
        deviceId: String? = nil,
        error: String? = nil,
        timestamp: Date = Date()
    ) {
        self.state = state
        self.deviceId = deviceId
        self.error = error
        self.timestamp = timestamp
    }
}
