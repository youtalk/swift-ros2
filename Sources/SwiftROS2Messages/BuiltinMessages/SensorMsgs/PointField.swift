// PointField.swift
// sensor_msgs/msg/PointField

import SwiftROS2CDR

/// PointField data types
public enum PointFieldDataType: UInt8, Sendable {
    case int8 = 1
    case uint8 = 2
    case int16 = 3
    case uint16 = 4
    case int32 = 5
    case uint32 = 6
    case float32 = 7
    case float64 = 8

    public var byteSize: Int {
        switch self {
        case .int8, .uint8: return 1
        case .int16, .uint16: return 2
        case .int32, .uint32, .float32: return 4
        case .float64: return 8
        }
    }
}

/// sensor_msgs/msg/PointField
public struct PointField: CDRCodable, Sendable {
    public var name: String
    public var offset: UInt32
    public var datatype: UInt8
    public var count: UInt32

    public init(name: String, offset: UInt32, datatype: PointFieldDataType, count: UInt32 = 1) {
        self.name = name
        self.offset = offset
        self.datatype = datatype.rawValue
        self.count = count
    }

    public init(name: String, offset: UInt32, datatype: UInt8, count: UInt32 = 1) {
        self.name = name
        self.offset = offset
        self.datatype = datatype
        self.count = count
    }

    // MARK: - Standard Fields

    public static func x(offset: UInt32 = 0) -> PointField {
        PointField(name: "x", offset: offset, datatype: .float32)
    }

    public static func y(offset: UInt32 = 4) -> PointField {
        PointField(name: "y", offset: offset, datatype: .float32)
    }

    public static func z(offset: UInt32 = 8) -> PointField {
        PointField(name: "z", offset: offset, datatype: .float32)
    }

    public static func rgb(offset: UInt32 = 12) -> PointField {
        PointField(name: "rgb", offset: offset, datatype: .uint32)
    }

    public static var xyzFields: [PointField] {
        [.x(), .y(), .z()]
    }

    public static var xyzrgbFields: [PointField] {
        [.x(), .y(), .z(), .rgb()]
    }

    // MARK: - CDR

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeString(name)
        encoder.writeUInt32(offset)
        encoder.writeUInt8(datatype)
        encoder.writeUInt32(count)
    }

    public init(from decoder: CDRDecoder) throws {
        self.name = try decoder.readString()
        self.offset = try decoder.readUInt32()
        self.datatype = try decoder.readUInt8()
        self.count = try decoder.readUInt32()
    }
}
