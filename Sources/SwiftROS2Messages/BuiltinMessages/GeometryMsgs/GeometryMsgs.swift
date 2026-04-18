// GeometryMsgs.swift
// geometry_msgs stamped types

import Foundation
import SwiftROS2CDR

/// geometry_msgs/msg/TwistStamped
public struct TwistStamped: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "geometry_msgs/msg/TwistStamped",
        typeHash: "RIHS01_5f0fcd4f81d5d06ad9b4c4c63e3ea51b82d6ae4d0558f1d475229b1121db6f64"
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
        typeHash: "RIHS01_10f3786d7d40fd2b54367835614bff85d4ad3b5dab62bf8bca0cc232d73b4cd8"
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
        typeHash: "RIHS01_0a241f87d04668d94099cbb5ba11691d5ad32c2f29682e4eb5653424bd275206"
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
