// Illuminance.swift
// sensor_msgs/msg/Illuminance

import Foundation
import RclSwiftCDR

/// sensor_msgs/msg/Illuminance
public struct Illuminance: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/Illuminance",
        typeHash: "RIHS01_d2f45928d0e7b1d6c5fa543e23c66e1cc7d104402c428c1a27a6e49e4d8e0a49"
    )

    public var header: Header
    public var illuminance: Double
    public var variance: Double

    public init(header: Header = Header(), illuminance: Double = 0.0, variance: Double = 0.0) {
        self.header = header
        self.illuminance = illuminance
        self.variance = variance
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeFloat64(illuminance)
        encoder.writeFloat64(variance)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.illuminance = try decoder.readFloat64()
        self.variance = try decoder.readFloat64()
    }
}
