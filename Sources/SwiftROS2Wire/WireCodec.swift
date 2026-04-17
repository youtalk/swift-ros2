// WireCodec.swift
// Protocol for wire format encoding

import Foundation

/// Protocol for generating rmw-compatible wire format elements
///
/// Implementations handle the specifics of key expression generation,
/// liveliness token construction, and attachment building for different
/// ROS 2 middleware implementations.
public protocol WireCodec: Sendable {
    /// Generate a key expression for a topic
    func makeKeyExpr(
        domainId: Int,
        namespace: String,
        topic: String,
        typeName: String,
        typeHash: String?
    ) -> String

    /// Generate a liveliness token for ROS 2 discovery
    func makeLivelinessToken(
        domainId: Int,
        sessionId: String,
        nodeId: String,
        entityId: String,
        namespace: String,
        nodeName: String,
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: QoSPolicy
    ) -> String

    /// Build attachment metadata for published messages
    func buildAttachment(
        seq: Int64,
        tsNsec: Int64,
        gid: [UInt8]
    ) -> Data
}

/// QoS policy for wire format encoding (transport-agnostic)
public struct QoSPolicy: Sendable, Equatable {
    public enum Reliability: Int, Sendable {
        case bestEffort = 0
        case reliable = 1
    }

    public enum Durability: Int, Sendable {
        case transientLocal = 1
        case volatile = 2
    }

    public enum HistoryPolicy: Int, Sendable {
        case keepLast = 0
        case keepAll = 1
    }

    public var reliability: Reliability
    public var durability: Durability
    public var historyPolicy: HistoryPolicy
    public var historyDepth: Int

    public init(
        reliability: Reliability = .bestEffort,
        durability: Durability = .volatile,
        historyPolicy: HistoryPolicy = .keepLast,
        historyDepth: Int = 10
    ) {
        self.reliability = reliability
        self.durability = durability
        self.historyPolicy = historyPolicy
        self.historyDepth = historyDepth
    }

    /// Encode QoS for liveliness token
    ///
    /// Format: `reliability:durability:history,depth:deadline:lifespan:liveliness`
    public func toKeyExpr() -> String {
        let relStr = reliability == .bestEffort ? "" : String(reliability.rawValue)
        let durStr = durability == .volatile ? "" : String(durability.rawValue)
        let histStr = historyPolicy == .keepLast ? "" : String(historyPolicy.rawValue)
        let depthStr = String(historyDepth)
        return "\(relStr):\(durStr):\(histStr),\(depthStr):,:,:,,"
    }

    // MARK: - Presets

    public static let `default` = QoSPolicy()

    public static let sensorData = QoSPolicy(
        reliability: .bestEffort,
        durability: .volatile,
        historyPolicy: .keepLast,
        historyDepth: 10
    )

    public static let latched = QoSPolicy(
        reliability: .reliable,
        durability: .transientLocal,
        historyPolicy: .keepLast,
        historyDepth: 1
    )

    public static let reliableSensor = QoSPolicy(
        reliability: .reliable,
        durability: .volatile,
        historyPolicy: .keepLast,
        historyDepth: 10
    )

    public static let servicesDefault = QoSPolicy(
        reliability: .reliable,
        durability: .volatile,
        historyPolicy: .keepLast,
        historyDepth: 10
    )
}
