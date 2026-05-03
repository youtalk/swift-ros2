// GoalStatus.swift
// action_msgs/msg/GoalStatus + GoalStatusCode

import SwiftROS2CDR

/// ROS 2 `action_msgs/msg/GoalStatus`.
///
/// Nested CDR payload — embedded inside `GoalStatusArray` (the actual
/// top-level wire message). Conforms to `CDRCodable` only so it cannot be
/// advertised through `ROS2Publisher` directly. Same convention as `Header`.
public struct GoalStatus: CDRCodable, Sendable, Equatable {
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
