// GoalInfo.swift
// action_msgs/msg/GoalInfo

import SwiftROS2CDR

/// ROS 2 `action_msgs/msg/GoalInfo`.
public struct GoalInfo: ROS2Message, Sendable, Equatable {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "action_msgs/msg/GoalInfo",
        typeHash: "RIHS01_6398fe763154554353930716b225947f93b672f0fb2e49fdd01bb7a7e37933e9"
    )

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
