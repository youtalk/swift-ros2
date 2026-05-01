// WireCodecTests.swift
// Tests for wire format codecs

import XCTest

@testable import SwiftROS2Wire

final class WireCodecTests: XCTestCase {

    // MARK: - Type Name Conversion

    func testDDSTypeNameConversion() {
        XCTAssertEqual(
            TypeNameConverter.toDDSTypeName("sensor_msgs/msg/Imu"),
            "sensor_msgs::msg::dds_::Imu_"
        )
        XCTAssertEqual(
            TypeNameConverter.toDDSTypeName("geometry_msgs/msg/Twist"),
            "geometry_msgs::msg::dds_::Twist_"
        )
        XCTAssertEqual(
            TypeNameConverter.toDDSTypeName("std_msgs/msg/String"),
            "std_msgs::msg::dds_::String_"
        )
    }

    func testTopicPathMangling() {
        XCTAssertEqual(
            TypeNameConverter.mangleTopicPath(namespace: "/ios", topic: "imu"),
            "%ios%imu"
        )
        XCTAssertEqual(
            TypeNameConverter.mangleTopicPath(namespace: "ios", topic: "imu"),
            "%ios%imu"
        )
        XCTAssertEqual(
            TypeNameConverter.mangleTopicPath(namespace: "", topic: "tf_static"),
            "%tf_static"
        )
    }

    func testStripLeadingSlash() {
        XCTAssertEqual(TypeNameConverter.stripLeadingSlash("/ios"), "ios")
        XCTAssertEqual(TypeNameConverter.stripLeadingSlash("ios"), "ios")
        XCTAssertEqual(TypeNameConverter.stripLeadingSlash(""), "")
    }

    // MARK: - Zenoh Wire Codec

