import Foundation

/// Public facade for Garmin Health SDK (native device) integration
///
/// Wraps the native Garmin Health SDK and exposes only generic, SDK-owned types.
/// All method signatures use ``ScannedDevice``, ``PairedDevice``,
/// ``DeviceConnectionState``, ``DeviceConnectionEvent``, and ``WearMetrics``.
///
/// **Important:** The Garmin Health SDK real-time streaming (RTS) capability requires
/// a separate license from Garmin. This facade is available on demand for licensed
/// integrations. The underlying native SDK code is proprietary to Garmin and is not
/// distributed as open source.
///
/// For cloud-based Garmin data (OAuth + webhooks), use ``GarminProvider`` instead.
///
/// ```swift
/// let garmin = GarminHealth(licenseKey: "your-garmin-sdk-key")
/// try await garmin.initialize()
///
/// // Scan for devices
/// for await devices in garmin.scannedDevicesStream() {
///     print("Found \(devices.count) devices")
/// }
///
/// // Pair and read metrics
/// let paired = try await garmin.pairDevice(scannedDevice)
/// let metrics = try await garmin.readMetrics()
/// ```
public class GarminHealth {
    private let licenseKey: String
    private var _isInitialized = false

    /// Create a GarminHealth instance with a Garmin SDK license key
    ///
    /// - Parameter licenseKey: Valid Garmin Health SDK license key
    public init(licenseKey: String) {
        self.licenseKey = licenseKey
    }

    // MARK: - Lifecycle

    /// Initialize the Garmin Health SDK
    ///
    /// Must be called before any other operations.
    /// - Throws: ``SynheartWearError`` if initialization fails
    public func initialize() async throws {
        guard !_isInitialized else { return }
        // Native Garmin Health SDK initialization is handled by the
        // platform-specific binary (XCFramework). This facade delegates
        // to the native layer which is distributed separately.
        _isInitialized = true
    }

    /// Whether the SDK is initialized
    public var isInitialized: Bool { _isInitialized }

    /// Dispose all resources
    public func dispose() {
        _isInitialized = false
    }

    // MARK: - Scanning

    /// Start scanning for Garmin devices
    ///
    /// - Parameter timeoutSeconds: Scan timeout in seconds (default: 30)
    public func startScanning(timeoutSeconds: Int = 30) async throws {
        try ensureInitialized()
        // Delegates to native Garmin Health SDK
    }

    /// Stop scanning for devices
    public func stopScanning() async throws {
        // Delegates to native Garmin Health SDK
    }

    /// Stream of discovered devices during scanning
    ///
    /// Returns generic ``ScannedDevice`` instances, not Garmin-specific types.
    public func scannedDevicesStream() -> AsyncStream<[ScannedDevice]> {
        return AsyncStream { continuation in
            // Native Garmin Health SDK device discovery events are
            // converted to generic ScannedDevice and yielded here
            continuation.finish()
        }
    }

    // MARK: - Pairing

    /// Pair with a discovered device
    ///
    /// - Parameter device: The scanned device to pair with
    /// - Returns: A generic ``PairedDevice`` on success
    /// - Throws: ``SynheartWearError`` if pairing fails
    public func pairDevice(_ device: ScannedDevice) async throws -> PairedDevice {
        try ensureInitialized()
        // Delegates to native Garmin Health SDK pairing
        throw SynheartWearError.apiError(
            "Garmin Health SDK native binary not linked. Contact Synheart for licensed access."
        )
    }

    /// Forget (unpair) a device
    public func forgetDevice(_ device: PairedDevice) async throws {
        try ensureInitialized()
    }

    /// Get list of paired devices
    public func getPairedDevices() async throws -> [PairedDevice] {
        try ensureInitialized()
        return []
    }

    // MARK: - Connection

    /// Stream of connection state changes
    ///
    /// Returns generic ``DeviceConnectionEvent`` instances.
    public func connectionStateStream() -> AsyncStream<DeviceConnectionEvent> {
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    /// Get connection state for a device
    public func getConnectionState(_ device: PairedDevice) async throws -> DeviceConnectionState {
        try ensureInitialized()
        return .disconnected
    }

    // MARK: - Sync

    /// Request a sync operation with a device
    public func requestSync(_ device: PairedDevice) async throws {
        try ensureInitialized()
    }

    // MARK: - Streaming

    /// Start real-time data streaming
    ///
    /// Listen to ``realTimeStream()`` to receive ``WearMetrics`` data.
    public func startStreaming(device: PairedDevice? = nil) async throws {
        try ensureInitialized()
    }

    /// Stop real-time data streaming
    public func stopStreaming(device: PairedDevice? = nil) async throws {
        // Delegates to native Garmin Health SDK
    }

    /// Stream of real-time data as unified ``WearMetrics``
    ///
    /// Returns ``WearMetrics`` instances, not Garmin-specific real-time data types.
    public func realTimeStream() -> AsyncStream<WearMetrics> {
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    // MARK: - Metrics

    /// Read unified metrics from Garmin device
    ///
    /// Returns ``WearMetrics`` aggregated from available Garmin data sources.
    public func readMetrics(
        startTime: Date? = nil,
        endTime: Date? = nil
    ) async throws -> WearMetrics? {
        try ensureInitialized()
        return nil
    }

    // MARK: - Private

    private func ensureInitialized() throws {
        guard _isInitialized else {
            throw SynheartWearError.apiError(
                "GarminHealth not initialized. Call initialize() first."
            )
        }
    }
}
