// Temperature.swift
// sensor_msgs/msg/Temperature

import Foundation
import RclSwiftCDR

/// sensor_msgs/msg/Temperature
public struct Temperature: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/Temperature",
        typeHash: "RIHS01_84b54121c59a5e31f248acd989e552b94e16e0dbf4d10a8e2e93f150f5f3d89c"
    )

    public var header: Header
    public var temperature: Double
    public var variance: Double

    public init(header: Header = Header(), temperature: Double = 0.0, variance: Double = 0.0) {
        self.header = header
        self.temperature = temperature
        self.variance = variance
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeFloat64(temperature)
        encoder.writeFloat64(variance)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.temperature = try decoder.readFloat64()
        self.variance = try decoder.readFloat64()
    }
}
