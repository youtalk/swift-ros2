// StdMsgs.swift
// std_msgs basic types

import SwiftROS2CDR

/// std_msgs/msg/String
public struct StringMsg: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "std_msgs/msg/String",
        typeHash: "RIHS01_df668c740482bbd48fb39d76a70dfd4bd59db1288021743503259e948f6b1a18"
    )

    public var data: String

    public init(data: String = "") {
        self.data = data
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        encoder.writeString(data)
    }

    public init(from decoder: CDRDecoder) throws {
        self.data = try decoder.readString()
    }
}

/// std_msgs/msg/Bool
public struct BoolMsg: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "std_msgs/msg/Bool",
        typeHash: "RIHS01_feb91e995ff9ebd09c0cb3d2aed18b11077585839fb5db80193b62d74528f6c9"
    )

    public var data: Bool

    public init(data: Bool = false) {
        self.data = data
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        encoder.writeBool(data)
    }

    public init(from decoder: CDRDecoder) throws {
        self.data = try decoder.readBool()
    }
}

/// std_msgs/msg/Int32
public struct Int32Msg: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "std_msgs/msg/Int32",
        typeHash: "RIHS01_b6578ded3c58c626cfe8d1a6fb6e04f706f97e9f03d2727c9ff4e74b1cef0deb"
    )

    public var data: Int32

    public init(data: Int32 = 0) {
        self.data = data
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        encoder.writeInt32(data)
    }

    public init(from decoder: CDRDecoder) throws {
        self.data = try decoder.readInt32()
    }
}

/// std_msgs/msg/Float64
public struct Float64Msg: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "std_msgs/msg/Float64",
        typeHash: "RIHS01_705ba9c3d1a09df43737eb67095534de36fd426c0587779bda2bc51fe790182a"
    )

    public var data: Double

    public init(data: Double = 0.0) {
        self.data = data
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        encoder.writeFloat64(data)
    }

    public init(from decoder: CDRDecoder) throws {
        self.data = try decoder.readFloat64()
    }
}

/// std_msgs/msg/Empty
public struct EmptyMsg: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "std_msgs/msg/Empty",
        typeHash: "RIHS01_20b625256f32d5dbc0d04fee44f43c41e51c70d3502f84b4a08e7a9c26a96312"
    )

    public init() {}

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
    }

    public init(from decoder: CDRDecoder) throws {}
}
