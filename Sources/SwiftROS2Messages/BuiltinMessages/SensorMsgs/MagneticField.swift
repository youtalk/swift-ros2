// MagneticField.swift
// sensor_msgs/msg/MagneticField

import Foundation
import SwiftROS2CDR

/// sensor_msgs/msg/MagneticField
public struct MagneticField: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/MagneticField",
        typeHash: "RIHS01_cde4732e416541ed0489ba6e7aa368c3af6a1b83dcb839e3af88a3a5e5cd4b40"
    )

    public var header: Header
    public var magneticField: Vector3
    public var magneticFieldCovariance: [Double]

    public init(
        header: Header = Header(),
        magneticField: Vector3 = Vector3(),
        magneticFieldCovariance: [Double] = CovarianceConstants.zeroCovariance3x3()
    ) {
        self.header = header
        self.magneticField = magneticField
        self.magneticFieldCovariance = magneticFieldCovariance
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        try magneticField.encode(to: encoder)
        encoder.writeFloat64Array(magneticFieldCovariance)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.magneticField = try Vector3(from: decoder)
        self.magneticFieldCovariance = try decoder.readFloat64Array(count: 9)
    }
}
