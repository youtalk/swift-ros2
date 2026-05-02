// RegionOfInterest.swift
// sensor_msgs/RegionOfInterest

import SwiftROS2CDR

/// sensor_msgs/RegionOfInterest
public struct RegionOfInterest: CDRCodable, Sendable, Equatable {
    public var xOffset: UInt32
    public var yOffset: UInt32
    public var height: UInt32
    public var width: UInt32
    public var doRectify: Bool

    public init(
        xOffset: UInt32 = 0, yOffset: UInt32 = 0, height: UInt32 = 0, width: UInt32 = 0, doRectify: Bool = false
    ) {
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.height = height
        self.width = width
        self.doRectify = doRectify
    }

    public static func fullFrame(width: UInt32, height: UInt32) -> RegionOfInterest {
        RegionOfInterest(xOffset: 0, yOffset: 0, height: height, width: width, doRectify: false)
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeUInt32(xOffset)
        encoder.writeUInt32(yOffset)
        encoder.writeUInt32(height)
        encoder.writeUInt32(width)
        encoder.writeBool(doRectify)
    }

    public init(from decoder: CDRDecoder) throws {
        self.xOffset = try decoder.readUInt32()
        self.yOffset = try decoder.readUInt32()
        self.height = try decoder.readUInt32()
        self.width = try decoder.readUInt32()
        self.doRectify = try decoder.readBool()
    }
}
