// GoalStatus.swift
// action_msgs/msg/GoalStatus + GoalStatusCode

import SwiftROS2CDR

/// ROS 2 `action_msgs/msg/GoalStatus`.
public struct GoalStatus: ROS2Message, Sendable, Equatable {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "action_msgs/msg/GoalStatus",
        typeHash: "RIHS01_32f4cfd717735d17657e1178f24431c1ce996c878c515230f6c5b3476819dbb9"
    )

    public var goalInfo: GoalInfo
    public var status: Int8

    public init(goalInfo: GoalInfo = GoalInfo(), status: Int8 = 0) {
        self.goalInfo = goalInfo
        self.status = status
    }

    public func encode(to encoder: CDREncoder) throws {
        try goalInfo.encode(to: encoder)
        encoder.writeInt8(status)
    }

    public init(from decoder: CDRDecoder) throws {
        self.goalInfo = try GoalInfo(from: decoder)
        self.status = try decoder.readInt8()
    }
}

/// Symbolic names for the `int8 status` field on ``GoalStatus``.
public enum GoalStatusCode: Int8, Sendable, CaseIterable {
    case unknown = 0
    case accepted = 1
    case executing = 2
    case canceling = 3
    case succeeded = 4
    case canceled = 5
    case aborted = 6
}
