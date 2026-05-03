// GoalInfo.swift
// action_msgs/msg/GoalInfo

import SwiftROS2CDR

/// ROS 2 `action_msgs/msg/GoalInfo`.
///
/// Nested CDR payload — embedded in `GoalStatus`, `GoalStatusArray`, and
/// `CancelGoal` request/response. Not a standalone top-level topic, so it
/// deliberately conforms to `CDRCodable` only and cannot be advertised
/// through `ROS2Publisher`. Same convention as `Header` and `Vector3`.
public struct GoalInfo: CDRCodable, Sendable, Equatable {
    public var goalId: UniqueIdentifierUUID
    public var stamp: BuiltinInterfacesTime

    public init(
        goalId: UniqueIdentifierUUID = UniqueIdentifierUUID(),
        stamp: BuiltinInterfacesTime = BuiltinInterfacesTime()
    ) {
        self.goalId = goalId
        self.stamp = stamp
    }

    public func encode(to encoder: CDREncoder) throws {
        try goalId.encode(to: encoder)
        try stamp.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.goalId = try UniqueIdentifierUUID(from: decoder)
        self.stamp = try BuiltinInterfacesTime(from: decoder)
    }
}
