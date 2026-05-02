// CameraInfo.swift
// sensor_msgs/msg/CameraInfo

import SwiftROS2CDR

/// sensor_msgs/msg/CameraInfo
public struct CameraInfo: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "sensor_msgs/msg/CameraInfo",
        typeHash: "RIHS01_b3dfd68ff46c9d56c80fd3bd4ed22c7a4ddce8c8348f2f59c299e73118e7e275"
    )

    public var header: Header
    public var height: UInt32
    public var width: UInt32
    public var distortionModel: String
    public var d: [Double]  // distortion parameters (variable length)
    public var k: [Double]  // intrinsic camera matrix (3x3 = 9)
    public var r: [Double]  // rectification matrix (3x3 = 9)
    public var p: [Double]  // projection matrix (3x4 = 12)
    public var binningX: UInt32
    public var binningY: UInt32
    public var roi: RegionOfInterest

    public init(
        header: Header = Header(),
        height: UInt32 = 0,
        width: UInt32 = 0,
        distortionModel: String = "plumb_bob",
        d: [Double] = [],
        k: [Double] = Array(repeating: 0.0, count: 9),
        r: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1],
        p: [Double] = Array(repeating: 0.0, count: 12),
        binningX: UInt32 = 0,
        binningY: UInt32 = 0,
        roi: RegionOfInterest = RegionOfInterest()
    ) {
        self.header = header
        self.height = height
        self.width = width
        self.distortionModel = distortionModel
        self.d = d
        self.k = k.count == 9 ? k : Array(repeating: 0.0, count: 9)
        self.r = r.count == 9 ? r : [1, 0, 0, 0, 1, 0, 0, 0, 1]
        self.p = p.count == 12 ? p : Array(repeating: 0.0, count: 12)
        self.binningX = binningX
        self.binningY = binningY
        self.roi = roi
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeUInt32(height)
        encoder.writeUInt32(width)
        encoder.writeString(distortionModel)
        encoder.writeFloat64Sequence(d)  // variable-length sequence
        encoder.writeFloat64Array(k)  // fixed 9
        encoder.writeFloat64Array(r)  // fixed 9
        encoder.writeFloat64Array(p)  // fixed 12
        encoder.writeUInt32(binningX)
        encoder.writeUInt32(binningY)
        try roi.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.height = try decoder.readUInt32()
        self.width = try decoder.readUInt32()
        self.distortionModel = try decoder.readString()
        self.d = try decoder.readFloat64Sequence()
        self.k = try decoder.readFloat64Array(count: 9)
        self.r = try decoder.readFloat64Array(count: 9)
        self.p = try decoder.readFloat64Array(count: 12)
        self.binningX = try decoder.readUInt32()
        self.binningY = try decoder.readUInt32()
        self.roi = try RegionOfInterest(from: decoder)
    }
}
