// Copyright 2026 Synheart. RAMEN gRPC client for real-time event delivery.
//
// Mirrors the Dart reference implementation: bidirectional Subscribe stream,
// heartbeat keepalive, auto-reconnect with exponential backoff, seq persistence
// via UserDefaults, and Combine-based event/state/error publishers.

import Combine
import Foundation
import GRPC
import NIOCore
import NIOHPACK
import NIOPosix
import SwiftProtobuf

// MARK: - UserDefaults Key

private let kLastSeqKey = "ramen_last_acknowledged_seq"

// MARK: - RamenClient

/// RAMEN gRPC client: persistent bidirectional stream for real-time event
/// delivery from Synheart cloud services.
///
/// Uses grpc-swift (NIO-based) for the transport layer. Auth credentials
/// (X-app-id, X-api-key) are sent as gRPC metadata on every Subscribe call.
///
/// Usage:
/// ```swift
/// let config = RamenConfig(host: "ramen.synheart.ai", deviceId: "my-device")
/// let client = RamenClient(config: config)
///
/// let cancellable = client.events.sink { event in
///     print("Event: \(event.eventType) seq=\(event.seq)")
/// }
///
/// try await client.connect()
/// // ... later ...
/// await client.close()
/// ```
internal final class RamenClient {

    // MARK: - Public Publishers

    /// Stream of parsed RAMEN events. Events are auto-acked on receipt.
    public var events: AnyPublisher<RamenEvent, Never> {
        _eventSubject.eraseToAnyPublisher()
    }

    /// Stream of connection state transitions.
    public var connectionState: AnyPublisher<RamenConnectionState, Never> {
        _stateSubject.eraseToAnyPublisher()
    }

    /// Stream of server-side errors. Fatal errors close the stream (no auto-reconnect).
    public var errors: AnyPublisher<RamenError, Never> {
        _errorSubject.eraseToAnyPublisher()
    }

    // MARK: - Configuration

    private let config: RamenConfig

    // MARK: - Internal State

    private let _eventSubject = PassthroughSubject<RamenEvent, Never>()
    private let _stateSubject = PassthroughSubject<RamenConnectionState, Never>()
    private let _errorSubject = PassthroughSubject<RamenError, Never>()

    private var group: (any EventLoopGroup)?
    private var channel: ClientConnection?
    private var call: BidirectionalStreamingCall<Ramen_V1_ClientMessage, Ramen_V1_ServerMessage>?
    private var heartbeatTimer: Timer?
    private var heartbeatsWithoutAck: Int = 0
    private var closed: Bool = false
    private var hasEmittedConnected: Bool = false
    private var backoffSeconds: Int = 1

    // MARK: - Init

    /// Create a new RAMEN client with the given configuration.
    ///
    /// - Parameter config: Connection and auth configuration.
    public init(config: RamenConfig) {
        self.config = config
    }

    // MARK: - Public API

    /// Last acknowledged sequence number, persisted to UserDefaults.
    /// Returns 0 on first launch.
    public var lastSeq: Int64 {
        let v = UserDefaults().object(forKey: kLastSeqKey) as? Int64
        return v ?? 0
    }

