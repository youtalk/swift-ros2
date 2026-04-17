// CommonTypes.swift
// Common ROS 2 types shared across multiple messages

import Foundation
import SwiftROS2CDR

// MARK: - std_msgs/Header

/// ROS 2 std_msgs/Header (stamp + frame_id)
public struct Header: CDRCodable, Sendable, Equatable {
    public var sec: UInt32
    public var nanosec: UInt32
    public var frameId: String

    public init(sec: UInt32 = 0, nanosec: UInt32 = 0, frameId: String = "") {
        self.sec = sec
        self.nanosec = nanosec
        self.frameId = frameId
    }

    public static func now(frameId: String) -> Header {
        let now = Date()
        let ti = now.timeIntervalSince1970
        let s = UInt32(ti)
        let ns = UInt32((ti - Double(s)) * 1_000_000_000)
        return Header(sec: s, nanosec: ns, frameId: frameId)
    }

    public var timestampNanoseconds: Int64 {
        Int64(sec) * 1_000_000_000 + Int64(nanosec)
    }

    // MARK: - CDR

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeUInt32(sec)
        encoder.writeUInt32(nanosec)
        encoder.writeString(frameId)
    }

    public init(from decoder: CDRDecoder) throws {
        self.sec = try decoder.readUInt32()
        self.nanosec = try decoder.readUInt32()
        self.frameId = try decoder.readString()
    }
}

// MARK: - geometry_msgs/Vector3

public struct Vector3: CDRCodable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double = 0.0, y: Double = 0.0, z: Double = 0.0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeFloat64(x)
        encoder.writeFloat64(y)
        encoder.writeFloat64(z)
    }

    public init(from decoder: CDRDecoder) throws {
        self.x = try decoder.readFloat64()
        self.y = try decoder.readFloat64()
        self.z = try decoder.readFloat64()
    }
}

// MARK: - geometry_msgs/Quaternion

public struct Quaternion: CDRCodable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public init(x: Double = 0.0, y: Double = 0.0, z: Double = 0.0, w: Double = 1.0) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeFloat64(x)
        encoder.writeFloat64(y)
        encoder.writeFloat64(z)
        encoder.writeFloat64(w)
    }

    public init(from decoder: CDRDecoder) throws {
        self.x = try decoder.readFloat64()
        self.y = try decoder.readFloat64()
        self.z = try decoder.readFloat64()
        self.w = try decoder.readFloat64()
    }
}

// MARK: - geometry_msgs/Point

public struct Point: CDRCodable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double = 0.0, y: Double = 0.0, z: Double = 0.0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeFloat64(x)
        encoder.writeFloat64(y)
        encoder.writeFloat64(z)
    }

    public init(from decoder: CDRDecoder) throws {
        self.x = try decoder.readFloat64()
        self.y = try decoder.readFloat64()
        self.z = try decoder.readFloat64()
    }
}

// MARK: - geometry_msgs/Pose

public struct Pose: CDRCodable, Sendable, Equatable {
    public var position: Point
    public var orientation: Quaternion

    public init(position: Point = Point(), orientation: Quaternion = Quaternion()) {
        self.position = position
        self.orientation = orientation
    }

    public func encode(to encoder: CDREncoder) throws {
        try position.encode(to: encoder)
        try orientation.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.position = try Point(from: decoder)
        self.orientation = try Quaternion(from: decoder)
    }
}

// MARK: - geometry_msgs/Twist

public struct Twist: CDRCodable, Sendable, Equatable {
    public var linear: Vector3
    public var angular: Vector3

    public init(linear: Vector3 = Vector3(), angular: Vector3 = Vector3()) {
        self.linear = linear
        self.angular = angular
    }

    public func encode(to encoder: CDREncoder) throws {
        try linear.encode(to: encoder)
        try angular.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.linear = try Vector3(from: decoder)
        self.angular = try Vector3(from: decoder)
    }
}

// MARK: - geometry_msgs/Transform

public struct Transform: CDRCodable, Sendable, Equatable {
    public var translation: Vector3
    public var rotation: Quaternion

    public init(translation: Vector3 = Vector3(), rotation: Quaternion = Quaternion()) {
        self.translation = translation
        self.rotation = rotation
    }

    public func encode(to encoder: CDREncoder) throws {
        try translation.encode(to: encoder)
        try rotation.encode(to: encoder)
    }

    public init(from decoder: CDRDecoder) throws {
        self.translation = try Vector3(from: decoder)
        self.rotation = try Quaternion(from: decoder)
    }
}

// MARK: - Covariance Constants

public enum CovarianceConstants {
    public static let unknown: Double = -1.0

    public static func unknownCovariance3x3() -> [Double] {
        Array(repeating: unknown, count: 9)
    }

    public static func zeroCovariance3x3() -> [Double] {
        Array(repeating: 0.0, count: 9)
    }
}
