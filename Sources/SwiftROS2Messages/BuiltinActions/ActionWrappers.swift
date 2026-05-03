// ActionWrappers.swift
// Synthesized SendGoal / GetResult / FeedbackMessage wrappers for ROS 2 actions

import SwiftROS2CDR

/// Synthesized `<Action>_SendGoal_Request` wrapper.
///
/// On the wire: `unique_identifier_msgs/UUID goal_id; <Goal> goal`.
/// Per-action type info is supplied at publish/subscribe time by the umbrella
/// API, since the synthesized wrapper hashes vary by action type.
public struct ActionSendGoalRequest<Goal: CDRCodable & Sendable>: CDRCodable, Sendable {
    public var goalId: UniqueIdentifierUUID
    public var goal: Goal

    public init(goalId: UniqueIdentifierUUID, goal: Goal) {
        self.goalId = goalId
        self.goal = goal
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try goalId.encode(to: encoder)
        try goal.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.goalId = try UniqueIdentifierUUID(from: decoder)
        self.goal = try Goal(from: decoder)
    }
}

/// Synthesized `<Action>_SendGoal_Response` wrapper.
///
/// On the wire: `bool accepted; builtin_interfaces/Time stamp`.
public struct ActionSendGoalResponse: CDRCodable, Sendable, Equatable {
    public var accepted: Bool
    public var stamp: BuiltinInterfacesTime

    public init(accepted: Bool, stamp: BuiltinInterfacesTime) {
        self.accepted = accepted
        self.stamp = stamp
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        encoder.writeBool(accepted)
        try stamp.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.accepted = try decoder.readBool()
        self.stamp = try BuiltinInterfacesTime(from: decoder)
    }
}

/// Synthesized `<Action>_GetResult_Request` wrapper.
///
/// On the wire: `unique_identifier_msgs/UUID goal_id`.
public struct ActionGetResultRequest: CDRCodable, Sendable, Equatable {
    public var goalId: UniqueIdentifierUUID

    public init(goalId: UniqueIdentifierUUID) {
        self.goalId = goalId
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try goalId.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.goalId = try UniqueIdentifierUUID(from: decoder)
    }
}

/// Synthesized `<Action>_GetResult_Response` wrapper.
///
/// On the wire: `int8 status; <Result> result`.
public struct ActionGetResultResponse<Result: CDRCodable & Sendable>: CDRCodable, Sendable {
    public var status: Int8
    public var result: Result

    public init(status: Int8, result: Result) {
        self.status = status
        self.result = result
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        encoder.writeInt8(status)
        try result.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.status = try decoder.readInt8()
        self.result = try Result(from: decoder)
    }
}

/// Synthesized `<Action>_FeedbackMessage` wrapper.
///
/// On the wire: `unique_identifier_msgs/UUID goal_id; <Feedback> feedback`.
public struct ActionFeedbackMessage<Feedback: CDRCodable & Sendable>: CDRCodable, Sendable {
    public var goalId: UniqueIdentifierUUID
    public var feedback: Feedback

    public init(goalId: UniqueIdentifierUUID, feedback: Feedback) {
        self.goalId = goalId
        self.feedback = feedback
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try goalId.encode(to: encoder)
        try feedback.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.goalId = try UniqueIdentifierUUID(from: decoder)
        self.feedback = try Feedback(from: decoder)
    }
}