    /// Start the subscription stream.
    ///
    /// Sends a SubscribeRequest with the persisted last_seq, device_id, user_id,
    /// and optional provider/event_type filters. Auth headers (X-app-id, X-api-key)
    /// are attached as gRPC call metadata.
    ///
    /// On each EventEnvelope the client automatically sends an Ack and persists
    /// the seq. A heartbeat is sent every `config.heartbeatInterval` seconds;
    /// if `config.heartbeatMissedAttempts` consecutive heartbeats go unacked the
    /// connection is torn down and reconnected with exponential backoff (max 32s).
    ///
    /// - Throws: `RamenError.alreadyClosed` if `close()` was already called.
    public func connect() async throws {
        guard !closed else { throw RamenError.alreadyClosed }

        hasEmittedConnected = false
        log("connecting to \(config.host):\(config.port) (tls=\(config.useTls))")
        _stateSubject.send(.connecting)

        // Tear down any previous connection.
        await teardownConnection()

        // Create NIO event loop group + gRPC channel.
        let elg = PlatformSupport.makeEventLoopGroup(loopCount: 1)
        self.group = elg

        let builder: ClientConnection.Builder
        if config.useTls {
            builder = ClientConnection.usingTLSBackedByNIOSSL(on: elg)
        } else {
            builder = ClientConnection.insecure(group: elg)
        }

        let connection = builder.connect(host: config.host, port: config.port)
        self.channel = connection

        // Build gRPC call options with auth metadata.
        var callOptions = CallOptions()
        var metadata = HPACKHeaders()
        if !config.appId.isEmpty { metadata.add(name: "x-app-id", value: config.appId) }
        if !config.apiKey.isEmpty { metadata.add(name: "x-api-key", value: config.apiKey) }
        callOptions.customMetadata = metadata

        // Create the NIO-based client and open the bidirectional stream.
        let client = Ramen_V1_RAMENServiceNIOClient(channel: connection)
        let streamCall = client.subscribe(callOptions: callOptions) { [weak self] serverMsg in
            self?.handleServerMessage(serverMsg)
        }
        self.call = streamCall

        // Send the initial SubscribeRequest.
        var subscribeReq = Ramen_V1_SubscribeRequest()
        subscribeReq.appID = config.appId
        subscribeReq.deviceID = config.deviceId
        subscribeReq.userID = config.userId
        subscribeReq.lastSeq = lastSeq
        subscribeReq.providers = config.providers
        subscribeReq.eventTypes = config.eventTypes

        var firstMessage = Ramen_V1_ClientMessage()
        firstMessage.subscribe = subscribeReq
        streamCall.sendMessage(firstMessage, promise: nil)

        // Reset heartbeat state and start timer.
        heartbeatsWithoutAck = 0
        startHeartbeatTimer()

        // Handle stream completion.
        streamCall.status.whenComplete { [weak self] result in
            guard let self else { return }
            self.stopHeartbeatTimer()

            switch result {
            case .success(let status):
                self.log("stream ended with status: \(status.code)")
                if !self.closed {
                    self._stateSubject.send(.disconnected)
                    // Do not reconnect on UNIMPLEMENTED.
                    if status.code != .unimplemented {
                        self.scheduleReconnect()
                    }
                }
            case .failure(let error):
                self.log("stream error: \(error)")
                if !self.closed {
                    self._stateSubject.send(.disconnected)
                    let desc = String(describing: error)
                    let isUnimplemented = desc.contains("UNIMPLEMENTED") || desc.contains("unknown service")
                    if !isUnimplemented {
                        self.scheduleReconnect()
                    }
                }
            }
        }
    }

    /// Close the client and stop reconnecting. The Combine subjects are completed.
    public func close() async {
        closed = true
        stopHeartbeatTimer()

        // End the request stream gracefully.
        call?.sendEnd(promise: nil)
        _ = try? call?.status.wait()
        call = nil

        await teardownConnection()

        _eventSubject.send(completion: .finished)
        _errorSubject.send(completion: .finished)
        _stateSubject.send(completion: .finished)
    }

    // MARK: - Server Message Handling

    private func handleServerMessage(_ msg: Ramen_V1_ServerMessage) {
        switch msg.message {
        case .subscribeResponse(let resp):
            emitConnectedIfFirst()
            onSubscribeResponse(resp)

        case .event(let envelope):
            emitConnectedIfFirst()
            onEvent(envelope)

        case .heartbeatAck(let ack):
            emitConnectedIfFirst()
            logResponse("heartbeat_ack", detail: "rtt_ms=\(ack.rttMs)")
            heartbeatsWithoutAck = 0

        case .error(let err):
            onServerError(err)

        case nil:
            break
        }
    }

    private func onSubscribeResponse(_ resp: Ramen_V1_SubscribeResponse) {
        logResponse("subscribe_response",
                     detail: "connection_id=\(resp.connectionID) current_seq=\(resp.currentSeq) heartbeat_interval=\(resp.heartbeatIntervalSeconds)s")

        // Adopt server-requested heartbeat interval if present.
        if resp.heartbeatIntervalSeconds > 0 {
            stopHeartbeatTimer()
            let interval = max(5, min(Int(resp.heartbeatIntervalSeconds), 300))
            startHeartbeatTimer(interval: TimeInterval(interval))
        }
    }

    private func onEvent(_ envelope: Ramen_V1_EventEnvelope) {
        logResponse("event",
                     detail: "event_id=\(envelope.eventID) seq=\(envelope.seq) provider=\(envelope.provider) event_type=\(envelope.eventType) payload_length=\(envelope.payload.count)")

        // Parse payload bytes as UTF-8 JSON.
        var payloadJson = ""
        var payloadDict: [String: Any]?
        if !envelope.payload.isEmpty {
            if let str = String(data: envelope.payload, encoding: .utf8) {
                payloadJson = str
                payloadDict = try? JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any]
            }
        }

