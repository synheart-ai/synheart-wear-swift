// Copyright 2026 Synheart. Hand-written gRPC client stub for ramen.v1.RAMENService.
//
// Equivalent to protoc-gen-grpc-swift output. Can be replaced with generated
// code when a protoc build step is added to CI.

import GRPC
import NIOCore
import SwiftProtobuf

// MARK: - NIO Client (callback-based)

/// NIO-based gRPC client for the RAMEN Subscribe and Replay RPCs.
///
/// Uses the NIO (EventLoopFuture) API from grpc-swift 1.x, which is the
/// most stable path for bidirectional streaming. The `RamenClient` wraps
/// this with Combine publishers and async/await convenience.
public final class Ramen_V1_RAMENServiceNIOClient: GRPCClient {
    public let channel: GRPCChannel
    public var defaultCallOptions: CallOptions
    public var interceptors: Ramen_V1_RAMENServiceClientInterceptorFactoryProtocol?

    public init(
        channel: GRPCChannel,
        defaultCallOptions: CallOptions = CallOptions(),
        interceptors: Ramen_V1_RAMENServiceClientInterceptorFactoryProtocol? = nil
    ) {
        self.channel = channel
        self.defaultCallOptions = defaultCallOptions
        self.interceptors = interceptors
    }

    // MARK: - Subscribe (bidirectional streaming)

    /// Opens a bidirectional Subscribe stream.
    ///
    /// - Parameters:
    ///   - callOptions: Per-call options (merged with defaults).
    ///   - handler: Callback invoked for each `ServerMessage` received.
    /// - Returns: `BidirectionalStreamingCall` on which the caller sends
    ///   `ClientMessage`s via `sendMessage(_:)`.
    public func subscribe(
        callOptions: CallOptions? = nil,
        handler: @escaping (Ramen_V1_ServerMessage) -> Void
    ) -> BidirectionalStreamingCall<Ramen_V1_ClientMessage, Ramen_V1_ServerMessage> {
        return makeBidirectionalStreamingCall(
            path: "/ramen.v1.RAMENService/Subscribe",
            callOptions: callOptions ?? defaultCallOptions,
            interceptors: interceptors?.makeSubscribeInterceptors() ?? [],
            handler: handler
        )
    }

    // MARK: - Replay (unary)

    /// Fetches historical events after a given sequence number.
    ///
    /// - Parameters:
    ///   - request: Replay request.
    ///   - callOptions: Per-call options (merged with defaults).
    /// - Returns: `UnaryCall` whose `.response` future resolves to `ReplayResponse`.
    public func replay(
        _ request: Ramen_V1_ReplayRequest,
        callOptions: CallOptions? = nil
    ) -> UnaryCall<Ramen_V1_ReplayRequest, Ramen_V1_ReplayResponse> {
        return makeUnaryCall(
            path: "/ramen.v1.RAMENService/Replay",
            request: request,
            callOptions: callOptions ?? defaultCallOptions,
            interceptors: interceptors?.makeReplayInterceptors() ?? []
        )
    }
}

// MARK: - Interceptor Factory Protocol

/// Factory protocol for creating per-call interceptors.
/// Implement this to add logging, metrics, or auth interceptors.
public protocol Ramen_V1_RAMENServiceClientInterceptorFactoryProtocol: Sendable {
    func makeSubscribeInterceptors() -> [ClientInterceptor<Ramen_V1_ClientMessage, Ramen_V1_ServerMessage>]
    func makeReplayInterceptors() -> [ClientInterceptor<Ramen_V1_ReplayRequest, Ramen_V1_ReplayResponse>]
}
