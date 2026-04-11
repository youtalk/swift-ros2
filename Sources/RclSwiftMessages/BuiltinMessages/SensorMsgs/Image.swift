// Image.swift
// sensor_msgs/msg/Image

import Foundation
import RclSwiftCDR

/// sensor_msgs/msg/Image
public struct Image: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/Image",
        typeHash: "RIHS01_d31d41a9a4c4bc8eae9be757b0beed306564f7526c88ea6a4588fb9582527d47"
    )

    public var header: Header
    public var height: UInt32
    public var width: UInt32
    public var encoding: String
    public var isBigendian: UInt8
    public var step: UInt32
    public var data: Data

    public init(
        header: Header = Header(),
        height: UInt32 = 0,
        width: UInt32 = 0,
        encoding: String = "rgb8",
        isBigendian: UInt8 = 0,
        step: UInt32 = 0,
        data: Data = Data()
    ) {
        self.header = header
        self.height = height
        self.width = width
        self.encoding = encoding
        self.isBigendian = isBigendian
        self.step = step
        self.data = data
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeUInt32(height)
        encoder.writeUInt32(width)
        encoder.writeString(encoding)
        encoder.writeUInt8(isBigendian)
        encoder.writeUInt32(step)
        encoder.writeUInt8Sequence(data)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.height = try decoder.readUInt32()
        self.width = try decoder.readUInt32()
        self.encoding = try decoder.readString()
        self.isBigendian = try decoder.readUInt8()
        self.step = try decoder.readUInt32()
        self.data = try decoder.readUInt8Sequence()
    }
}
