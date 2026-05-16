// Copyright 2026 Synheart. Hand-written SwiftProtobuf types mirroring ramen.proto.
//
// These types mirror the protobuf definitions in ramen/v1/ramen.proto and are
// compatible with grpc-swift's codegen conventions. They can be replaced with
// protoc-gen-grpc-swift output when a protoc build step is added to CI.
//
// Package: ramen.v1

import Foundation
import SwiftProtobuf

// MARK: - AckStatus

public enum Ramen_V1_AckStatus: SwiftProtobuf.Enum {
    public typealias RawValue = Int

    case unspecified // = 0
    case success     // = 1
    case failed      // = 2
    case skipped     // = 3
    case UNRECOGNIZED(Int)

    public init() { self = .unspecified }

    public init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .success
        case 2: self = .failed
        case 3: self = .skipped
        default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
        case .unspecified: return 0
        case .success: return 1
        case .failed: return 2
        case .skipped: return 3
        case .UNRECOGNIZED(let v): return v
        }
    }
}

// MARK: - ErrorCode

public enum Ramen_V1_ErrorCode: SwiftProtobuf.Enum {
    public typealias RawValue = Int

    case unspecified  // = 0
    case authFailed   // = 1
    case rateLimited  // = 2
    case `internal`   // = 3
    case streamClosed // = 4
    case UNRECOGNIZED(Int)

    public init() { self = .unspecified }

    public init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .authFailed
        case 2: self = .rateLimited
        case 3: self = .internal
        case 4: self = .streamClosed
        default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
        case .unspecified: return 0
        case .authFailed: return 1
        case .rateLimited: return 2
        case .internal: return 3
        case .streamClosed: return 4
        case .UNRECOGNIZED(let v): return v
        }
    }
}

// MARK: - SubscribeRequest (field numbers from proto)

public struct Ramen_V1_SubscribeRequest: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.SubscribeRequest"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .same(proto: "token"),
        2: .standard(proto: "device_id"),
        3: .standard(proto: "app_id"),
        4: .standard(proto: "user_id"),
        5: .standard(proto: "last_seq"),
        6: .same(proto: "providers"),
        7: .standard(proto: "event_types"),
    ]

    public var token: String = ""           // = 1
    public var deviceID: String = ""        // = 2
    public var appID: String = ""           // = 3
    public var userID: String = ""          // = 4
    public var lastSeq: Int64 = 0           // = 5
    public var providers: [String] = []     // = 6
    public var eventTypes: [String] = []    // = 7

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularStringField(value: &token)
            case 2: try decoder.decodeSingularStringField(value: &deviceID)
            case 3: try decoder.decodeSingularStringField(value: &appID)
            case 4: try decoder.decodeSingularStringField(value: &userID)
            case 5: try decoder.decodeSingularInt64Field(value: &lastSeq)
            case 6: try decoder.decodeRepeatedStringField(value: &providers)
            case 7: try decoder.decodeRepeatedStringField(value: &eventTypes)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if !token.isEmpty { try visitor.visitSingularStringField(value: token, fieldNumber: 1) }
        if !deviceID.isEmpty { try visitor.visitSingularStringField(value: deviceID, fieldNumber: 2) }
        if !appID.isEmpty { try visitor.visitSingularStringField(value: appID, fieldNumber: 3) }
        if !userID.isEmpty { try visitor.visitSingularStringField(value: userID, fieldNumber: 4) }
        if lastSeq != 0 { try visitor.visitSingularInt64Field(value: lastSeq, fieldNumber: 5) }
        if !providers.isEmpty { try visitor.visitRepeatedStringField(value: providers, fieldNumber: 6) }
        if !eventTypes.isEmpty { try visitor.visitRepeatedStringField(value: eventTypes, fieldNumber: 7) }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.token == rhs.token && lhs.deviceID == rhs.deviceID && lhs.appID == rhs.appID
            && lhs.userID == rhs.userID && lhs.lastSeq == rhs.lastSeq
            && lhs.providers == rhs.providers && lhs.eventTypes == rhs.eventTypes
            && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - Ack

