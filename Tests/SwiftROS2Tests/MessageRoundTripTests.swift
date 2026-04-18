// MessageRoundTripTests.swift
// Tests for message CDR encode/decode round-trips

import SwiftROS2
import SwiftROS2CDR
import SwiftROS2Messages
import XCTest

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

    // MARK: - New Message Types

    func testImageRoundTrip() throws {
        let pixelData = Data(repeating: 0xAB, count: 640 * 480 * 3)
        let original = Image(
            header: Header(sec: 700, nanosec: 0, frameId: "camera_link"),
            height: 480, width: 640, encoding: "rgb8",
            isBigendian: 0, step: 640 * 3, data: pixelData
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try Image(from: decoder)

        XCTAssertEqual(decoded.height, 480)
        XCTAssertEqual(decoded.width, 640)
        XCTAssertEqual(decoded.encoding, "rgb8")
        XCTAssertEqual(decoded.data.count, pixelData.count)
    }

    func testPointCloud2RoundTrip() throws {
        var pointData = Data()
        for i: Float in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0] {
            var bits = i.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { pointData.append(contentsOf: $0) }
        }

        let original = PointCloud2(
            header: Header(sec: 800, nanosec: 0, frameId: "lidar_link"),
            height: 1, width: 2,
            fields: PointField.xyzFields,
            isBigendian: false, pointStep: 12, rowStep: 24,
            data: pointData, isDense: true
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try PointCloud2(from: decoder)

        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.fields.count, 3)
        XCTAssertEqual(decoded.fields[0].name, "x")
        XCTAssertEqual(decoded.pointStep, 12)
        XCTAssertEqual(decoded.data, pointData)
        XCTAssertTrue(decoded.isDense)
    }

    func testBatteryStateRoundTrip() throws {
        let original = BatteryState(
            header: Header(sec: 900, nanosec: 0, frameId: "battery"),
            voltage: 3.7, percentage: 0.85,
            powerSupplyStatus: .discharging,
            powerSupplyTechnology: .lion,
            location: "main", serialNumber: "ABC123"
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try BatteryState(from: decoder)

        XCTAssertEqual(decoded.voltage, 3.7, accuracy: 0.001)
        XCTAssertEqual(decoded.percentage, 0.85, accuracy: 0.001)
        XCTAssertEqual(decoded.powerSupplyStatus, 2)  // discharging
        XCTAssertEqual(decoded.location, "main")
        XCTAssertEqual(decoded.serialNumber, "ABC123")
    }

    func testJoyRoundTrip() throws {
        let original = Joy(
            header: Header(sec: 1000, nanosec: 0, frameId: "joy"),
            axes: [0.5, -0.3, 1.0, -1.0],
            buttons: [0, 1, 0, 1, 1]
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try Joy(from: decoder)

        XCTAssertEqual(decoded.axes.count, 4)
        XCTAssertEqual(decoded.axes[0], 0.5, accuracy: 0.001)
        XCTAssertEqual(decoded.buttons, [0, 1, 0, 1, 1])
    }

    func testRangeRoundTrip() throws {
        let original = Range(
            header: Header(sec: 1100, nanosec: 0, frameId: "proximity"),
            radiationType: .infrared,
            fieldOfView: 0.5, minRange: 0.0, maxRange: 5.0, range: 1.23, variance: 0.04
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try Range(from: decoder)

        XCTAssertEqual(decoded.radiationType, 1)  // infrared
        XCTAssertEqual(decoded.range, 1.23, accuracy: 0.001)
        XCTAssertEqual(decoded.variance, 0.04, accuracy: 0.0001)
    }

    /// Humble/legacy wire format must omit the post-Humble `variance` trailing field.
    func testRangeLegacySchemaOmitsVariance() throws {
        let original = Range(
            header: Header(sec: 1100, nanosec: 0, frameId: "proximity"),
            radiationType: .infrared,
            fieldOfView: 0.5, minRange: 0.0, maxRange: 5.0, range: 1.23, variance: 42.0
        )

        let legacyEncoder = CDREncoder(isLegacySchema: true)
        try original.encode(to: legacyEncoder)
        let legacyBytes = legacyEncoder.getData()

        let modernEncoder = CDREncoder()
        try original.encode(to: modernEncoder)
        let modernBytes = modernEncoder.getData()

        // Legacy payload is exactly 4 bytes shorter (the omitted float32 variance).
        XCTAssertEqual(modernBytes.count - legacyBytes.count, 4)

        // Legacy decoder accepts the legacy payload and reports variance == 0.
        let legacyDecoder = try CDRDecoder(data: legacyBytes, isLegacySchema: true)
        let decoded = try Range(from: legacyDecoder)
        XCTAssertEqual(decoded.range, 1.23, accuracy: 0.001)
        XCTAssertEqual(decoded.variance, 0.0)

        // Modern decoder refuses the legacy payload (not enough bytes for variance).
        let modernDecoder = try CDRDecoder(data: legacyBytes)
        XCTAssertThrowsError(try Range(from: modernDecoder))
    }

    func testAudioDataRoundTrip() throws {
        let audioBytes = Data(repeating: 0x42, count: 4096)
        let original = AudioData(data: audioBytes)

        let encoder = CDREncoder()
        try original.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try AudioData(from: decoder)

        XCTAssertEqual(decoded.data, audioBytes)
    }

    func testMagneticFieldRoundTrip() throws {
        let original = MagneticField(
            header: Header(sec: 1200, nanosec: 0, frameId: "magnetometer_link"),
            magneticField: Vector3(x: 0.00003, y: -0.00001, z: 0.00005),
            magneticFieldCovariance: [1, 0, 0, 0, 1, 0, 0, 0, 1]
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try MagneticField(from: decoder)

        XCTAssertEqual(decoded.magneticField, original.magneticField)
        XCTAssertEqual(decoded.magneticFieldCovariance, original.magneticFieldCovariance)
    }

    func testNavSatFixRoundTrip() throws {
        let original = NavSatFix(
            header: Header(sec: 1700000000, nanosec: 123456789, frameId: "gps_link"),
            status: NavSatStatus(status: NavSatStatus.statusFix, service: NavSatStatus.serviceGPS),
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 30.5,
            positionCovariance: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            positionCovarianceType: .diagonalKnown
        )

        let encoder = CDREncoder()
        try original.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try NavSatFix(from: decoder)

        XCTAssertEqual(decoded.header.frameId, "gps_link")
        XCTAssertEqual(decoded.status.status, NavSatStatus.statusFix)
        XCTAssertEqual(decoded.status.service, NavSatStatus.serviceGPS)
        XCTAssertEqual(decoded.latitude, 37.7749, accuracy: 1e-9)
        XCTAssertEqual(decoded.longitude, -122.4194, accuracy: 1e-9)
        XCTAssertEqual(decoded.altitude, 30.5, accuracy: 1e-9)
        XCTAssertEqual(decoded.positionCovariance, original.positionCovariance)
        XCTAssertEqual(decoded.positionCovarianceType, NavSatFix.CovarianceType.diagonalKnown.rawValue)
    }

    /// Locks the byte-level CDR layout of sensor_msgs/NavSatFix to the IDL offsets so
    /// stray manual padding cannot drift the fields again. Round-trip tests alone miss
    /// this class of bug because a buggy encoder pairs with a symmetrically-buggy
    /// decoder — a receiver that auto-aligns per CDR spec would read garbage in the
    /// latitude slot (see GPS lat/alt swap report in downstream projects).
    ///
    /// With frame_id = "gps_link" (8 chars + null), the relative dataPosition after
    /// encoding the Header is 21. NavSatStatus then writes int8 (→22) and auto-aligned
    /// uint16 (→24), which leaves the first float64 (latitude) 8-aligned at
    /// dataPosition 24. Absolute offsets include the 4-byte encapsulation header.
    func testNavSatFixCDRLayoutMatchesROS2IDL() throws {
        let latitude = 37.7749
        let longitude = -122.4194
        let altitude = 30.5

        let message = NavSatFix(
            header: Header(sec: 0, nanosec: 0, frameId: "gps_link"),
            status: NavSatStatus(status: NavSatStatus.statusFix, service: NavSatStatus.serviceGPS),
            latitude: latitude,
            longitude: longitude,
            altitude: altitude
        )

        let encoder = CDREncoder()
        try message.encode(to: encoder)
        let bytes = encoder.getData()

        func readF64(_ offset: Int) -> Double {
            let raw = bytes.subdata(in: offset..<(offset + 8))
            let bits = raw.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
            return Double(bitPattern: UInt64(littleEndian: bits))
        }

        // encap(4) + Header → dataPos 21, int8 status → 22, uint16 service (auto-aligned) → 24.
        // latitude / longitude / altitude land at absolute 28 / 36 / 44.
        XCTAssertEqual(readF64(28), latitude, accuracy: 1e-12, "latitude must be at IDL offset 28")
        XCTAssertEqual(readF64(36), longitude, accuracy: 1e-12, "longitude must be at IDL offset 36")
        XCTAssertEqual(readF64(44), altitude, accuracy: 1e-12, "altitude must be at IDL offset 44")
    }
}
