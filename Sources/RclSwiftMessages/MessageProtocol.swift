// MessageProtocol.swift
// Core protocols for ROS 2 message types

import Foundation
import RclSwiftCDR

/// Type information for a ROS 2 message
public struct ROS2MessageTypeInfo: Sendable {
    /// ROS format type name (e.g., "sensor_msgs/msg/Imu")
    public let typeName: String

    /// Type hash for Jazzy+ (e.g., "RIHS01_..."), nil for Humble
    public let typeHash: String?

    public init(typeName: String, typeHash: String? = nil) {
        self.typeName = typeName
        self.typeHash = typeHash
    }
}

/// Type information for a ROS 2 service
public struct ROS2ServiceTypeInfo: Sendable {
    public let serviceName: String
    public let requestTypeHash: String?
    public let responseTypeHash: String?

    public init(serviceName: String, requestTypeHash: String? = nil, responseTypeHash: String? = nil) {
        self.serviceName = serviceName
        self.requestTypeHash = requestTypeHash
        self.responseTypeHash = responseTypeHash
    }
}

/// Type information for a ROS 2 action
public struct ROS2ActionTypeInfo: Sendable {
    public let actionName: String
    public let goalTypeHash: String?
    public let resultTypeHash: String?
    public let feedbackTypeHash: String?

    public init(actionName: String, goalTypeHash: String? = nil, resultTypeHash: String? = nil, feedbackTypeHash: String? = nil) {
        self.actionName = actionName
        self.goalTypeHash = goalTypeHash
        self.resultTypeHash = resultTypeHash
        self.feedbackTypeHash = feedbackTypeHash
    }
}

// MARK: - CDR Protocols

/// Protocol for types that can be serialized to CDR format
public protocol CDREncodable {
    func encode(to encoder: CDREncoder) throws
}

/// Protocol for types that can be deserialized from CDR format
public protocol CDRDecodable {
    init(from decoder: CDRDecoder) throws
}

/// Combined CDR encoding and decoding
public typealias CDRCodable = CDREncodable & CDRDecodable

// MARK: - Message Protocols

/// Base protocol for ROS 2 message types
public protocol ROS2MessageType: Sendable {
    static var typeInfo: ROS2MessageTypeInfo { get }
}

/// A message type that can be published (encode only)
public typealias ROS2Publishable = ROS2MessageType & CDREncodable

/// A message type that can be subscribed to (decode only)
public typealias ROS2Subscribable = ROS2MessageType & CDRDecodable

/// A message type that supports both publish and subscribe
public typealias ROS2Message = ROS2MessageType & CDRCodable

// MARK: - Service Protocol

/// Protocol for ROS 2 service types
public protocol ROS2Service: Sendable {
    associatedtype Request: CDRCodable & Sendable
    associatedtype Response: CDRCodable & Sendable
    static var typeInfo: ROS2ServiceTypeInfo { get }
}

// MARK: - Action Protocol

/// Protocol for ROS 2 action types
public protocol ROS2Action: Sendable {
    associatedtype Goal: CDRCodable & Sendable
    associatedtype Result: CDRCodable & Sendable
    associatedtype Feedback: CDRCodable & Sendable
    static var typeInfo: ROS2ActionTypeInfo { get }
}

// MARK: - CDR Serialization Errors

public enum CDRSerializationError: Error, LocalizedError {
    case invalidCovarianceArraySize(expected: Int, actual: Int)
    case serializationFailed(String)
    case bufferOverflow

    public var errorDescription: String? {
        switch self {
        case .invalidCovarianceArraySize(let expected, let actual):
            return "Invalid covariance array size: expected \(expected), got \(actual)"
        case .serializationFailed(let message):
            return "Serialization failed: \(message)"
        case .bufferOverflow:
            return "Buffer overflow during serialization"
        }
    }
}
