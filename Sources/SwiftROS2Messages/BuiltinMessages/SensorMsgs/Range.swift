// Range.swift
// sensor_msgs/msg/Range

import Foundation
import SwiftROS2CDR

/// sensor_msgs/msg/Range
public struct Range: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/Range",
        typeHash: "RIHS01_b42b62562e93cbfe9d42b82fe5994dfa3d63d7d5c90a317981703f7388adff3a"
    )

    public enum RadiationType: UInt8, Sendable {
        case ultrasound = 0
        case infrared = 1
    }

    public var header: Header
    public var radiationType: UInt8
    public var fieldOfView: Float
    public var minRange: Float
    public var maxRange: Float
    public var range: Float
    public var variance: Float

    public init(
        header: Header = Header(),
        radiationType: RadiationType = .infrared,
        fieldOfView: Float = 0.0,
        minRange: Float = 0.0,
        maxRange: Float = 0.0,
        range: Float = 0.0,
        variance: Float = 0.0
    ) {
        self.header = header
        self.radiationType = radiationType.rawValue
        self.fieldOfView = fieldOfView
        self.minRange = minRange
        self.maxRange = maxRange
        self.range = range
        self.variance = variance
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeUInt8(radiationType)
        encoder.writeFloat32(fieldOfView)
        encoder.writeFloat32(minRange)
        encoder.writeFloat32(maxRange)
        encoder.writeFloat32(range)
        // `variance` was added to sensor_msgs/Range after Humble — skip on legacy wire.
        if !encoder.isLegacyDistro {
            encoder.writeFloat32(variance)
        }
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.radiationType = try decoder.readUInt8()
        self.fieldOfView = try decoder.readFloat32()
        self.minRange = try decoder.readFloat32()
        self.maxRange = try decoder.readFloat32()
        self.range = try decoder.readFloat32()
        if decoder.isLegacyDistro {
            self.variance = 0
        } else {
            self.variance = try decoder.readFloat32()
        }
    }
}
