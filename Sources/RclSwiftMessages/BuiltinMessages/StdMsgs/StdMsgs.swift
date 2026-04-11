// StdMsgs.swift
// std_msgs basic types

import Foundation
import RclSwiftCDR

/// std_msgs/msg/String
public struct StringMsg: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "std_msgs/msg/String",
        typeHash: "RIHS01_f9b447fc04e9cc582e799e86fb0a33e6f1de76834ec9de631e0e8c2eab8ba8f3"
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
        typeHash: "RIHS01_80aaada1b4c63b2cc6ec3dc5e61ec5dd84dc37fd41da8d3c73631d37e0a4dd73"
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
        typeHash: "RIHS01_58c48d1e21af9e1ca38ed3cec6ed43e6e47beb37ee0b7c3b12dc2ab27f7e44fc"
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
        typeHash: "RIHS01_57d0eff56e72ce4ea0fda44c75c42e04f4eb5dea39f2c8cd20db72e7eab76a5c"
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
        typeHash: "RIHS01_d6a64ffc91cefc5b56cc2b0488c4e3df1b58f83923a9c07f8e93e7c52a46c5b3"
    )

    public init() {}

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
    }

    public init(from decoder: CDRDecoder) throws {}
}