    func testJazzyKeyExpression() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeKeyExpr(
            domainId: 0,
            namespace: "ios",
            topic: "imu",
            typeName: "sensor_msgs/msg/Imu",
            typeHash: "RIHS01_abc123"
        )
        XCTAssertEqual(key, "0/ios/imu/sensor_msgs::msg::dds_::Imu_/RIHS01_abc123")
    }

    func testHumbleKeyExpression() {
        let codec = ZenohWireCodec(distro: .humble)
        let key = codec.makeKeyExpr(
            domainId: 0,
            namespace: "ios",
            topic: "imu",
            typeName: "sensor_msgs/msg/Imu",
            typeHash: nil
        )
        XCTAssertEqual(key, "0/ios/imu/sensor_msgs::msg::dds_::Imu_/TypeHashNotSupported")
    }

    func testJazzyKeyExpressionEmptyNamespace() {
        // Global topics like /tf_static are published with an empty namespace.
        // The key must NOT contain a double slash between the domain id and topic.
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeKeyExpr(
            domainId: 0,
            namespace: "",
            topic: "tf_static",
            typeName: "tf2_msgs/msg/TFMessage",
            typeHash: "RIHS01_abc123"
        )
        XCTAssertEqual(key, "0/tf_static/tf2_msgs::msg::dds_::TFMessage_/RIHS01_abc123")
    }

    func testJazzyKeyExpressionWithoutTypeHash() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeKeyExpr(
            domainId: 0,
            namespace: "ios",
            topic: "imu",
            typeName: "sensor_msgs/msg/Imu",
            typeHash: nil
        )
        // Jazzy omits trailing segment when hash is empty
        XCTAssertEqual(key, "0/ios/imu/sensor_msgs::msg::dds_::Imu_")
    }

    func testLivelinessToken() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let qos = QoSPolicy(reliability: .bestEffort, durability: .volatile, historyPolicy: .keepLast, historyDepth: 10)
        let token = codec.makeLivelinessToken(
            domainId: 0,
            sessionId: "abc123",
            nodeId: "1",
            entityId: "2",
            namespace: "/ios",
            nodeName: "imu_node",
            topic: "imu",
            typeName: "sensor_msgs/msg/Imu",
            typeHash: "RIHS01_hash",
            qos: qos
        )
        XCTAssertTrue(token.hasPrefix("@ros2_lv/0/abc123/1/2/MP/%/%/imu_node/"))
        XCTAssertTrue(token.contains("%ios%imu"))
        XCTAssertTrue(token.contains("sensor_msgs::msg::dds_::Imu_"))
    }

    // MARK: - Attachment

    func testAttachmentSize() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let gid = [UInt8](repeating: 0x42, count: 16)
        let attachment = codec.buildAttachment(seq: 0, tsNsec: 1234567890, gid: gid)
        XCTAssertEqual(attachment.count, 33, "Attachment must be exactly 33 bytes")
    }

    func testAttachmentFormat() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let gid: [UInt8] = Array(0..<16)
        let attachment = codec.buildAttachment(seq: 42, tsNsec: 1_000_000_000, gid: gid)

        // Verify seq (bytes 0-7)
        let seq = attachment.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Int64.self) }
        XCTAssertEqual(Int64(littleEndian: seq), 42)

        // Verify timestamp (bytes 8-15)
        let ts = attachment.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: Int64.self) }
        XCTAssertEqual(Int64(littleEndian: ts), 1_000_000_000)

        // Verify LEB128 GID length (byte 16)
        XCTAssertEqual(attachment[16], 0x10)

        // Verify GID (bytes 17-32)
        for i in 0..<16 {
            XCTAssertEqual(attachment[17 + i], UInt8(i))
        }
    }

    func testAttachmentBoundaryValues() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let gid = [UInt8](repeating: 0xFF, count: 16)
        let attachment = codec.buildAttachment(seq: Int64.min, tsNsec: Int64.max, gid: gid)

        XCTAssertEqual(attachment.count, 33)

        let seq = attachment.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Int64.self) }
        XCTAssertEqual(Int64(littleEndian: seq), Int64.min)

        let ts = attachment.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: Int64.self) }
        XCTAssertEqual(Int64(littleEndian: ts), Int64.max)

        XCTAssertEqual(attachment[16], 0x10)
        for i in 0..<16 {
            XCTAssertEqual(attachment[17 + i], 0xFF)
        }
    }

    // MARK: - DDS Wire Codec

    func testDDSTopic() {
        let codec = DDSWireCodec()
        XCTAssertEqual(codec.ddsTopic(from: "/conduit/imu"), "rt/conduit/imu")
        XCTAssertEqual(codec.ddsTopic(from: "conduit/imu"), "rt/conduit/imu")
    }

    func testDDSUserData() {
        let codec = DDSWireCodec()
        XCTAssertEqual(codec.userDataString(typeHash: "RIHS01_abc"), "typehash=RIHS01_abc;")
        XCTAssertNil(codec.userDataString(typeHash: nil))
        XCTAssertNil(codec.userDataString(typeHash: ""))
    }

    // MARK: - ROS2Distro

    func testDistroTypeHashSupport() {
        XCTAssertFalse(ROS2Distro.humble.supportsTypeHash)
        XCTAssertTrue(ROS2Distro.jazzy.supportsTypeHash)
        XCTAssertTrue(ROS2Distro.kilted.supportsTypeHash)
        XCTAssertTrue(ROS2Distro.rolling.supportsTypeHash)
    }

    func testDistroFormatTypeHash() {
        XCTAssertEqual(ROS2Distro.humble.formatTypeHash(nil), "TypeHashNotSupported")
        XCTAssertEqual(ROS2Distro.humble.formatTypeHash("RIHS01_abc"), "TypeHashNotSupported")
        XCTAssertEqual(ROS2Distro.jazzy.formatTypeHash("RIHS01_abc"), "RIHS01_abc")
        XCTAssertEqual(ROS2Distro.jazzy.formatTypeHash(nil), "")
    }
}
