// NavSatFix.swift
// sensor_msgs/msg/NavSatFix

import Foundation
import SwiftROS2CDR

/// sensor_msgs/msg/NavSatStatus
public struct NavSatStatus: CDRCodable, Sendable {
    public var status: Int8
    public var service: UInt16

    public static let statusNoFix: Int8 = -1
    public static let statusFix: Int8 = 0
    public static let statusSbasFix: Int8 = 1
    public static let statusGbassFix: Int8 = 2

    public static let serviceGPS: UInt16 = 1
    public static let serviceGLONASS: UInt16 = 2
    public static let serviceCOMPASS: UInt16 = 4
    public static let serviceGALILEO: UInt16 = 8

    public init(status: Int8 = 0, service: UInt16 = 1) {
        self.status = status
        self.service = service
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeInt8(status)
        encoder.writeUInt16(service)
    }

    public init(from decoder: CDRDecoder) throws {
        self.status = try decoder.readInt8()
        self.service = try decoder.readUInt16()
    }
}

/// sensor_msgs/msg/NavSatFix
public struct NavSatFix: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/NavSatFix",
        typeHash: "RIHS01_62223ab3fe210a15976021da7afddc9e200dc9ec75231c1b6a557fc598a65404"
    )

    public enum CovarianceType: UInt8, Sendable {
        case unknown = 0
        case approximated = 1
        case diagonalKnown = 2
        case known = 3
    }

    public var header: Header
    public var status: NavSatStatus
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var positionCovariance: [Double]
    public var positionCovarianceType: UInt8

    public init(
        header: Header = Header(),
        status: NavSatStatus = NavSatStatus(),
        latitude: Double = 0.0,
        longitude: Double = 0.0,
        altitude: Double = .nan,
        positionCovariance: [Double] = Array(repeating: 0.0, count: 9),
        positionCovarianceType: CovarianceType = .unknown
    ) {
        self.header = header
        self.status = status
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.positionCovariance = positionCovariance.count == 9 ? positionCovariance : Array(repeating: 0.0, count: 9)
        self.positionCovarianceType = positionCovarianceType.rawValue
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        try status.encode(to: encoder)
        encoder.writeFloat64(latitude)
        encoder.writeFloat64(longitude)
        encoder.writeFloat64(altitude)
        encoder.writeFloat64Array(positionCovariance)
        encoder.writeUInt8(positionCovarianceType)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.status = try NavSatStatus(from: decoder)
        self.latitude = try decoder.readFloat64()
        self.longitude = try decoder.readFloat64()
        self.altitude = try decoder.readFloat64()
        self.positionCovariance = try decoder.readFloat64Array(count: 9)
        self.positionCovarianceType = try decoder.readUInt8()
    }
}
