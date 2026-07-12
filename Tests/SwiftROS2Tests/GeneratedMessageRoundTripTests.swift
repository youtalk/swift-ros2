// GeneratedMessageRoundTripTests.swift
// CDR encode/decode round-trips for the generated message types that had no
// direct test coverage: example_interfaces AddTwoInts request/response, the
// remaining sensor_msgs types, std_msgs Float64/Int32 wrappers, the composed
// geometry_msgs types, and the builtin_interfaces source-compat aliases.

import SwiftROS2CDR
import SwiftROS2Messages
import XCTest

final class GeneratedMessageRoundTripTests: XCTestCase {

    // MARK: - Helper

    private func roundTrip<M: ROS2Message>(_ original: M) throws -> M {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        try original.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        return try M(from: decoder)
    }

    // MARK: - example_interfaces

    func testAddTwoIntsRequestRoundTrip() throws {
        let original = AddTwoIntsRequest(a: Int64.min, b: Int64.max)
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.a, Int64.min)
        XCTAssertEqual(decoded.b, Int64.max)
        XCTAssertEqual(decoded, original)
    }

    func testAddTwoIntsResponseRoundTrip() throws {
        let original = AddTwoIntsResponse(sum: -1)
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.sum, -1)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - std_msgs

    func testFloat64MsgRoundTrip() throws {
        let original = Float64Msg(data: -273.15)
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.data, -273.15)
        XCTAssertEqual(decoded, original)
    }

    func testInt32MsgRoundTrip() throws {
        let original = Int32Msg(data: Int32.min)
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.data, Int32.min)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - geometry_msgs

    func testAccelRoundTrip() throws {
        let original = Accel(
            linear: Vector3(x: 0.25, y: -9.81, z: 1e-9),
            angular: Vector3(x: -0.5, y: 0.75, z: -1.25)
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.linear, original.linear)
        XCTAssertEqual(decoded.angular, original.angular)
        XCTAssertEqual(decoded, original)
    }

    func testPoseStampedRoundTrip() throws {
        let original = PoseStamped(
            header: Header(sec: 1_700_000_001, nanosec: 999_999_999, frameId: "map"),
            pose: Pose(
                position: Point(x: -3.5, y: 2.25, z: 0.125),
                orientation: Quaternion(x: 0.0, y: 0.0, z: 0.707, w: 0.707)
            )
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.header.sec, original.header.sec)
        XCTAssertEqual(decoded.header.nanosec, original.header.nanosec)
        XCTAssertEqual(decoded.header.frameId, "map")
        XCTAssertEqual(decoded.pose.position, original.pose.position)
        XCTAssertEqual(decoded.pose.orientation, original.pose.orientation)
    }

    func testTwistStampedRoundTrip() throws {
        let original = TwistStamped(
            header: Header(sec: UInt32.max, nanosec: 1, frameId: "base_link"),
            twist: Twist(
                linear: Vector3(x: 1.5, y: -0.5, z: 0.0),
                angular: Vector3(x: 0.0, y: 0.0, z: -3.14159)
            )
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.header.sec, UInt32.max)
        XCTAssertEqual(decoded.header.frameId, "base_link")
        XCTAssertEqual(decoded.twist.linear, original.twist.linear)
        XCTAssertEqual(decoded.twist.angular, original.twist.angular)
    }

    func testVector3StampedRoundTrip() throws {
        let original = Vector3Stamped(
            header: Header(sec: 42, nanosec: 7, frameId: "gravity"),
            vector: Vector3(x: 0.0, y: 0.0, z: -9.80665)
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.header.frameId, "gravity")
        XCTAssertEqual(decoded.vector, original.vector)
    }

    func testWrenchRoundTrip() throws {
        let original = Wrench(
            force: Vector3(x: 12.5, y: -8.25, z: 100.0),
            torque: Vector3(x: -0.001, y: 0.002, z: -0.003)
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.force, original.force)
        XCTAssertEqual(decoded.torque, original.torque)
        XCTAssertEqual(decoded, original)
    }

    func testPoint32RoundTrip() throws {
        let original = Point32(x: -1.5, y: Float.greatestFiniteMagnitude, z: -Float.leastNormalMagnitude)
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.x, -1.5)
        XCTAssertEqual(decoded.y, Float.greatestFiniteMagnitude)
        XCTAssertEqual(decoded.z, -Float.leastNormalMagnitude)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - sensor_msgs (services)

    func testSetCameraInfoRequestRoundTrip() throws {
        let original = SetCameraInfoRequest(
            cameraInfo: CameraInfo(
                header: Header(sec: 900, nanosec: 250, frameId: "camera_optical_frame"),
                height: 1080,
                width: 1920,
                distortionModel: "rational_polynomial",
                d: [0.05, -0.1, 0.0025, -0.0005],
                k: [700.0, 0.0, 960.0, 0.0, 700.0, 540.0, 0.0, 0.0, 1.0],
                r: [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
                p: [700.0, 0.0, 960.0, 0.0, 0.0, 700.0, 540.0, 0.0, 0.0, 0.0, 1.0, 0.0],
                binningX: 2,
                binningY: 2,
                roi: RegionOfInterest(xOffset: 8, yOffset: 16, height: 1024, width: 1888, doRectify: true)
            )
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.cameraInfo.header.frameId, "camera_optical_frame")
        XCTAssertEqual(decoded.cameraInfo.height, 1080)
        XCTAssertEqual(decoded.cameraInfo.width, 1920)
        XCTAssertEqual(decoded.cameraInfo.distortionModel, "rational_polynomial")
        XCTAssertEqual(decoded.cameraInfo.d, original.cameraInfo.d)
        XCTAssertEqual(decoded.cameraInfo.k, original.cameraInfo.k)
        XCTAssertEqual(decoded.cameraInfo.r, original.cameraInfo.r)
        XCTAssertEqual(decoded.cameraInfo.p, original.cameraInfo.p)
        XCTAssertEqual(decoded.cameraInfo.binningX, 2)
        XCTAssertEqual(decoded.cameraInfo.binningY, 2)
        XCTAssertEqual(decoded.cameraInfo.roi, original.cameraInfo.roi)
    }

    func testSetCameraInfoResponseRoundTrip() throws {
        let original = SetCameraInfoResponse(success: true, statusMessage: "calibration stored")
        let decoded = try roundTrip(original)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.statusMessage, "calibration stored")
        XCTAssertEqual(decoded, original)
    }

    // MARK: - sensor_msgs (messages)

    func testJoyFeedbackRoundTrip() throws {
        let original = JoyFeedback(type: JoyFeedback.TYPE_RUMBLE, id: 3, intensity: 0.75)
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.type, 1)
        XCTAssertEqual(decoded.id, 3)
        XCTAssertEqual(decoded.intensity, 0.75)
        XCTAssertEqual(decoded, original)
    }

    func testJoyFeedbackTypeConstants() {
        XCTAssertEqual(JoyFeedback.TYPE_LED, 0)
        XCTAssertEqual(JoyFeedback.TYPE_RUMBLE, 1)
        XCTAssertEqual(JoyFeedback.TYPE_BUZZER, 2)
    }

    func testJoyFeedbackArrayRoundTrip() throws {
        let original = JoyFeedbackArray(array: [
            JoyFeedback(type: JoyFeedback.TYPE_LED, id: 0, intensity: 1.0),
            JoyFeedback(type: JoyFeedback.TYPE_BUZZER, id: 255, intensity: -0.5),
        ])
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.array.count, 2)
        XCTAssertEqual(decoded.array[0], original.array[0])
        XCTAssertEqual(decoded.array[1], original.array[1])
        XCTAssertEqual(decoded.array[1].id, 255)
    }

    func testRelativeHumidityRoundTrip() throws {
        let original = RelativeHumidity(
            header: Header(sec: 1_650_000_000, nanosec: 500, frameId: "hygrometer"),
            relativeHumidity: 0.55,
            variance: 0.0001
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.header.frameId, "hygrometer")
        XCTAssertEqual(decoded.relativeHumidity, 0.55)
        XCTAssertEqual(decoded.variance, 0.0001)
    }

    func testTimeReferenceRoundTrip() throws {
        let original = TimeReference(
            header: Header(sec: 100, nanosec: 200, frameId: "gps_time"),
            timeRef: Time(sec: Int32.max, nanosec: 999_999_999),
            source: "gps"
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.header.frameId, "gps_time")
        XCTAssertEqual(decoded.timeRef.sec, Int32.max)
        XCTAssertEqual(decoded.timeRef.nanosec, 999_999_999)
        XCTAssertEqual(decoded.source, "gps")
    }

    func testLaserEchoRoundTrip() throws {
        let original = LaserEcho(echoes: [0.5, -1.25, 3.75, Float.infinity])
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.echoes, original.echoes)
        XCTAssertEqual(decoded.echoes.count, 4)
        XCTAssertEqual(decoded.echoes[3], Float.infinity)
    }

    func testChannelFloat32RoundTrip() throws {
        let original = ChannelFloat32(name: "intensity", values: [-0.25, 0.0, 127.5])
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.name, "intensity")
        XCTAssertEqual(decoded.values, original.values)
    }

    func testPointCloudRoundTrip() throws {
        let original = PointCloud(
            header: Header(sec: 300, nanosec: 400, frameId: "lidar"),
            points: [
                Point32(x: 1.0, y: -2.0, z: 3.0),
                Point32(x: -4.5, y: 5.5, z: -6.5),
            ],
            channels: [
                ChannelFloat32(name: "intensity", values: [10.0, 20.0]),
                ChannelFloat32(name: "ring", values: [0.0, 1.0]),
            ]
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.header.frameId, "lidar")
        XCTAssertEqual(decoded.points.count, 2)
        XCTAssertEqual(decoded.points[0], original.points[0])
        XCTAssertEqual(decoded.points[1], original.points[1])
        XCTAssertEqual(decoded.channels.count, 2)
        XCTAssertEqual(decoded.channels[0].name, "intensity")
        XCTAssertEqual(decoded.channels[1].values, [0.0, 1.0])
    }

    func testLaserScanRoundTrip() throws {
        let original = LaserScan(
            header: Header(sec: 500, nanosec: 600, frameId: "laser"),
            angleMin: -3.14159,
            angleMax: 3.14159,
            angleIncrement: 0.0174533,
            timeIncrement: 0.0001,
            scanTime: 0.1,
            rangeMin: 0.02,
            rangeMax: 30.0,
            ranges: [0.5, 12.25, Float.infinity, 29.99],
            intensities: [100.0, 0.0, -1.0, 255.0]
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.header.frameId, "laser")
        XCTAssertEqual(decoded.angleMin, -3.14159)
        XCTAssertEqual(decoded.angleMax, 3.14159)
        XCTAssertEqual(decoded.angleIncrement, 0.0174533)
        XCTAssertEqual(decoded.timeIncrement, 0.0001)
        XCTAssertEqual(decoded.scanTime, 0.1)
        XCTAssertEqual(decoded.rangeMin, 0.02)
        XCTAssertEqual(decoded.rangeMax, 30.0)
        XCTAssertEqual(decoded.ranges, original.ranges)
        XCTAssertEqual(decoded.intensities, original.intensities)
    }

    func testMultiEchoLaserScanRoundTrip() throws {
        let original = MultiEchoLaserScan(
            header: Header(sec: 700, nanosec: 800, frameId: "multi_laser"),
            angleMin: -1.5708,
            angleMax: 1.5708,
            angleIncrement: 0.01,
            timeIncrement: 0.00005,
            scanTime: 0.05,
            rangeMin: 0.1,
            rangeMax: 50.0,
            ranges: [
                LaserEcho(echoes: [1.0, 1.5]),
                LaserEcho(echoes: [2.0]),
            ],
            intensities: [
                LaserEcho(echoes: [80.0, 40.0]),
                LaserEcho(echoes: [60.0]),
            ]
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.header.frameId, "multi_laser")
        XCTAssertEqual(decoded.angleMin, -1.5708)
        XCTAssertEqual(decoded.ranges.count, 2)
        XCTAssertEqual(decoded.ranges[0].echoes, [1.0, 1.5])
        XCTAssertEqual(decoded.ranges[1].echoes, [2.0])
        XCTAssertEqual(decoded.intensities.count, 2)
        XCTAssertEqual(decoded.intensities[0].echoes, [80.0, 40.0])
    }

    func testJointStateRoundTrip() throws {
        let original = JointState(
            header: Header(sec: 900, nanosec: 100, frameId: ""),
            name: ["shoulder_pan", "shoulder_lift", "elbow"],
            position: [0.5, -1.25, 2.0],
            velocity: [-0.1, 0.0, 0.1],
            effort: [10.0, -20.0, 30.0]
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.name, ["shoulder_pan", "shoulder_lift", "elbow"])
        XCTAssertEqual(decoded.position, [0.5, -1.25, 2.0])
        XCTAssertEqual(decoded.velocity, [-0.1, 0.0, 0.1])
        XCTAssertEqual(decoded.effort, [10.0, -20.0, 30.0])
    }

    func testMultiDOFJointStateRoundTrip() throws {
        let original = MultiDOFJointState(
            header: Header(sec: 1_000, nanosec: 2_000, frameId: "world"),
            jointNames: ["free_body"],
            transforms: [
                Transform(
                    translation: Vector3(x: 0.5, y: -0.5, z: 1.5),
                    rotation: Quaternion(x: 0.0, y: 0.0, z: 0.0, w: 1.0)
                )
            ],
            twist: [
                Twist(
                    linear: Vector3(x: 0.1, y: 0.2, z: 0.3),
                    angular: Vector3(x: -0.1, y: -0.2, z: -0.3)
                )
            ],
            wrench: [
                Wrench(
                    force: Vector3(x: 1.0, y: 2.0, z: 3.0),
                    torque: Vector3(x: -1.0, y: -2.0, z: -3.0)
                )
            ]
        )
        let decoded = try roundTrip(original)

        XCTAssertEqual(decoded.header.frameId, "world")
        XCTAssertEqual(decoded.jointNames, ["free_body"])
        XCTAssertEqual(decoded.transforms, original.transforms)
        XCTAssertEqual(decoded.twist, original.twist)
        XCTAssertEqual(decoded.wrench, original.wrench)
    }

    // MARK: - builtin_interfaces aliases

    func testBuiltinInterfacesTimeAliasIdentity() {
        XCTAssertTrue(BuiltinInterfacesTime.self == Time.self)
        XCTAssertEqual(BuiltinInterfacesTime.typeInfo.typeName, "builtin_interfaces/msg/Time")
    }

    func testTimeNowProducesPlausibleWallClock() {
        let t = Time.now()
        // 2026-01-01T00:00:00Z as a sanity lower bound; Time.now() reads the wall clock.
        XCTAssertGreaterThan(t.sec, 1_767_225_600)
        XCTAssertLessThan(t.nanosec, 1_000_000_000)
    }

    // MARK: - Type metadata

    func testGeneratedTypeInfoMetadata() {
        XCTAssertEqual(AddTwoIntsRequest.typeInfo.typeName, "example_interfaces/srv/AddTwoInts_Request")
        XCTAssertEqual(AddTwoIntsResponse.typeInfo.typeName, "example_interfaces/srv/AddTwoInts_Response")
        XCTAssertEqual(Float64Msg.typeInfo.typeName, "std_msgs/msg/Float64")
        XCTAssertEqual(Int32Msg.typeInfo.typeName, "std_msgs/msg/Int32")
        XCTAssertEqual(Accel.typeInfo.typeName, "geometry_msgs/msg/Accel")
        XCTAssertEqual(PoseStamped.typeInfo.typeName, "geometry_msgs/msg/PoseStamped")
        XCTAssertEqual(TwistStamped.typeInfo.typeName, "geometry_msgs/msg/TwistStamped")
        XCTAssertEqual(Vector3Stamped.typeInfo.typeName, "geometry_msgs/msg/Vector3Stamped")
        XCTAssertEqual(Wrench.typeInfo.typeName, "geometry_msgs/msg/Wrench")
        XCTAssertEqual(Point32.typeInfo.typeName, "geometry_msgs/msg/Point32")
        XCTAssertEqual(SetCameraInfoRequest.typeInfo.typeName, "sensor_msgs/srv/SetCameraInfo_Request")
        XCTAssertEqual(SetCameraInfoResponse.typeInfo.typeName, "sensor_msgs/srv/SetCameraInfo_Response")
        XCTAssertEqual(JoyFeedback.typeInfo.typeName, "sensor_msgs/msg/JoyFeedback")
        XCTAssertEqual(JoyFeedbackArray.typeInfo.typeName, "sensor_msgs/msg/JoyFeedbackArray")
        XCTAssertEqual(RelativeHumidity.typeInfo.typeName, "sensor_msgs/msg/RelativeHumidity")
        XCTAssertEqual(TimeReference.typeInfo.typeName, "sensor_msgs/msg/TimeReference")
        XCTAssertEqual(LaserEcho.typeInfo.typeName, "sensor_msgs/msg/LaserEcho")
        XCTAssertEqual(ChannelFloat32.typeInfo.typeName, "sensor_msgs/msg/ChannelFloat32")
        XCTAssertEqual(PointCloud.typeInfo.typeName, "sensor_msgs/msg/PointCloud")
        XCTAssertEqual(LaserScan.typeInfo.typeName, "sensor_msgs/msg/LaserScan")
        XCTAssertEqual(MultiEchoLaserScan.typeInfo.typeName, "sensor_msgs/msg/MultiEchoLaserScan")
        XCTAssertEqual(JointState.typeInfo.typeName, "sensor_msgs/msg/JointState")
        XCTAssertEqual(MultiDOFJointState.typeInfo.typeName, "sensor_msgs/msg/MultiDOFJointState")

        for typeInfo in [
            AddTwoIntsRequest.typeInfo, AddTwoIntsResponse.typeInfo,
            Float64Msg.typeInfo, Int32Msg.typeInfo,
            Accel.typeInfo, PoseStamped.typeInfo, TwistStamped.typeInfo,
            Vector3Stamped.typeInfo, Wrench.typeInfo, Point32.typeInfo,
            SetCameraInfoRequest.typeInfo, SetCameraInfoResponse.typeInfo,
            JoyFeedback.typeInfo, JoyFeedbackArray.typeInfo,
            RelativeHumidity.typeInfo, TimeReference.typeInfo,
            LaserEcho.typeInfo, ChannelFloat32.typeInfo, PointCloud.typeInfo,
            LaserScan.typeInfo, MultiEchoLaserScan.typeInfo,
            JointState.typeInfo, MultiDOFJointState.typeInfo,
        ] {
            XCTAssertNotNil(typeInfo.typeHash, "\(typeInfo.typeName) should carry a type hash")
            XCTAssertTrue(
                typeInfo.typeHash!.hasPrefix("RIHS01_"),
                "\(typeInfo.typeName) hash should be RIHS01-prefixed")
        }
    }
}
