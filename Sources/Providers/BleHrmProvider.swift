import Foundation
import CoreBluetooth

/// BLE Heart Rate Monitor provider using CoreBluetooth
///
/// Provides scan, connect, disconnect, and real-time heart rate streaming
/// from any Bluetooth Low Energy heart rate monitor (Polar, Garmin, Wahoo, etc.).
///
/// Implements RFC-BLE-HRM: reconnection with 3 retries and exponential backoff,
/// HR parsing (uint8/uint16 + RR intervals), and structured error codes.
public class BleHrmProvider: NSObject {

    // MARK: - Public Properties

    /// Stream of heart rate samples from the connected device
    public var onHeartRate: AsyncStream<HeartRateSample> {
        AsyncStream { continuation in
            self.streamLock.lock()
            self.streamContinuations.append(continuation)
            self.streamLock.unlock()

            continuation.onTermination = { @Sendable [weak self] _ in
                guard let self = self else { return }
                self.streamLock.lock()
                self.streamContinuations.removeAll { $0 == continuation }
                self.streamLock.unlock()
            }
        }
    }

    /// Last received heart rate sample
    public private(set) var lastSample: HeartRateSample?

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private let cbQueue = DispatchQueue(label: "ai.synheart.wear.ble.hrm", qos: .userInitiated)

    private var connectedPeripheral: CBPeripheral?
    private var hrCharacteristic: CBCharacteristic?
    private var batteryCharacteristic: CBCharacteristic?

    private var currentSessionId: String?
    private var enableBattery: Bool = false

    // Scan state
    private var scanContinuation: CheckedContinuation<[BleHrmDevice], Error>?
    private var scanTimeout: DispatchWorkItem?
    private var discoveredDevices: [String: BleHrmDevice] = [:]
    private var scanNamePrefix: String?

    // Connect state
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var targetDeviceId: String?
    private var isReconnecting = false
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 3
    private let reconnectBackoffs: [TimeInterval] = [1.0, 2.0, 4.0]

    // Stream continuations
    private var streamContinuations: [AsyncStream<HeartRateSample>.Continuation] = []
    private let streamLock = NSLock()

    // Bluetooth state
    private var bluetoothReadyContinuation: CheckedContinuation<Void, Error>?
    private var isCentralReady = false

