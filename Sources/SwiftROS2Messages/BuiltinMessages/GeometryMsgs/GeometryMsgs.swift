// GeometryMsgs.swift
// geometry_msgs stamped types

import Foundation
import SwiftROS2CDR

/// geometry_msgs/msg/TwistStamped
public struct TwistStamped: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "geometry_msgs/msg/TwistStamped",
        typeHash: "RIHS01_beb0b072ca1cc0e19510aef3ff4f30b8e1cce2ceabb02cc2107b3a0e3b9b5206"
    )

    public var header: Header
    public var twist: Twist

    public init(header: Header = Header(), twist: Twist = Twist()) {
        self.header = header
        self.twist = twist
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        try twist.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.twist = try Twist(from: decoder)
    }
}

/// geometry_msgs/msg/PoseStamped
public struct PoseStamped: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "geometry_msgs/msg/PoseStamped",
        typeHash: "RIHS01_fb0a7ecfbf5a3161cb0142ec21e00be06af41cdffb4423e2d6fd0e88aee64d0b"
    )

    public var header: Header
    public var pose: Pose

    public init(header: Header = Header(), pose: Pose = Pose()) {
        self.header = header
        self.pose = pose
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        try pose.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.pose = try Pose(from: decoder)
    }
}

/// geometry_msgs/msg/TransformStamped
public struct TransformStamped: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "geometry_msgs/msg/TransformStamped",
        typeHash: "RIHS01_bc4298e76077a7ba74f3ab8d1c3d07ae3d6f834cc7ea7ee5d2a53ebdb0f0b7e7"
    )

    public var header: Header
    public var childFrameId: String
    public var transform: Transform

    public init(header: Header = Header(), childFrameId: String = "", transform: Transform = Transform()) {
        self.header = header
        self.childFrameId = childFrameId
        self.transform = transform
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeString(childFrameId)
        try transform.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.childFrameId = try decoder.readString()
        self.transform = try Transform(from: decoder)
    }
}
