// TransportSession.swift
// Transport abstraction protocols

import Foundation
import SwiftROS2CDR
import SwiftROS2Wire

// MARK: - Transport Session Protocol

/// Protocol for transport session lifecycle management
///
/// Implementations provide the actual transport mechanism:
/// - Zenoh: via zenoh-pico C-FFI
/// - DDS: via CycloneDDS C-FFI
public protocol TransportSession: AnyObject, Sendable {
    var isConnected: Bool { get }
    var transportType: TransportType { get }
    var sessionId: String { get }

    func open(config: TransportConfig) async throws
    func close() throws
    func checkHealth() -> Bool

    /// Create a publisher for a topic
    func createPublisher(
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: TransportQoS
    ) throws -> any TransportPublisher

    /// Create a subscriber for a topic
    func createSubscriber(
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) throws -> any TransportSubscriber

    /// Create a Service Server.
    ///
    /// `serviceTypeName` is the ROS-format service type name (e.g.
    /// `std_srvs/srv/Trigger`). Each transport derives the wire-level naming
    /// from this: DDS uses `DDSWireCodec.serviceTopicNames` to build the
    /// `rq/<service>Request` / `rr/<service>Reply` topic pair plus
    /// `<pkg>::srv::dds_::<Type>_Request_` / `_Response_` type names; Zenoh
    /// uses `ZenohWireCodec.makeServiceKeyExpr` to build the queryable key
    /// expression. Callers do not need to pre-derive any of this.
    func createServiceServer(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data) async throws -> Data
    ) throws -> any TransportService

    /// Create a Service Client.
    ///
    /// `serviceTypeName` is the ROS-format service type name (e.g.
    /// `std_srvs/srv/Trigger`). Each transport derives the wire-level naming
    /// from this: DDS uses `DDSWireCodec.serviceTopicNames`; Zenoh uses
    /// `ZenohWireCodec.makeServiceKeyExpr`. Callers do not need to pre-derive
    /// any of it.
    func createServiceClient(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS
    ) throws -> any TransportClient
}

// MARK: - Transport Publisher Protocol

/// An active publisher handle that writes pre-serialized CDR payloads to a transport.
///
/// Conforming types are returned by ``TransportSession/createPublisher(topic:typeName:typeHash:qos:)``
/// and must remain sendable across concurrency domains.
public protocol TransportPublisher: Sendable {
    func publish(data: Data, timestamp: UInt64, sequenceNumber: Int64) throws
    func close() throws
    var topic: String { get }
    var isActive: Bool { get }
}

// MARK: - Transport Subscriber Protocol

/// An active subscriber handle that receives raw CDR payloads from a transport.
///
/// Conforming types are returned by ``TransportSession/createSubscriber(topic:typeName:typeHash:qos:handler:)``
/// and must remain sendable across concurrency domains.
public protocol TransportSubscriber: Sendable {
    var topic: String { get }
    var isActive: Bool { get }
    func close() throws
}

// MARK: - Transport Service / Client (Service Server / Service Client)

/// An active Service Server handle.
///
/// The handler closure passed at creation time receives raw CDR request bytes
/// and is expected to return raw CDR response bytes. The transport layer is
/// untyped on purpose — `ROS2Service<S>` on top encodes / decodes typed values.
public protocol TransportService: Sendable {
    var name: String { get }
    var isActive: Bool { get }
    func close() throws
}

/// An active Service Client handle.
///
/// `call` operates on raw CDR. The `ROS2Client<S>` layer encodes the typed
/// request, invokes this method, and decodes the typed response.
public protocol TransportClient: Sendable {
    var name: String { get }
    var isActive: Bool { get }
    func waitForService(timeout: Duration) async throws
    /// Send pre-encoded CDR request, await pre-encoded CDR response.
    /// Throws `TransportError.requestTimeout` on deadline,
    /// `TransportError.requestCancelled` on parent-Task cancellation.
    func call(requestCDR: Data, timeout: Duration) async throws -> Data
    func close() throws
}

// MARK: - Transport QoS

/// Quality-of-service settings used internally by the transport layer.
///
/// End users should prefer the higher-level ``QoSProfile`` presets; `TransportQoS` is derived
/// automatically from a `QoSProfile` when creating publishers and subscriptions.
public struct TransportQoS: Sendable, Equatable {
    public enum Reliability: String, Sendable {
        case reliable
        case bestEffort = "best_effort"
    }

    public enum Durability: String, Sendable {
        case volatile
        case transientLocal = "transient_local"
    }

    public enum History: Sendable, Equatable {
        case keepLast(Int)
        case keepAll
    }

    public let reliability: Reliability
    public let durability: Durability
    public let history: History

    public static let sensorData = TransportQoS(
        reliability: .reliable,
        durability: .volatile,
        history: .keepLast(10)
    )

    public static let bestEffort = TransportQoS(
        reliability: .bestEffort,
        durability: .volatile,
        history: .keepLast(1)
    )

    public static let `default` = sensorData

    public init(
        reliability: Reliability = .reliable,
        durability: Durability = .volatile,
        history: History = .keepLast(10)
    ) {
        self.reliability = reliability
        self.durability = durability
        self.history = history
    }
}

// MARK: - Transport Errors

/// Errors thrown by transport session operations such as connect, publish, and subscribe.
///
/// Check ``isRecoverable`` to decide whether a retry is appropriate.
public enum TransportError: Error, LocalizedError {
    case connectionFailed(String)
    case connectionTimeout(TimeInterval)
    case alreadyConnected
    case notConnected
    case publisherCreationFailed(String)
    case subscriberCreationFailed(String)
    case publishFailed(String)
    case publisherClosed
    case sessionUnhealthy(String)
    case sessionClosed
    case invalidConfiguration(String)
    case unsupportedFeature(String)
    case requestTimeout(Duration)
    case requestCancelled
    case serviceHandlerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .connectionTimeout(let t): return "Connection timed out after \(Int(t))s"
        case .alreadyConnected: return "Already connected"
        case .notConnected: return "Not connected"
        case .publisherCreationFailed(let msg): return "Failed to create publisher: \(msg)"
        case .subscriberCreationFailed(let msg): return "Failed to create subscriber: \(msg)"
        case .publishFailed(let msg): return "Publish failed: \(msg)"
        case .publisherClosed: return "Publisher is closed"
        case .sessionUnhealthy(let msg): return "Session unhealthy: \(msg)"
        case .sessionClosed: return "Session is closed"
        case .invalidConfiguration(let msg): return "Invalid configuration: \(msg)"
        case .unsupportedFeature(let f): return "Unsupported feature: \(f)"
        case .requestTimeout(let d): return "Service request timed out after \(d)"
        case .requestCancelled: return "Service request was cancelled"
        case .serviceHandlerFailed(let msg): return "Service handler failed: \(msg)"
        }
    }

    public var isRecoverable: Bool {
        switch self {
        case .connectionFailed, .connectionTimeout, .publishFailed, .sessionUnhealthy:
            return true
        default:
            return false
        }
    }
}
