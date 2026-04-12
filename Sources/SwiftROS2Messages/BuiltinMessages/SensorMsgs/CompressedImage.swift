// CompressedImage.swift
// sensor_msgs/msg/CompressedImage

import Foundation
import SwiftROS2CDR

/// sensor_msgs/msg/CompressedImage
public struct CompressedImage: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/CompressedImage",
        typeHash: "RIHS01_15640771531571185e2efc8a100baf923961a4d15d5569652e6cb6691e8e371a"
    )

    public var header: Header
    public var format: String
    public var data: Data

    public init(header: Header = Header(), format: String = "jpeg", data: Data = Data()) {
        self.header = header
        self.format = format
        self.data = data
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeString(format)
        encoder.writeUInt8Sequence(data)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.format = try decoder.readString()
        self.data = try decoder.readUInt8Sequence()
    }
}