        let createdAt: Date? = envelope.hasCreatedAt
            ? Date(timeIntervalSince1970: TimeInterval(envelope.createdAt.seconds)
                + TimeInterval(envelope.createdAt.nanos) / 1_000_000_000)
            : nil

        let event = RamenEvent(
            eventId: envelope.eventID,
            seq: envelope.seq,
            provider: envelope.provider,
            eventType: envelope.eventType,
            rawId: envelope.rawID,
            payloadJson: payloadJson,
            payload: payloadDict,
            createdAt: createdAt,
            isReplay: envelope.hasDelivery ? envelope.delivery.isReplay : false,
            deliveryAttempt: envelope.hasDelivery ? envelope.delivery.attempt : 0
        )

        _eventSubject.send(event)
        sendAck(seq: envelope.seq)
        persistLastSeq(envelope.seq)
    }

    private func onServerError(_ err: Ramen_V1_Error) {
        logResponse("error", detail: "code=\(err.code) message=\(err.message) fatal=\(err.fatal)")

        let ramenError: RamenError
        switch err.code {
        case .authFailed:
            ramenError = .authFailed(err.message)
        case .rateLimited:
            ramenError = .rateLimited(err.message)
        case .internal:
            ramenError = .internalError(err.message)
        case .streamClosed:
            ramenError = .streamClosed(err.message)
        default:
            ramenError = .internalError(err.message)
        }

        _errorSubject.send(ramenError)

        if err.fatal {
            stopHeartbeatTimer()
            call?.sendEnd(promise: nil)
            if !closed {
                _stateSubject.send(.disconnected)
            }
        }
    }

    // MARK: - Sending Client Messages

    private func trySend(_ msg: Ramen_V1_ClientMessage) {
        call?.sendMessage(msg, promise: nil)
    }

    private func sendAck(seq: Int64, status: Ramen_V1_AckStatus = .success) {
        var ack = Ramen_V1_Ack()
        ack.seq = seq
        ack.status = status

        var msg = Ramen_V1_ClientMessage()
        msg.ack = ack
        trySend(msg)
    }

    private func sendHeartbeat() {
        heartbeatsWithoutAck += 1
        if heartbeatsWithoutAck >= config.heartbeatMissedAttempts {
            stopHeartbeatTimer()
            call?.sendEnd(promise: nil)
            scheduleReconnect()
            return
        }

        var ts = Google_Protobuf_Timestamp()
        let now = Date()
        ts.seconds = Int64(now.timeIntervalSince1970)
        ts.nanos = Int32((now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1_000_000_000)

        var hb = Ramen_V1_Heartbeat()
        hb.timestamp = ts

        var msg = Ramen_V1_ClientMessage()
        msg.heartbeat = hb
        trySend(msg)
    }

    // MARK: - Seq Persistence

    private func persistLastSeq(_ seq: Int64) {
        UserDefaults().set(seq, forKey: kLastSeqKey)
    }

    // MARK: - Heartbeat Timer

    private func startHeartbeatTimer(interval: TimeInterval? = nil) {
        stopHeartbeatTimer()
        let ti = interval ?? config.heartbeatInterval
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: ti, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }

    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard !closed else { return }
        stopHeartbeatTimer()

        let delay = backoffSeconds
        backoffSeconds = min(backoffSeconds * 2, 32)

        log("reconnecting in \(delay)s")
        _stateSubject.send(.reconnecting)

        Task { [weak self] in
            guard let self, !self.closed else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !self.closed else { return }
            self.log("reconnecting now...")
            try? await self.connect()
        }
    }

    private func emitConnectedIfFirst() {
        guard !hasEmittedConnected, !closed else { return }
        hasEmittedConnected = true
        backoffSeconds = 1
        log("established")
        _stateSubject.send(.connected)
    }

    // MARK: - Teardown

    private func teardownConnection() async {
        call?.sendEnd(promise: nil)
        call = nil

        if let ch = channel {
            let closeFuture = ch.close()
            try? closeFuture.wait()
            channel = nil
        }

        if let g = group {
            try? g.syncShutdownGracefully()
            group = nil
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        if config.logResponses {
            print("[RAMEN] connection: \(message)")
        }
    }

    private func logResponse(_ type: String, detail: String) {
        if config.logResponses {
            print("[RAMEN] \(type): \(detail)")
        }
    }
}