public struct Ramen_V1_Ack: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.Ack"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .same(proto: "seq"),
        2: .same(proto: "status"),
    ]

    public var seq: Int64 = 0                            // = 1
    public var status: Ramen_V1_AckStatus = .unspecified // = 2

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularInt64Field(value: &seq)
            case 2: try decoder.decodeSingularEnumField(value: &status)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if seq != 0 { try visitor.visitSingularInt64Field(value: seq, fieldNumber: 1) }
        if status != .unspecified { try visitor.visitSingularEnumField(value: status, fieldNumber: 2) }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.seq == rhs.seq && lhs.status == rhs.status && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - Heartbeat

public struct Ramen_V1_Heartbeat: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.Heartbeat"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .same(proto: "timestamp"),
    ]

    public var timestamp: Google_Protobuf_Timestamp {
        get { _timestamp ?? Google_Protobuf_Timestamp() }
        set { _timestamp = newValue }
    }
    public var hasTimestamp: Bool { _timestamp != nil }
    public mutating func clearTimestamp() { _timestamp = nil }
    private var _timestamp: Google_Protobuf_Timestamp?

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularMessageField(value: &_timestamp)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        try { if let v = self._timestamp {
            try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
        } }()
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs._timestamp == rhs._timestamp && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - ClientMessage (oneof)

public struct Ramen_V1_ClientMessage: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.ClientMessage"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .same(proto: "subscribe"),
        2: .same(proto: "ack"),
        3: .same(proto: "heartbeat"),
    ]

    public enum OneOf_Message: Equatable, Sendable {
        case subscribe(Ramen_V1_SubscribeRequest)
        case ack(Ramen_V1_Ack)
        case heartbeat(Ramen_V1_Heartbeat)

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.subscribe(let l), .subscribe(let r)): return l == r
            case (.ack(let l), .ack(let r)): return l == r
            case (.heartbeat(let l), .heartbeat(let r)): return l == r
            default: return false
            }
        }
    }

    public var message: OneOf_Message?

    public var subscribe: Ramen_V1_SubscribeRequest {
        get {
            if case .subscribe(let v) = message { return v }
            return Ramen_V1_SubscribeRequest()
        }
        set { message = .subscribe(newValue) }
    }

    public var ack: Ramen_V1_Ack {
        get {
            if case .ack(let v) = message { return v }
            return Ramen_V1_Ack()
        }
        set { message = .ack(newValue) }
    }

    public var heartbeat: Ramen_V1_Heartbeat {
        get {
            if case .heartbeat(let v) = message { return v }
            return Ramen_V1_Heartbeat()
        }
        set { message = .heartbeat(newValue) }
    }

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            if message != nil, [1, 2, 3].contains(fieldNumber) {
                try decoder.handleConflictingOneOf()
            }
            switch fieldNumber {
            case 1:
                var v: Ramen_V1_SubscribeRequest?
                try decoder.decodeSingularMessageField(value: &v)
                if let v { message = .subscribe(v) }
            case 2:
                var v: Ramen_V1_Ack?
                try decoder.decodeSingularMessageField(value: &v)
                if let v { message = .ack(v) }
            case 3:
                var v: Ramen_V1_Heartbeat?
                try decoder.decodeSingularMessageField(value: &v)
                if let v { message = .heartbeat(v) }
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        switch message {
        case .subscribe(let v):
            try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
        case .ack(let v):
            try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
        case .heartbeat(let v):
            try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
        case nil:
            break
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.message == rhs.message && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - SubscribeResponse

public struct Ramen_V1_SubscribeResponse: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.SubscribeResponse"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .standard(proto: "connection_id"),
        2: .standard(proto: "expires_at"),
        3: .standard(proto: "heartbeat_interval_seconds"),
        4: .standard(proto: "current_seq"),
    ]

    public var connectionID: String = ""    // = 1
    public var expiresAt: Google_Protobuf_Timestamp {
        get { _expiresAt ?? Google_Protobuf_Timestamp() }
        set { _expiresAt = newValue }
    }
    public var hasExpiresAt: Bool { _expiresAt != nil }
    public mutating func clearExpiresAt() { _expiresAt = nil }
    private var _expiresAt: Google_Protobuf_Timestamp?  // = 2

    public var heartbeatIntervalSeconds: Int32 = 0  // = 3
    public var currentSeq: Int64 = 0                // = 4

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularStringField(value: &connectionID)
            case 2: try decoder.decodeSingularMessageField(value: &_expiresAt)
            case 3: try decoder.decodeSingularInt32Field(value: &heartbeatIntervalSeconds)
            case 4: try decoder.decodeSingularInt64Field(value: &currentSeq)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if !connectionID.isEmpty { try visitor.visitSingularStringField(value: connectionID, fieldNumber: 1) }
        try { if let v = self._expiresAt {
            try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
        } }()
        if heartbeatIntervalSeconds != 0 { try visitor.visitSingularInt32Field(value: heartbeatIntervalSeconds, fieldNumber: 3) }
        if currentSeq != 0 { try visitor.visitSingularInt64Field(value: currentSeq, fieldNumber: 4) }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.connectionID == rhs.connectionID && lhs._expiresAt == rhs._expiresAt
            && lhs.heartbeatIntervalSeconds == rhs.heartbeatIntervalSeconds
            && lhs.currentSeq == rhs.currentSeq && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - DeliveryMeta

public struct Ramen_V1_DeliveryMeta: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.DeliveryMeta"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .same(proto: "attempt"),
        2: .standard(proto: "first_sent_at"),
        3: .standard(proto: "is_replay"),
    ]

    public var attempt: Int32 = 0           // = 1
    public var firstSentAt: Google_Protobuf_Timestamp {
        get { _firstSentAt ?? Google_Protobuf_Timestamp() }
        set { _firstSentAt = newValue }
    }
    public var hasFirstSentAt: Bool { _firstSentAt != nil }
    private var _firstSentAt: Google_Protobuf_Timestamp? // = 2
    public var isReplay: Bool = false       // = 3

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularInt32Field(value: &attempt)
            case 2: try decoder.decodeSingularMessageField(value: &_firstSentAt)
            case 3: try decoder.decodeSingularBoolField(value: &isReplay)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if attempt != 0 { try visitor.visitSingularInt32Field(value: attempt, fieldNumber: 1) }
        try { if let v = self._firstSentAt {
            try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
        } }()
        if isReplay { try visitor.visitSingularBoolField(value: isReplay, fieldNumber: 3) }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.attempt == rhs.attempt && lhs._firstSentAt == rhs._firstSentAt
            && lhs.isReplay == rhs.isReplay && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - EventEnvelope