    // MARK: - Initialization

    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: cbQueue)
    }

    // MARK: - Public Methods

    /// Scan for BLE heart rate monitors
    ///
    /// - Parameters:
    ///   - timeoutMs: Scan timeout in milliseconds (default 10000)
    ///   - namePrefix: Optional filter by device name prefix
    /// - Returns: Array of discovered BLE HRM devices
    /// - Throws: `SynheartWearError.bleHrm` on bluetooth/permission errors
    public func scan(timeoutMs: Int = 10000, namePrefix: String? = nil) async throws -> [BleHrmDevice] {
        try await ensureBluetoothReady()

        return try await withCheckedThrowingContinuation { continuation in
            cbQueue.async { [weak self] in
                guard let self = self else { return }

                self.discoveredDevices.removeAll()
                self.scanNamePrefix = namePrefix
                self.scanContinuation = continuation

                self.centralManager.scanForPeripherals(
                    withServices: [CBUUID(string: BleHrmUUID.heartRateService)],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )

                let timeout = DispatchWorkItem { [weak self] in
                    self?.finishScan()
                }
                self.scanTimeout = timeout
                self.cbQueue.asyncAfter(
                    deadline: .now() + Double(timeoutMs) / 1000.0,
                    execute: timeout
                )
            }
        }
    }

    /// Connect to a BLE HRM device by its identifier
    ///
    /// - Parameters:
    ///   - deviceId: UUID string of the peripheral
    ///   - sessionId: Optional session identifier for tagging samples
    ///   - enableBattery: Whether to subscribe to battery level notifications
    /// - Throws: `SynheartWearError.bleHrm` on connection failure
    public func connect(deviceId: String, sessionId: String? = nil, enableBattery: Bool = false) async throws {
        try await ensureBluetoothReady()

        self.currentSessionId = sessionId
        self.enableBattery = enableBattery
        self.targetDeviceId = deviceId
        self.reconnectAttempt = 0
        self.isReconnecting = false

        try await connectInternal(deviceId: deviceId)
    }

    /// Disconnect from the currently connected device
    public func disconnect() async throws {
        cbQueue.sync {
            isReconnecting = false
            reconnectAttempt = maxReconnectAttempts // prevent auto-reconnect

            if let peripheral = connectedPeripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            cleanupConnection()
        }
    }

    /// Check if a device is currently connected
    public func isConnected() -> Bool {
        return connectedPeripheral?.state == .connected && hrCharacteristic != nil
    }

    /// Clean up resources
    public func dispose() {
        cbQueue.sync {
            isReconnecting = false
            reconnectAttempt = maxReconnectAttempts

            if let peripheral = connectedPeripheral {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            cleanupConnection()
        }

        streamLock.lock()
        for continuation in streamContinuations {
            continuation.finish()
        }
        streamContinuations.removeAll()
        streamLock.unlock()
    }

    // MARK: - Private Methods

    private func ensureBluetoothReady() async throws {
        if isCentralReady { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            cbQueue.async { [weak self] in
                guard let self = self else { return }

                switch self.centralManager.state {
                case .poweredOn:
                    self.isCentralReady = true
                    continuation.resume()
                case .poweredOff:
                    continuation.resume(throwing: SynheartWearError.bleHrm(.bluetoothOff, "Bluetooth is powered off"))
                case .unauthorized:
                    continuation.resume(throwing: SynheartWearError.bleHrm(.permissionDenied, "Bluetooth permission denied"))
                case .unsupported:
                    continuation.resume(throwing: SynheartWearError.bleHrm(.permissionDenied, "Bluetooth LE not supported"))
                case .unknown, .resetting:
                    self.bluetoothReadyContinuation = continuation
                @unknown default:
                    self.bluetoothReadyContinuation = continuation
                }
            }
        }
    }

    private func connectInternal(deviceId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            cbQueue.async { [weak self] in
                guard let self = self else { return }

                self.connectContinuation = continuation

                guard let uuid = UUID(uuidString: deviceId) else {
                    self.connectContinuation = nil
                    continuation.resume(throwing: SynheartWearError.bleHrm(.deviceNotFound, "Invalid device ID: \(deviceId)"))
                    return
                }

                let peripherals = self.centralManager.retrievePeripherals(withIdentifiers: [uuid])
                guard let peripheral = peripherals.first else {
                    // Try to find via scan results
                    self.connectContinuation = nil
                    continuation.resume(throwing: SynheartWearError.bleHrm(.deviceNotFound, "Device not found: \(deviceId)"))
                    return
                }

                self.connectedPeripheral = peripheral
                peripheral.delegate = self
                self.centralManager.connect(peripheral, options: nil)

                // Connection timeout after 15 seconds
                self.cbQueue.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    guard let self = self, let cont = self.connectContinuation else { return }
                    self.connectContinuation = nil
                    self.centralManager.cancelPeripheralConnection(peripheral)
                    cont.resume(throwing: SynheartWearError.bleHrm(.deviceNotFound, "Connection timed out"))
                }
            }
        }
    }

    private func finishScan() {
        centralManager.stopScan()
        scanTimeout?.cancel()
        scanTimeout = nil

        let devices = Array(discoveredDevices.values)
        let cont = scanContinuation
        scanContinuation = nil
        cont?.resume(returning: devices)
    }

    private func cleanupConnection() {
        connectedPeripheral = nil
        hrCharacteristic = nil
        batteryCharacteristic = nil
    }

    private func attemptReconnect() {
        guard let deviceId = targetDeviceId,
              reconnectAttempt < maxReconnectAttempts else {
            // Max retries exhausted — notify streams
            emitDisconnection()
            return
        }

        isReconnecting = true
        let delay = reconnectBackoffs[reconnectAttempt]
        reconnectAttempt += 1

        cbQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isReconnecting else { return }
            guard let uuid = UUID(uuidString: deviceId),
                  let peripheral = self.centralManager.retrievePeripherals(withIdentifiers: [uuid]).first else {
                self.attemptReconnect()
                return
            }

            self.connectedPeripheral = peripheral
            peripheral.delegate = self
            self.centralManager.connect(peripheral, options: nil)
        }
    }

    private func emitSample(_ sample: HeartRateSample) {
        lastSample = sample
        streamLock.lock()
        let continuations = streamContinuations
        streamLock.unlock()

        for continuation in continuations {
            continuation.yield(sample)
        }
    }

    private func emitDisconnection() {
        // We don't finish streams on disconnect — the provider stays alive
        // and can reconnect. Consumers check isConnected() for state.
    }
}

