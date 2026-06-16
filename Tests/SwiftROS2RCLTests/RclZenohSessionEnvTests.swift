#if SWIFT_ROS2_RCL
    import Foundation
    import SwiftROS2RCL
    import SwiftROS2Transport
    import XCTest

    /// MZ1 router plumbing: the RCL-over-Zenoh path injects the router locator
    /// into rmw_zenoh_cpp via a generated session-config json5 pointed at by
    /// ZENOH_SESSION_CONFIG_URI — the Zenoh analog of the DDS CYCLONEDDS_URI
    /// plumbing in RclDiscoveryEnvTests. These tests are pure: no rmw, no router.
    final class RclZenohSessionEnvTests: XCTestCase {
        func testSessionConfigCarriesConnectEndpointInClientMode() {
            let cfg = RclClient().makeZenohSessionConfigJSON5(locator: "tcp/192.168.1.85:7447")
            XCTAssertTrue(cfg.contains("\"tcp/192.168.1.85:7447\""), "connect endpoint missing")
            XCTAssertTrue(cfg.contains("mode: \"client\""), "client mode missing")
            XCTAssertTrue(cfg.contains("connect"), "connect block missing")
            XCTAssertTrue(cfg.contains("enabled: false"), "multicast scouting must be disabled")
        }

        func testApplyZenohSessionEnvExportsAndRestores() {
            // Hermetic: snapshot + restore whatever the environment already had.
            let outerURI = getenv("ZENOH_SESSION_CONFIG_URI").map { String(cString: $0) }
            let outerAtt = getenv("ZENOH_ROUTER_CHECK_ATTEMPTS").map { String(cString: $0) }
            defer {
                if let p = outerURI {
                    setenv("ZENOH_SESSION_CONFIG_URI", p, 1)
                } else {
                    unsetenv("ZENOH_SESSION_CONFIG_URI")
                }
                if let p = outerAtt {
                    setenv("ZENOH_ROUTER_CHECK_ATTEMPTS", p, 1)
                } else {
                    unsetenv("ZENOH_ROUTER_CHECK_ATTEMPTS")
                }
            }
            unsetenv("ZENOH_SESSION_CONFIG_URI")  // known-clear starting point
            unsetenv("ZENOH_ROUTER_CHECK_ATTEMPTS")

            let client = RclClient()
            XCTAssertTrue(client.applyZenohSessionEnv(locator: "tcp/192.168.1.85:7447"))
            let uri = getenv("ZENOH_SESSION_CONFIG_URI").map { String(cString: $0) }
            XCTAssertNotNil(uri)
            let contents = (try? String(contentsOfFile: uri!, encoding: .utf8)) ?? ""
            XCTAssertTrue(contents.contains("tcp/192.168.1.85:7447"))
            XCTAssertEqual(
                getenv("ZENOH_ROUTER_CHECK_ATTEMPTS").map { String(cString: $0) }, "1",
                "router check attempts must be pinned to 1 (non-blocking)")

            client.restoreZenohSessionEnv()
            XCTAssertNil(getenv("ZENOH_SESSION_CONFIG_URI").map { String(cString: $0) })
            XCTAssertNil(getenv("ZENOH_ROUTER_CHECK_ATTEMPTS").map { String(cString: $0) })
            XCTAssertFalse(FileManager.default.fileExists(atPath: uri!), "temp config not cleaned up")
        }

        func testRestoreZenohSessionEnvIsNoOpWhenNothingApplied() {
            // Calling restore on a fresh client must not crash or mutate the env.
            let outerURI = getenv("ZENOH_SESSION_CONFIG_URI").map { String(cString: $0) }
            RclClient().restoreZenohSessionEnv()
            XCTAssertEqual(getenv("ZENOH_SESSION_CONFIG_URI").map { String(cString: $0) }, outerURI)
        }
    }
#endif