public struct Ramen_V1_EventEnvelope: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.EventEnvelope"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .standard(proto: "event_id"),
        2: .same(proto: "seq"),
        3: .same(proto: "provider"),
        4: .standard(proto: "event_type"),
        5: .standard(proto: "raw_id"),
        6: .same(proto: "payload"),
        7: .standard(proto: "created_at"),
        8: .same(proto: "delivery"),
    ]

    public var eventID: String = ""     // = 1
    public var seq: Int64 = 0           // = 2
    public var provider: String = ""    // = 3
    public var eventType: String = ""   // = 4
    public var rawID: String = ""       // = 5
    public var payload: Data = Data()   // = 6
    public var createdAt: Google_Protobuf_Timestamp {
        get { _createdAt ?? Google_Protobuf_Timestamp() }
        set { _createdAt = newValue }
    }
    public var hasCreatedAt: Bool { _createdAt != nil }
    private var _createdAt: Google_Protobuf_Timestamp?  // = 7
    public var delivery: Ramen_V1_DeliveryMeta {
        get { _delivery ?? Ramen_V1_DeliveryMeta() }
        set { _delivery = newValue }
    }
    public var hasDelivery: Bool { _delivery != nil }
    private var _delivery: Ramen_V1_DeliveryMeta?       // = 8

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularStringField(value: &eventID)
            case 2: try decoder.decodeSingularInt64Field(value: &seq)
            case 3: try decoder.decodeSingularStringField(value: &provider)
            case 4: try decoder.decodeSingularStringField(value: &eventType)
            case 5: try decoder.decodeSingularStringField(value: &rawID)
            case 6: try decoder.decodeSingularBytesField(value: &payload)
            case 7: try decoder.decodeSingularMessageField(value: &_createdAt)
            case 8: try decoder.decodeSingularMessageField(value: &_delivery)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if !eventID.isEmpty { try visitor.visitSingularStringField(value: eventID, fieldNumber: 1) }
        if seq != 0 { try visitor.visitSingularInt64Field(value: seq, fieldNumber: 2) }
        if !provider.isEmpty { try visitor.visitSingularStringField(value: provider, fieldNumber: 3) }
        if !eventType.isEmpty { try visitor.visitSingularStringField(value: eventType, fieldNumber: 4) }
        if !rawID.isEmpty { try visitor.visitSingularStringField(value: rawID, fieldNumber: 5) }
        if !payload.isEmpty { try visitor.visitSingularBytesField(value: payload, fieldNumber: 6) }
        try { if let v = self._createdAt {
            try visitor.visitSingularMessageField(value: v, fieldNumber: 7)
        } }()
        try { if let v = self._delivery {
            try visitor.visitSingularMessageField(value: v, fieldNumber: 8)
        } }()
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.eventID == rhs.eventID && lhs.seq == rhs.seq && lhs.provider == rhs.provider
            && lhs.eventType == rhs.eventType && lhs.rawID == rhs.rawID && lhs.payload == rhs.payload
            && lhs._createdAt == rhs._createdAt && lhs._delivery == rhs._delivery
            && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - HeartbeatAck

