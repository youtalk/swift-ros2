// MessageProtocol.swift
// Core protocols for ROS 2 message types

import Foundation
import SwiftROS2CDR

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
    /// ROS format service name (e.g., "example_interfaces/srv/AddTwoInts")
    public let serviceName: String

    /// ROS format request type name (e.g., "example_interfaces/srv/AddTwoInts_Request")
    public let requestTypeName: String

    /// ROS format response type name (e.g., "example_interfaces/srv/AddTwoInts_Response")
    public let responseTypeName: String

    /// Type hash for Jazzy+ on the request side (e.g., "RIHS01_..."), nil for Humble
    public let requestTypeHash: String?

    /// Type hash for Jazzy+ on the response side, nil for Humble
    public let responseTypeHash: String?

    public init(
        serviceName: String,
        requestTypeName: String,
        responseTypeName: String,
        requestTypeHash: String? = nil,
        responseTypeHash: String? = nil
    ) {
        self.serviceName = serviceName
        self.requestTypeName = requestTypeName
        self.responseTypeName = responseTypeName
        self.requestTypeHash = requestTypeHash
        self.responseTypeHash = responseTypeHash
    }
}

/// Type information for a ROS 2 action.
///
/// Carries the action's user-level Goal / Result / Feedback hashes plus the
/// synthesized wrapper hashes that actually travel on the wire
/// (`<Action>_SendGoal_Request`, `<Action>_SendGoal_Response`,
/// `<Action>_GetResult_Request`, `<Action>_GetResult_Response`,
/// `<Action>_FeedbackMessage`). All hashes are optional — `nil` means
/// `TypeHashNotSupported` on Jazzy or absent on Humble.
public struct ROS2ActionTypeInfo: Sendable {
    /// ROS format action name (e.g., "example_interfaces/action/Fibonacci")
    public let actionName: String

    public let goalTypeHash: String?
    public let resultTypeHash: String?
    public let feedbackTypeHash: String?

    public let sendGoalRequestTypeHash: String?
    public let sendGoalResponseTypeHash: String?
    public let getResultRequestTypeHash: String?
    public let getResultResponseTypeHash: String?
    public let feedbackMessageTypeHash: String?

    /// Legacy 3-hash initializer — kept for ABI/source compatibility with 0.6.x. Synthesized
    /// wrapper hashes default to `nil`.
    public init(
        actionName: String,
        goalTypeHash: String? = nil,
        resultTypeHash: String? = nil,
        feedbackTypeHash: String? = nil
    ) {
        self.init(
            actionName: actionName,
            goalTypeHash: goalTypeHash,
            resultTypeHash: resultTypeHash,
            feedbackTypeHash: feedbackTypeHash,
            sendGoalRequestTypeHash: nil,
            sendGoalResponseTypeHash: nil,
            getResultRequestTypeHash: nil,
            getResultResponseTypeHash: nil,
            feedbackMessageTypeHash: nil
        )
    }

    /// Full initializer — supply any subset of hashes; unknown ones stay `nil`.
    public init(
        actionName: String,
        goalTypeHash: String?,
        resultTypeHash: String?,
        feedbackTypeHash: String?,
        sendGoalRequestTypeHash: String?,
        sendGoalResponseTypeHash: String?,
        getResultRequestTypeHash: String?,
        getResultResponseTypeHash: String?,
        feedbackMessageTypeHash: String?
    ) {
        self.actionName = actionName
        self.goalTypeHash = goalTypeHash
        self.resultTypeHash = resultTypeHash
        self.feedbackTypeHash = feedbackTypeHash
        self.sendGoalRequestTypeHash = sendGoalRequestTypeHash
        self.sendGoalResponseTypeHash = sendGoalResponseTypeHash
        self.getResultRequestTypeHash = getResultRequestTypeHash
        self.getResultResponseTypeHash = getResultResponseTypeHash
        self.feedbackMessageTypeHash = feedbackMessageTypeHash
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
public protocol ROS2ServiceType: Sendable {
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

/// Errors thrown during CDR encoding or decoding of ROS 2 message payloads.
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
