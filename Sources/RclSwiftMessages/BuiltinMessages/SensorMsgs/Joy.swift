// Joy.swift
// sensor_msgs/msg/Joy

import Foundation
import RclSwiftCDR

/// sensor_msgs/msg/Joy
public struct Joy: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/Joy",
        typeHash: "RIHS01_0d356c79cad3401e35ffeb75a96a96e08be3ef896b8b83841d73e890989372c5"
    )

    public var header: Header
    public var axes: [Float]
    public var buttons: [Int32]

    public init(header: Header = Header(), axes: [Float] = [], buttons: [Int32] = []) {
        self.header = header
        self.axes = axes
        self.buttons = buttons
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeFloat32Sequence(axes)
        encoder.writeInt32Sequence(buttons)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.axes = try decoder.readFloat32Sequence()
        self.buttons = try decoder.readInt32Sequence()
    }
}
