// Copyright 2026 Synheart. RAMEN gRPC models mirroring ramen.proto.

import Foundation
import GRPC
import SwiftProtobuf
import NIOCore

// MARK: - Connection State

/// Connection state for the RAMEN bidirectional stream.
internal enum RamenConnectionState: String, Sendable {
    /// Stream started, waiting for first server message.
    case connecting
    /// At least one Event or HeartbeatAck received from server.
    case connected
    /// Stream ended or error; client may be reconnecting.
    case disconnected
    /// Backoff delay before next connect attempt.
    case reconnecting
}

// MARK: - RamenEvent

/// Parsed event from RAMEN (payload bytes decoded as UTF-8 JSON).
internal struct RamenEvent: Sendable {
    public let eventId: String
    public let seq: Int64
    public let provider: String
    public let eventType: String
    public let rawId: String
    public let payloadJson: String
    public let payload: [String: Any]?
    public let createdAt: Date?
    public let isReplay: Bool
    public let deliveryAttempt: Int32

    public init(
        eventId: String,
        seq: Int64,
        provider: String,
        eventType: String,
        rawId: String = "",
        payloadJson: String = "",
        payload: [String: Any]? = nil,
        createdAt: Date? = nil,
        isReplay: Bool = false,
        deliveryAttempt: Int32 = 0
    ) {
        self.eventId = eventId
        self.seq = seq
        self.provider = provider
        self.eventType = eventType
        self.rawId = rawId
        self.payloadJson = payloadJson
        self.payload = payload
        self.createdAt = createdAt
        self.isReplay = isReplay
        self.deliveryAttempt = deliveryAttempt
    }
}

// MARK: - RamenError

/// Errors specific to the RAMEN client.
internal enum RamenError: LocalizedError, Sendable {
    case authFailed(String)
    case rateLimited(String)
    case internalError(String)
    case streamClosed(String)
    case fatalServerError(String)
    case connectionFailed(String)
    case alreadyClosed

    public var errorDescription: String? {
        switch self {
        case .authFailed(let msg):
            return "RAMEN auth failed: \(msg)"
        case .rateLimited(let msg):
            return "RAMEN rate limited: \(msg)"
        case .internalError(let msg):
            return "RAMEN internal error: \(msg)"
        case .streamClosed(let msg):
            return "RAMEN stream closed: \(msg)"
        case .fatalServerError(let msg):
            return "RAMEN fatal error: \(msg)"
        case .connectionFailed(let msg):
            return "RAMEN connection failed: \(msg)"
        case .alreadyClosed:
            return "RAMEN client is already closed."
        }
    }
}

// MARK: - RamenConfig

/// Configuration for the RAMEN client.
internal struct RamenConfig: Sendable {
    public let host: String
    public let port: Int
    public let appId: String
    public let apiKey: String
    public let deviceId: String
    public let userId: String
    public let useTls: Bool
    public let heartbeatInterval: TimeInterval
    public let heartbeatMissedAttempts: Int
    public let providers: [String]
    public let eventTypes: [String]
    public let logResponses: Bool

    public init(
        host: String,
        port: Int = 443,
        appId: String = "",
        apiKey: String = "",
        deviceId: String,
        userId: String = "",
        useTls: Bool = true,
        heartbeatInterval: TimeInterval = 30.0,
        heartbeatMissedAttempts: Int = 2,
        providers: [String] = [],
        eventTypes: [String] = [],
        logResponses: Bool = false
    ) {
        self.host = host
        self.port = port
        self.appId = appId
        self.apiKey = apiKey
        self.deviceId = deviceId
        self.userId = userId
        self.useTls = useTls
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatMissedAttempts = heartbeatMissedAttempts
        self.providers = providers
        self.eventTypes = eventTypes
        self.logResponses = logResponses
    }
}

// MARK: - Proto Enums (mirroring ramen.proto)

/// Ack status sent from client to server.
internal enum RamenAckStatus: Int, Sendable {
    case unspecified = 0
    case success = 1
    case failed = 2
    case skipped = 3
}

/// Error codes from the RAMEN server.
internal enum RamenErrorCode: Int, Sendable {
    case unspecified = 0
    case authFailed = 1
    case rateLimited = 2
    case `internal` = 3
    case streamClosed = 4
}