// MARK: - CBCentralManagerDelegate

extension BleHrmProvider: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            isCentralReady = true
            bluetoothReadyContinuation?.resume()
            bluetoothReadyContinuation = nil
        case .poweredOff:
            bluetoothReadyContinuation?.resume(throwing: SynheartWearError.bleHrm(.bluetoothOff, "Bluetooth is powered off"))
            bluetoothReadyContinuation = nil
        case .unauthorized:
            bluetoothReadyContinuation?.resume(throwing: SynheartWearError.bleHrm(.permissionDenied, "Bluetooth permission denied"))
            bluetoothReadyContinuation = nil
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String

        if let prefix = scanNamePrefix, let name = name {
            guard name.hasPrefix(prefix) else { return }
        }

        let device = BleHrmDevice(
            deviceId: peripheral.identifier.uuidString,
            name: name,
            rssi: RSSI.intValue
        )
        discoveredDevices[device.deviceId] = device
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isReconnecting = false
        reconnectAttempt = 0
        peripheral.discoverServices([CBUUID(string: BleHrmUUID.heartRateService), CBUUID(string: BleHrmUUID.batteryService)])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let cont = connectContinuation {
            connectContinuation = nil
            cont.resume(throwing: SynheartWearError.bleHrm(.deviceNotFound, "Failed to connect: \(error?.localizedDescription ?? "unknown")"))
        } else {
            attemptReconnect()
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        hrCharacteristic = nil
        batteryCharacteristic = nil

        if isReconnecting || (error != nil && reconnectAttempt < maxReconnectAttempts) {
            attemptReconnect()
        } else {
            cleanupConnection()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BleHrmProvider: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            connectContinuation?.resume(throwing: SynheartWearError.bleHrm(.subscribeFailed, "Service discovery failed: \(error?.localizedDescription ?? "unknown")"))
            connectContinuation = nil
            return
        }

        for service in services {
            if service.uuid == CBUUID(string: BleHrmUUID.heartRateService) {
                peripheral.discoverCharacteristics([CBUUID(string: BleHrmUUID.heartRateMeasurement)], for: service)
            } else if service.uuid == CBUUID(string: BleHrmUUID.batteryService) && enableBattery {
                peripheral.discoverCharacteristics([CBUUID(string: BleHrmUUID.batteryLevel)], for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            connectContinuation?.resume(throwing: SynheartWearError.bleHrm(.subscribeFailed, "Characteristic discovery failed"))
            connectContinuation = nil
            return
        }

        for characteristic in characteristics {
            if characteristic.uuid == CBUUID(string: BleHrmUUID.heartRateMeasurement) {
                hrCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == CBUUID(string: BleHrmUUID.batteryLevel) {
                batteryCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == CBUUID(string: BleHrmUUID.heartRateMeasurement) {
            if let error = error {
                connectContinuation?.resume(throwing: SynheartWearError.bleHrm(.subscribeFailed, "Failed to subscribe to HR notifications: \(error.localizedDescription)"))
                connectContinuation = nil
                return
            }

            // Successfully subscribed — connection is complete
            connectContinuation?.resume()
            connectContinuation = nil
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        if characteristic.uuid == CBUUID(string: BleHrmUUID.heartRateMeasurement) {
            let parsed = HeartRateParser.parse(data)
            guard parsed.bpm > 0 else { return }

            let sample = HeartRateSample(
                tsMs: Int64(Date().timeIntervalSince1970 * 1000),
                bpm: parsed.bpm,
                source: "ble_hrm",
                deviceId: peripheral.identifier.uuidString,
                deviceName: peripheral.name,
                sessionId: currentSessionId,
                rrIntervalsMs: parsed.rrIntervalsMs
            )
            emitSample(sample)
        }
    }
}

// MARK: - AsyncStream.Continuation Equatable (identity-based)

extension AsyncStream.Continuation: @retroactive Equatable {
    public static func == (lhs: AsyncStream.Continuation, rhs: AsyncStream.Continuation) -> Bool {
        withUnsafePointer(to: lhs) { lhsPtr in
            withUnsafePointer(to: rhs) { rhsPtr in
                lhsPtr == rhsPtr
            }
        }
    }
}
