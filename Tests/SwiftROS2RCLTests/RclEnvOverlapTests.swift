// RclEnvOverlapTests.swift
// Overlapping-context env discipline for the process-global discovery slots.
// RMW_IMPLEMENTATION got the static refcounted save/restore in #163; these
// tests pin the same contract for CYCLONEDDS_URI and the ZENOH_* slots:
// a non-LIFO teardown must neither restore a stale intermediate value nor
// leave the env pointing at a deleted temp config file. All hermetic — no
// rmw is started.

#if SWIFT_ROS2_RCL
    import Foundation
    import SwiftROS2RCL
    import XCTest

    final class RclEnvOverlapTests: XCTestCase {
        private var outerCyclonedDDSURI: String?
        private var outerZenohConfigURI: String?
        private var outerZenohRouterCheckAttempts: String?

        override func setUp() {
            super.setUp()
            outerCyclonedDDSURI = env("CYCLONEDDS_URI")
            outerZenohConfigURI = env("ZENOH_SESSION_CONFIG_URI")
            outerZenohRouterCheckAttempts = env("ZENOH_ROUTER_CHECK_ATTEMPTS")
            unsetenv("CYCLONEDDS_URI")
            unsetenv("ZENOH_SESSION_CONFIG_URI")
            unsetenv("ZENOH_ROUTER_CHECK_ATTEMPTS")
        }

        override func tearDown() {
            restore("CYCLONEDDS_URI", outerCyclonedDDSURI)
            restore("ZENOH_SESSION_CONFIG_URI", outerZenohConfigURI)
            restore("ZENOH_ROUTER_CHECK_ATTEMPTS", outerZenohRouterCheckAttempts)
            super.tearDown()
        }

        private func env(_ name: String) -> String? {
            getenv(name).map { String(cString: $0) }
        }

        private func restore(_ name: String, _ value: String?) {
            if let value { setenv(name, value, 1) } else { unsetenv(name) }
        }

        // Non-LIFO teardown: the FIRST applier restores first. The slot must
        // keep serving the surviving holder and only return to the pre-first
        // value when the LAST holder drops.
        func testOverlappingDiscoveryEnvRestoresPreFirstValueOnLastTeardown() {
            let a = RclClient()
            let b = RclClient()
            XCTAssertTrue(
                a.applyDiscoveryEnv(
                    domainId: 0, unicastPeerAddresses: ["10.0.0.1"], networkInterface: nil))
            XCTAssertTrue(
                b.applyDiscoveryEnv(
                    domainId: 0, unicastPeerAddresses: ["10.0.0.2"], networkInterface: nil))

            a.restoreDiscoveryEnv()
            let midValue = env("CYCLONEDDS_URI")
            XCTAssertNotNil(midValue, "first-applier teardown must not clear the live slot")
            XCTAssertTrue(
                midValue?.contains("10.0.0.2") == true,
                "slot must keep the surviving holder's XML, got: \(midValue ?? "unset")")

            b.restoreDiscoveryEnv()
            XCTAssertNil(env("CYCLONEDDS_URI"), "last teardown must restore the pre-first value")
        }

        func testDoubleRestoreDoesNotUnderflowTheDiscoveryHold() {
            let a = RclClient()
            let b = RclClient()
            XCTAssertTrue(
                a.applyDiscoveryEnv(
                    domainId: 0, unicastPeerAddresses: ["10.0.0.1"], networkInterface: nil))
            XCTAssertTrue(
                b.applyDiscoveryEnv(
                    domainId: 0, unicastPeerAddresses: ["10.0.0.2"], networkInterface: nil))
            a.restoreDiscoveryEnv()
            a.restoreDiscoveryEnv()  // second restore of the same instance: no-op
            XCTAssertNotNil(
                env("CYCLONEDDS_URI"),
                "a repeated per-instance restore must not decrement another holder's ref")
            b.restoreDiscoveryEnv()
            XCTAssertNil(env("CYCLONEDDS_URI"))
        }

        func testOverlappingZenohEnvKeepsLiveConfigFileUntilLastTeardown() throws {
            let a = RclClient()
            let b = RclClient()
            XCTAssertTrue(a.applyZenohSessionEnv(locator: "tcp/10.0.0.1:7447"))
            XCTAssertTrue(b.applyZenohSessionEnv(locator: "tcp/10.0.0.2:7447"))
            let livePath = try XCTUnwrap(env("ZENOH_SESSION_CONFIG_URI"))

            a.restoreZenohSessionEnv()
            XCTAssertEqual(
                env("ZENOH_SESSION_CONFIG_URI"), livePath,
                "first-applier teardown must not repoint or clear the live slot")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: livePath),
                "the exported config file must stay readable while any holder lives")

            b.restoreZenohSessionEnv()
            XCTAssertNil(env("ZENOH_SESSION_CONFIG_URI"))
            XCTAssertNil(env("ZENOH_ROUTER_CHECK_ATTEMPTS"))
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: livePath),
                "the last teardown must delete every held temp config file")
        }
    }
#endif
