// CancelGoal.swift
// action_msgs/srv/CancelGoal + CancelGoalReturnCode

import SwiftROS2CDR

/// ROS 2 `action_msgs/srv/CancelGoal` service.
public enum CancelGoalSrv: ROS2ServiceType {
    public static let typeInfo = ROS2ServiceTypeInfo(
        serviceName: "action_msgs/srv/CancelGoal",
        requestTypeName: "action_msgs/srv/CancelGoal_Request",
        responseTypeName: "action_msgs/srv/CancelGoal_Response",
        requestTypeHash: "RIHS01_3d3c84653c1f96918086887e1dcb236faec88b81a5b14fd4cf4840065bcdf8af",
        responseTypeHash: "RIHS01_35e682cf3f510e83c70a82a4aac888496dedee56773bf9d8e5e0aa81f9e1c960"
    )

    public struct Request: ROS2Message, Sendable, Equatable {
        public static let typeInfo = ROS2MessageTypeInfo(
            typeName: "action_msgs/srv/CancelGoal_Request",
            typeHash: "RIHS01_3d3c84653c1f96918086887e1dcb236faec88b81a5b14fd4cf4840065bcdf8af"
        )

        public var goalInfo: GoalInfo

        public init(goalInfo: GoalInfo = GoalInfo()) {
            self.goalInfo = goalInfo
        }

        public func encode(to encoder: CDREncoder) throws {
            encoder.writeEncapsulationHeader()
            try goalInfo.encode(to: encoder)
        }

        public init(from decoder: CDRDecoder) throws {
            self.goalInfo = try GoalInfo(from: decoder)
        }
    }

    public struct Response: ROS2Message, Sendable, Equatable {
        public static let typeInfo = ROS2MessageTypeInfo(
            typeName: "action_msgs/srv/CancelGoal_Response",
            typeHash: "RIHS01_35e682cf3f510e83c70a82a4aac888496dedee56773bf9d8e5e0aa81f9e1c960"
        )

        public var returnCode: Int8
        public var goalsCanceling: [GoalInfo]

        public init(returnCode: Int8 = 0, goalsCanceling: [GoalInfo] = []) {
            self.returnCode = returnCode
            self.goalsCanceling = goalsCanceling
        }

        public func encode(to encoder: CDREncoder) throws {
            encoder.writeEncapsulationHeader()
            encoder.writeInt8(returnCode)
            encoder.writeUInt32(UInt32(goalsCanceling.count))
            for g in goalsCanceling {
                try g.encode(to: encoder)
            }
        }

        public init(from decoder: CDRDecoder) throws {
            self.returnCode = try decoder.readInt8()
            let count = try decoder.readUInt32()
            var out: [GoalInfo] = []
            out.reserveCapacity(Int(count))
            for _ in 0..<count {
                out.append(try GoalInfo(from: decoder))
            }
            self.goalsCanceling = out
        }
    }
}

/// Symbolic names for the `int8 return_code` field on ``CancelGoalSrv/Response``.
public enum CancelGoalReturnCode: Int8, Sendable, CaseIterable {
    case none = 0
    case rejected = 1
    case unknownGoalId = 2
    case goalTerminated = 3
}