public struct Ramen_V1_HeartbeatAck: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.HeartbeatAck"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .standard(proto: "server_time"),
        2: .standard(proto: "rtt_ms"),
    ]

    public var serverTime: Google_Protobuf_Timestamp {
        get { _serverTime ?? Google_Protobuf_Timestamp() }
        set { _serverTime = newValue }
    }
    public var hasServerTime: Bool { _serverTime != nil }
    private var _serverTime: Google_Protobuf_Timestamp?  // = 1
    public var rttMs: Int64 = 0                          // = 2

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularMessageField(value: &_serverTime)
            case 2: try decoder.decodeSingularInt64Field(value: &rttMs)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        try { if let v = self._serverTime {
            try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
        } }()
        if rttMs != 0 { try visitor.visitSingularInt64Field(value: rttMs, fieldNumber: 2) }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs._serverTime == rhs._serverTime && lhs.rttMs == rhs.rttMs
            && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - Error

public struct Ramen_V1_Error: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.Error"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .same(proto: "code"),
        2: .same(proto: "message"),
        3: .same(proto: "fatal"),
    ]

    public var code: Ramen_V1_ErrorCode = .unspecified  // = 1
    public var message: String = ""                     // = 2
    public var fatal: Bool = false                      // = 3

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularEnumField(value: &code)
            case 2: try decoder.decodeSingularStringField(value: &message)
            case 3: try decoder.decodeSingularBoolField(value: &fatal)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if code != .unspecified { try visitor.visitSingularEnumField(value: code, fieldNumber: 1) }
        if !message.isEmpty { try visitor.visitSingularStringField(value: message, fieldNumber: 2) }
        if fatal { try visitor.visitSingularBoolField(value: fatal, fieldNumber: 3) }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.code == rhs.code && lhs.message == rhs.message && lhs.fatal == rhs.fatal
            && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - ServerMessage (oneof)

