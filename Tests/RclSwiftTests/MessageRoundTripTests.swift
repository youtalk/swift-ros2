// MessageRoundTripTests.swift
// Tests for message CDR encode/decode round-trips

import XCTest
import RclSwiftCDR
import RclSwiftMessages
@testable import RclSwift

final class MessageRoundTripTests: XCTestCase {

    // MARK: - Common Types

    func testHeaderRoundTrip() throws {
        let original = Header(sec: 1234567890, nanosec: 500000000, frameId: "imu_link")

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try Header(from: decoder)

        XCTAssertEqual(decoded.sec, original.sec)
        XCTAssertEqual(decoded.nanosec, original.nanosec)
        XCTAssertEqual(decoded.frameId, original.frameId)
    }

    func testVector3RoundTrip() throws {
        let original = Vector3(x: 1.5, y: -2.7, z: 9.81)

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try Vector3(from: decoder)

        XCTAssertEqual(decoded, original)
    }

    func testQuaternionRoundTrip() throws {
        let original = Quaternion(x: 0.0, y: 0.0, z: 0.707, w: 0.707)

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try Quaternion(from: decoder)

        XCTAssertEqual(decoded, original)
    }

    func testPoseRoundTrip() throws {
        let original = Pose(
            position: Point(x: 1.0, y: 2.0, z: 3.0),
            orientation: Quaternion(x: 0.0, y: 0.0, z: 0.0, w: 1.0)
        )

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try Pose(from: decoder)

        XCTAssertEqual(decoded, original)
    }

    func testTwistRoundTrip() throws {
        let original = Twist(
            linear: Vector3(x: 1.0, y: 0.0, z: 0.0),
            angular: Vector3(x: 0.0, y: 0.0, z: 0.5)
        )

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try Twist(from: decoder)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Sensor Messages

    func testImuRoundTrip() throws {
        let original = Imu(
            header: Header(sec: 100, nanosec: 0, frameId: "imu_link"),
            orientation: Quaternion(x: 0.1, y: 0.2, z: 0.3, w: 0.9),
            orientationCovariance: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            angularVelocity: Vector3(x: 0.01, y: 0.02, z: 0.03),
            angularVelocityCovariance: CovarianceConstants.unknownCovariance3x3(),
            linearAcceleration: Vector3(x: 0.0, y: 0.0, z: 9.81),
            linearAccelerationCovariance: CovarianceConstants.zeroCovariance3x3()
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)
        let data = encoder.getData()

        let decoder = try CDRDecoder(data: data)
        let decoded = try Imu(from: decoder)

        XCTAssertEqual(decoded.header.sec, original.header.sec)
        XCTAssertEqual(decoded.header.frameId, original.header.frameId)
        XCTAssertEqual(decoded.orientation, original.orientation)
        XCTAssertEqual(decoded.orientationCovariance, original.orientationCovariance)
        XCTAssertEqual(decoded.angularVelocity, original.angularVelocity)
        XCTAssertEqual(decoded.linearAcceleration, original.linearAcceleration)
    }

    func testFluidPressureRoundTrip() throws {
        let original = FluidPressure(
            header: Header(sec: 200, nanosec: 123456789, frameId: "barometer_link"),
            fluidPressure: 101325.0,
            variance: 10.0
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try FluidPressure(from: decoder)

        XCTAssertEqual(decoded.header.sec, original.header.sec)
        XCTAssertEqual(decoded.header.frameId, original.header.frameId)
        XCTAssertEqual(decoded.fluidPressure, original.fluidPressure)
        XCTAssertEqual(decoded.variance, original.variance)
    }

    func testCompressedImageRoundTrip() throws {
        let imageData = Data(repeating: 0xFF, count: 1024)
        let original = CompressedImage(
            header: Header(sec: 300, nanosec: 0, frameId: "camera_link"),
            format: "jpeg",
            data: imageData
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try CompressedImage(from: decoder)

        XCTAssertEqual(decoded.header.frameId, original.header.frameId)
        XCTAssertEqual(decoded.format, original.format)
        XCTAssertEqual(decoded.data, original.data)
    }

    func testIlluminanceRoundTrip() throws {
        let original = Illuminance(
            header: Header(sec: 400, nanosec: 0, frameId: "light_sensor"),
            illuminance: 500.0,
            variance: 0.0
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try Illuminance(from: decoder)

        XCTAssertEqual(decoded.illuminance, original.illuminance)
        XCTAssertEqual(decoded.variance, original.variance)
    }

    func testTemperatureRoundTrip() throws {
        let original = Temperature(
            header: Header(sec: 500, nanosec: 0, frameId: "thermal"),
            temperature: 36.6,
            variance: 0.1
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try Temperature(from: decoder)

        XCTAssertEqual(decoded.temperature, original.temperature, accuracy: 1e-10)
        XCTAssertEqual(decoded.variance, original.variance, accuracy: 1e-10)
    }

    // MARK: - Std Messages

    func testStringMsgRoundTrip() throws {
        let original = StringMsg(data: "Hello, ROS 2!")

        let encoder = CDREncoder()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try StringMsg(from: decoder)

        XCTAssertEqual(decoded.data, original.data)
    }

    func testBoolMsgRoundTrip() throws {
        let original = BoolMsg(data: true)

        let encoder = CDREncoder()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try BoolMsg(from: decoder)

        XCTAssertEqual(decoded.data, original.data)
    }

    func testEmptyMsgRoundTrip() throws {
        let encoder = CDREncoder()
        try EmptyMsg().encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        _ = try EmptyMsg(from: decoder)
        // Just verify it doesn't throw
    }

    // MARK: - Geometry Messages

    func testTransformStampedRoundTrip() throws {
        let original = TransformStamped(
            header: Header(sec: 600, nanosec: 0, frameId: "world"),
            childFrameId: "base_link",
            transform: Transform(
                translation: Vector3(x: 1.0, y: 2.0, z: 3.0),
                rotation: Quaternion(x: 0.0, y: 0.0, z: 0.707, w: 0.707)
            )
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try TransformStamped(from: decoder)

        XCTAssertEqual(decoded.header.frameId, "world")
        XCTAssertEqual(decoded.childFrameId, "base_link")
        XCTAssertEqual(decoded.transform.translation, original.transform.translation)
        XCTAssertEqual(decoded.transform.rotation, original.transform.rotation)
    }

    // MARK: - Type Info

    func testImuTypeInfo() {
        XCTAssertEqual(Imu.typeInfo.typeName, "sensor_msgs/msg/Imu")
        XCTAssertNotNil(Imu.typeInfo.typeHash)
        XCTAssertTrue(Imu.typeInfo.typeHash!.hasPrefix("RIHS01_"))
    }

    func testStringMsgTypeInfo() {
        XCTAssertEqual(StringMsg.typeInfo.typeName, "std_msgs/msg/String")
    }
}
