// Imu.swift
// sensor_msgs/msg/Imu

import Foundation
import RclSwiftCDR

/// sensor_msgs/msg/Imu
public struct Imu: ROS2Message, Equatable {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/Imu",
        typeHash: "RIHS01_7d9a00ff131080897a5ec7e26e315954b8eae3353c3f995c55faf71574000b5b"
    )

    public var header: Header
    public var orientation: Quaternion
    public var orientationCovariance: [Double]
    public var angularVelocity: Vector3
    public var angularVelocityCovariance: [Double]
    public var linearAcceleration: Vector3
    public var linearAccelerationCovariance: [Double]

    public init(
        header: Header = Header(),
        orientation: Quaternion = Quaternion(),
        orientationCovariance: [Double] = CovarianceConstants.unknownCovariance3x3(),
        angularVelocity: Vector3 = Vector3(),
        angularVelocityCovariance: [Double] = CovarianceConstants.unknownCovariance3x3(),
        linearAcceleration: Vector3 = Vector3(),
        linearAccelerationCovariance: [Double] = CovarianceConstants.unknownCovariance3x3()
    ) {
        self.header = header
        self.orientation = orientation
        self.orientationCovariance = orientationCovariance
        self.angularVelocity = angularVelocity
        self.angularVelocityCovariance = angularVelocityCovariance
        self.linearAcceleration = linearAcceleration
        self.linearAccelerationCovariance = linearAccelerationCovariance
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        try orientation.encode(to: encoder)
        encoder.writeFloat64Array(orientationCovariance)
        try angularVelocity.encode(to: encoder)
        encoder.writeFloat64Array(angularVelocityCovariance)
        try linearAcceleration.encode(to: encoder)
        encoder.writeFloat64Array(linearAccelerationCovariance)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.orientation = try Quaternion(from: decoder)
        self.orientationCovariance = try decoder.readFloat64Array(count: 9)
        self.angularVelocity = try Vector3(from: decoder)
        self.angularVelocityCovariance = try decoder.readFloat64Array(count: 9)
        self.linearAcceleration = try Vector3(from: decoder)
        self.linearAccelerationCovariance = try decoder.readFloat64Array(count: 9)
    }
}