public struct Ramen_V1_ServerMessage: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.ServerMessage"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .standard(proto: "subscribe_response"),
        2: .same(proto: "event"),
        3: .standard(proto: "heartbeat_ack"),
        4: .same(proto: "error"),
    ]

    public enum OneOf_Message: Equatable, Sendable {
        case subscribeResponse(Ramen_V1_SubscribeResponse)
        case event(Ramen_V1_EventEnvelope)
        case heartbeatAck(Ramen_V1_HeartbeatAck)
        case error(Ramen_V1_Error)

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.subscribeResponse(let l), .subscribeResponse(let r)): return l == r
            case (.event(let l), .event(let r)): return l == r
            case (.heartbeatAck(let l), .heartbeatAck(let r)): return l == r
            case (.error(let l), .error(let r)): return l == r
            default: return false
            }
        }
    }

    public var message: OneOf_Message?

    public var subscribeResponse: Ramen_V1_SubscribeResponse {
        get {
            if case .subscribeResponse(let v) = message { return v }
            return Ramen_V1_SubscribeResponse()
        }
        set { message = .subscribeResponse(newValue) }
    }

    public var event: Ramen_V1_EventEnvelope {
        get {
            if case .event(let v) = message { return v }
            return Ramen_V1_EventEnvelope()
        }
        set { message = .event(newValue) }
    }

    public var heartbeatAck: Ramen_V1_HeartbeatAck {
        get {
            if case .heartbeatAck(let v) = message { return v }
            return Ramen_V1_HeartbeatAck()
        }
        set { message = .heartbeatAck(newValue) }
    }

    public var error: Ramen_V1_Error {
        get {
            if case .error(let v) = message { return v }
            return Ramen_V1_Error()
        }
        set { message = .error(newValue) }
    }

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            if message != nil, [1, 2, 3, 4].contains(fieldNumber) {
                try decoder.handleConflictingOneOf()
            }
            switch fieldNumber {
            case 1:
                var v: Ramen_V1_SubscribeResponse?
                try decoder.decodeSingularMessageField(value: &v)
                if let v { message = .subscribeResponse(v) }
            case 2:
                var v: Ramen_V1_EventEnvelope?
                try decoder.decodeSingularMessageField(value: &v)
                if let v { message = .event(v) }
            case 3:
                var v: Ramen_V1_HeartbeatAck?
                try decoder.decodeSingularMessageField(value: &v)
                if let v { message = .heartbeatAck(v) }
            case 4:
                var v: Ramen_V1_Error?
                try decoder.decodeSingularMessageField(value: &v)
                if let v { message = .error(v) }
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        switch message {
        case .subscribeResponse(let v):
            try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
        case .event(let v):
            try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
        case .heartbeatAck(let v):
            try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
        case .error(let v):
            try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
        case nil:
            break
        }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.message == rhs.message && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - ReplayRequest

public struct Ramen_V1_ReplayRequest: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.ReplayRequest"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .standard(proto: "app_id"),
        2: .standard(proto: "user_id"),
        3: .standard(proto: "after_seq"),
        4: .same(proto: "limit"),
    ]

    public var appID: String = ""   // = 1
    public var userID: String = ""  // = 2
    public var afterSeq: Int64 = 0  // = 3
    public var limit: Int32 = 0     // = 4

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeSingularStringField(value: &appID)
            case 2: try decoder.decodeSingularStringField(value: &userID)
            case 3: try decoder.decodeSingularInt64Field(value: &afterSeq)
            case 4: try decoder.decodeSingularInt32Field(value: &limit)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if !appID.isEmpty { try visitor.visitSingularStringField(value: appID, fieldNumber: 1) }
        if !userID.isEmpty { try visitor.visitSingularStringField(value: userID, fieldNumber: 2) }
        if afterSeq != 0 { try visitor.visitSingularInt64Field(value: afterSeq, fieldNumber: 3) }
        if limit != 0 { try visitor.visitSingularInt32Field(value: limit, fieldNumber: 4) }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.appID == rhs.appID && lhs.userID == rhs.userID
            && lhs.afterSeq == rhs.afterSeq && lhs.limit == rhs.limit
            && lhs.unknownFields == rhs.unknownFields
    }
}

// MARK: - ReplayResponse

public struct Ramen_V1_ReplayResponse: Sendable, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
    public static let protoMessageName = "ramen.v1.ReplayResponse"
    public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
        1: .same(proto: "events"),
        2: .standard(proto: "has_more"),
        3: .standard(proto: "highest_seq"),
    ]

    public var events: [Ramen_V1_EventEnvelope] = []    // = 1
    public var hasMore: Bool = false                     // = 2
    public var highestSeq: Int64 = 0                     // = 3

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}

    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let fieldNumber = try decoder.nextFieldNumber() {
            switch fieldNumber {
            case 1: try decoder.decodeRepeatedMessageField(value: &events)
            case 2: try decoder.decodeSingularBoolField(value: &hasMore)
            case 3: try decoder.decodeSingularInt64Field(value: &highestSeq)
            default: break
            }
        }
    }

    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if !events.isEmpty { try visitor.visitRepeatedMessageField(value: events, fieldNumber: 1) }
        if hasMore { try visitor.visitSingularBoolField(value: hasMore, fieldNumber: 2) }
        if highestSeq != 0 { try visitor.visitSingularInt64Field(value: highestSeq, fieldNumber: 3) }
        try unknownFields.traverse(visitor: &visitor)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.events == rhs.events && lhs.hasMore == rhs.hasMore
            && lhs.highestSeq == rhs.highestSeq && lhs.unknownFields == rhs.unknownFields
    }
}
