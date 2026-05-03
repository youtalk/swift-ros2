// GoalStatusArray.swift
// action_msgs/msg/GoalStatusArray

import SwiftROS2CDR

/// ROS 2 `action_msgs/msg/GoalStatusArray`.
public struct GoalStatusArray: ROS2Message, Sendable, Equatable {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "action_msgs/msg/GoalStatusArray",
        typeHash: "RIHS01_6c1684b00f177d37438febe6e709fc4e2b0d4248dca4854946f9ed8b30cda83e"
    )

    public var statusList: [GoalStatus]

    public init(statusList: [GoalStatus] = []) {
        self.statusList = statusList
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeUInt32(UInt32(statusList.count))
        for s in statusList {
            try s.encode(to: encoder)
        }
    }

    public init(from decoder: CDRDecoder) throws {
        let count = try decoder.readUInt32()
        var out: [GoalStatus] = []
        out.reserveCapacity(Int(count))
        for _ in 0..<count {
            out.append(try GoalStatus(from: decoder))
        }
        self.statusList = out
    }
}
