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

    // MARK: - RclAmentPrefixEnvTests (S2)

    /// rmw_zenoh_cpp hard-requires AMENT_PREFIX_PATH at rmw_init (live-proven:
    /// context creation threw "Environment variable AMENT_PREFIX_PATH is not
    /// set or empty"). `applyAmentPrefixEnv` synthesizes a minimal ament prefix
    /// so consumers need not export one; `restoreZenohSessionEnv` undoes it.
    final class RclAmentPrefixEnvTests: XCTestCase {
        /// Hermetic: snapshot + restore whatever the environment already had.
        private var outerAmentPrefixPath: String?

        override func setUp() {
            super.setUp()
            outerAmentPrefixPath = getenv("AMENT_PREFIX_PATH").map { String(cString: $0) }
        }

        override func tearDown() {
            if let p = outerAmentPrefixPath {
                setenv("AMENT_PREFIX_PATH", p, 1)
            } else {
                unsetenv("AMENT_PREFIX_PATH")
            }
            super.tearDown()
        }

        private var currentAmentPrefixPath: String? {
            getenv("AMENT_PREFIX_PATH").map { String(cString: $0) }
        }

        /// Create a directory carrying the rmw_zenoh_cpp resource-index marker
        /// (a "valid user prefix" as far as ament_index resolution goes).
        private func makeValidUserPrefix() throws -> URL {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("swift-ros2-test-prefix-\(UUID().uuidString)")
            let markerDir = root.appendingPathComponent(
                "share/ament_index/resource_index/packages", isDirectory: true)
            try FileManager.default.createDirectory(
                at: markerDir, withIntermediateDirectories: true)
            try Data().write(to: markerDir.appendingPathComponent("rmw_zenoh_cpp"))
            return root
        }

        func testApplySynthesizesPrefixWhenUnset() throws {
            unsetenv("AMENT_PREFIX_PATH")
            let client = RclClient()
            try client.applyAmentPrefixEnv()

            let prefix = try XCTUnwrap(currentAmentPrefixPath, "env not exported")
            let marker = "\(prefix)/share/ament_index/resource_index/packages/rmw_zenoh_cpp"
            let sessionCfg = "\(prefix)/share/rmw_zenoh_cpp/config/DEFAULT_RMW_ZENOH_SESSION_CONFIG.json5"
            let routerCfg = "\(prefix)/share/rmw_zenoh_cpp/config/DEFAULT_RMW_ZENOH_ROUTER_CONFIG.json5"
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker), "resource marker missing")
            XCTAssertTrue(FileManager.default.fileExists(atPath: sessionCfg), "session config missing")
            XCTAssertTrue(FileManager.default.fileExists(atPath: routerCfg), "router config missing")
            let session = try String(contentsOfFile: sessionCfg, encoding: .utf8)
            XCTAssertTrue(session.contains("mode: \"peer\""), "session config is not the peer default")
            let router = try String(contentsOfFile: routerCfg, encoding: .utf8)
            XCTAssertTrue(router.contains("mode: \"router\""), "router config is not the router default")
            XCTAssertTrue(
                RclClient.amentPrefixPathContainsRmwZenoh(prefix),
                "synthesized prefix must satisfy the resolution rule it was created for")

            client.restoreZenohSessionEnv()
            XCTAssertNil(currentAmentPrefixPath, "env not restored to unset")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: prefix), "temp prefix not cleaned up")
        }

        func testApplyPrependsWhenResourceMissing() throws {
            // A set-but-unusable AMENT_PREFIX_PATH (no rmw_zenoh_cpp resource)
            // gets the synthesized prefix PREPENDED, keeping the user's other
            // ament resources resolvable; restore brings back the exact value.
            let bogus = FileManager.default.temporaryDirectory
                .appendingPathComponent("swift-ros2-test-bogus-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: bogus, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: bogus) }
            setenv("AMENT_PREFIX_PATH", bogus.path, 1)

            let client = RclClient()
            try client.applyAmentPrefixEnv()
            let value = try XCTUnwrap(currentAmentPrefixPath)
            XCTAssertTrue(value.hasSuffix(":\(bogus.path)"), "existing value not preserved: \(value)")
            XCTAssertTrue(
                RclClient.amentPrefixPathContainsRmwZenoh(value),
                "prepended prefix must make the resource resolvable")

            client.restoreZenohSessionEnv()
            XCTAssertEqual(currentAmentPrefixPath, bogus.path, "prior value not restored")
        }

        func testApplyLeavesValidUserPrefixUntouched() throws {
            let userPrefix = try makeValidUserPrefix()
            defer { try? FileManager.default.removeItem(at: userPrefix) }
            setenv("AMENT_PREFIX_PATH", userPrefix.path, 1)

            let client = RclClient()
            try client.applyAmentPrefixEnv()
            XCTAssertEqual(currentAmentPrefixPath, userPrefix.path, "valid user prefix was touched")

            // Nothing was applied, so restore must be a no-op for this slot.
            client.restoreZenohSessionEnv()
            XCTAssertEqual(currentAmentPrefixPath, userPrefix.path, "no-op restore mutated the env")
        }

        func testAmentPrefixPathContainsRmwZenohRule() throws {
            let valid = try makeValidUserPrefix()
            defer { try? FileManager.default.removeItem(at: valid) }
            XCTAssertTrue(RclClient.amentPrefixPathContainsRmwZenoh(valid.path))
            XCTAssertTrue(
                RclClient.amentPrefixPathContainsRmwZenoh("/nonexistent:\(valid.path)"),
                "any prefix in the colon-separated list must satisfy the rule")
            XCTAssertFalse(RclClient.amentPrefixPathContainsRmwZenoh("/nonexistent"))
            XCTAssertFalse(RclClient.amentPrefixPathContainsRmwZenoh(""))
        }

        func testCreateContextWithoutAmentEnvDoesNotThrowAmentError() {
            // The live-proven failure mode: with no AMENT_PREFIX_PATH, rmw_init
            // used to fail with "Environment variable AMENT_PREFIX_PATH is not
            // set or empty" (rmw_init.cpp:114). With the synthesis in place,
            // context creation must get past that error — it either succeeds
            // (router reachable at the locator) or fails for a non-AMENT reason
            // (e.g. no router). Either way the env slots are restored.
            unsetenv("AMENT_PREFIX_PATH")
            let client = RclClient()
            do {
                try client.createContext(
                    domainId: 0, unicastPeerAddresses: [], networkInterface: nil,
                    zenohRouterLocator: "tcp/127.0.0.1:7447")
                client.destroyContext()
            } catch {
                let description = String(describing: error)
                XCTAssertFalse(
                    description.contains("AMENT_PREFIX_PATH"),
                    "the AMENT error resurfaced: \(description)")
            }
            XCTAssertNil(currentAmentPrefixPath, "AMENT_PREFIX_PATH not restored to unset")
            XCTAssertNil(
                getenv("ZENOH_SESSION_CONFIG_URI").map { String(cString: $0) },
                "ZENOH_SESSION_CONFIG_URI not restored to unset")
        }
    }

    // MARK: - RclZenohTransportConfigTests (S6)

    /// `.rcl` / `.rclUnicast` target rmw_cyclonedds: in the zenoh-rmw build they
    /// would open rmw_zenoh with default session settings while exporting a
    /// meaningless CYCLONEDDS_URI. The supported transports here are `.zenoh`
    /// (RCL via rmw_zenoh) and `.dds` (wire CycloneDDS) — reject the rest.
    final class RclZenohTransportConfigTests: XCTestCase {
        private func assertRejected(_ config: TransportConfig) async {
            do {
                _ = try await ROS2Context(transport: config)
                XCTFail("expected unsupportedFeature for \(config.type)")
            } catch TransportError.unsupportedFeature(let message) {
                XCTAssertTrue(message.contains(".zenoh"), "remedy missing from: \(message)")
            } catch {
                XCTFail("expected unsupportedFeature, got \(error)")
            }
        }

        func testRclConfigIsRejected() async {
            await assertRejected(.rcl())
        }

        func testRclUnicastConfigIsRejected() async {
            await assertRejected(.rclUnicast(peers: [DDSPeer(address: "192.168.1.10")]))
        }
    }
#endif
