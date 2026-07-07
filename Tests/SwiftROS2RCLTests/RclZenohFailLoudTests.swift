// RclZenohFailLoudTests.swift
// Zenoh-rmw-variant fail-loud behavior: the route-(b) registry-miss gate (S1),
// the AMENT_PREFIX_PATH self-sufficiency synthesis (S2), and the `.rcl` /
// `.rclUnicast` config rejection (S6). All compiled only in the zenoh variant
// (SWIFT_ROS2_RCL_RMW=zenoh); the cyclonedds variant keeps its route-(b)
// fallback and `.rcl` support unchanged.

#if SWIFT_ROS2_RCL && SWIFT_ROS2_RCL_RMW_ZENOH
    import Foundation
    import SwiftROS2
    import SwiftROS2RCL
    import SwiftROS2Transport
    import XCTest

    // MARK: - FakeNodeHandle

    /// Stand-in node handle: the registry-miss gate fires before the node
    /// handle is even inspected, so these tests need no rcl context or node.
    private final class FakeNodeHandle: RclNodeHandle {}

    // MARK: - RclZenohRegistryMissGateTests (S1)

    /// On a marshal-registry miss the cyclonedds variant falls back to a
    /// raw-CDR writer/reader on a sibling CycloneDDS participant. Under
    /// rmw_zenoh that participant's DDS domain has no counterpart (live-proven
    /// silent data loss: a std_msgs/String talker published into the void), so
    /// the zenoh variant must throw instead. The cyclonedds fallback stays
    /// covered by the crcl-nonbundled-* loopbacks in ci-rcl.yml.
    final class RclZenohRegistryMissGateTests: XCTestCase {
        private let absentType = "foo_msgs/msg/Bar"

        private func assertRegistryMissError(_ error: Error) {
            guard case TransportError.unsupportedFeature(let message) = error else {
                return XCTFail("expected unsupportedFeature, got \(error)")
            }
            XCTAssertTrue(message.contains(absentType), "type name missing from: \(message)")
            XCTAssertTrue(message.contains(".dds"), "remedy missing from: \(message)")
        }

        func testCreatePublisherThrowsOnRegistryMiss() {
            XCTAssertThrowsError(
                try RclClient().createPublisher(
                    node: FakeNodeHandle(), typeName: absentType, typeHash: nil,
                    topic: "/gate_pub", qos: .sensorData)
            ) { assertRegistryMissError($0) }
        }

        func testCreateSubscriptionThrowsOnRegistryMiss() {
            XCTAssertThrowsError(
                try RclClient().createSubscription(
                    node: FakeNodeHandle(), typeName: absentType, typeHash: nil,
                    topic: "/gate_sub", qos: .sensorData, handler: { _, _ in })
            ) { assertRegistryMissError($0) }
        }

        func testBundledTypePassesGate() {
            // A bundled type must get past the gate and fail on the (fake) node
            // handle instead — the gate keys on the registry, not on the variant
            // as a whole.
            XCTAssertThrowsError(
                try RclClient().createPublisher(
                    node: FakeNodeHandle(), typeName: "sensor_msgs/msg/Imu", typeHash: nil,
                    topic: "/gate_bundled", qos: .sensorData)
            ) { error in
                guard case TransportError.publisherCreationFailed(let message) = error else {
                    return XCTFail("expected publisherCreationFailed, got \(error)")
                }
                XCTAssertTrue(message.contains("invalid node handle"), "unexpected: \(message)")
            }
        }

        func testRequireBundledTypesupportAcceptsBundledType() {
            XCTAssertNoThrow(try RclClient.requireBundledTypesupport("sensor_msgs/msg/Imu"))
        }
    }
#endif
