// PointCloud2.swift
// sensor_msgs/msg/PointCloud2

import Foundation
import SwiftROS2CDR

/// sensor_msgs/msg/PointCloud2
public struct PointCloud2: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/PointCloud2",
        typeHash: "RIHS01_9198cabf7da3796ae6fe19c4cb3bdd3525492988c70522628af5daa124bae2b5"
    )

    public var header: Header
    public var height: UInt32
    public var width: UInt32
    public var fields: [PointField]
    public var isBigendian: Bool
    public var pointStep: UInt32
    public var rowStep: UInt32
    public var data: Data
    public var isDense: Bool

    public init(
        header: Header = Header(),
        height: UInt32 = 1,
        width: UInt32 = 0,
        fields: [PointField] = PointField.xyzFields,
        isBigendian: Bool = false,
        pointStep: UInt32 = 12,
        rowStep: UInt32 = 0,
        data: Data = Data(),
        isDense: Bool = true
    ) {
        self.header = header
        self.height = height
        self.width = width
        self.fields = fields
        self.isBigendian = isBigendian
        self.pointStep = pointStep
        self.rowStep = rowStep == 0 ? pointStep * width : rowStep
        self.data = data
        self.isDense = isDense
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeUInt32(height)
        encoder.writeUInt32(width)
        // PointField[] fields (sequence)
        encoder.writeUInt32(UInt32(fields.count))
        for field in fields {
            try field.encode(to: encoder)
        }
        encoder.writeBool(isBigendian)
        encoder.writeUInt32(pointStep)
        encoder.writeUInt32(rowStep)
        encoder.writeUInt8Sequence(data)
        encoder.writeBool(isDense)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.height = try decoder.readUInt32()
        self.width = try decoder.readUInt32()
        let fieldCount = Int(try decoder.readUInt32())
        var fields = [PointField]()
        fields.reserveCapacity(fieldCount)
        for _ in 0..<fieldCount {
            fields.append(try PointField(from: decoder))
        }
        self.fields = fields
        self.isBigendian = try decoder.readBool()
        self.pointStep = try decoder.readUInt32()
        self.rowStep = try decoder.readUInt32()
        self.data = try decoder.readUInt8Sequence()
        self.isDense = try decoder.readBool()
    }

    public var pointCount: Int { Int(width) * Int(height) }
}
