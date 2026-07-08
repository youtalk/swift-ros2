#if SWIFT_ROS2_RCL && os(Linux)
    import Foundation
    import SwiftROS2RCL
    import XCTest

    /// MZ5: on Linux the rmw is process-global and chosen by RMW_IMPLEMENTATION.
    /// RclClient sets it from the transport type before rcl_init and restores it.
    final class RclLinuxRmwEnvTests: XCTestCase {
        func testZenohSelectsRmwZenohAndRestores() {
            let outer = getenv("RMW_IMPLEMENTATION").map { String(cString: $0) }
            defer {
                if let p = outer { setenv("RMW_IMPLEMENTATION", p, 1) } else { unsetenv("RMW_IMPLEMENTATION") }
            }
            unsetenv("RMW_IMPLEMENTATION")
            let c = RclClient()
            XCTAssertTrue(c.applyRmwImplementationEnv(zenoh: true))
            XCTAssertEqual(getenv("RMW_IMPLEMENTATION").map { String(cString: $0) }, "rmw_zenoh_cpp")
            c.restoreRmwImplementationEnv()
            XCTAssertNil(getenv("RMW_IMPLEMENTATION").map { String(cString: $0) })
        }

        func testDdsSelectsRmwCyclonedds() {
            let outer = getenv("RMW_IMPLEMENTATION").map { String(cString: $0) }
            defer {
                if let p = outer { setenv("RMW_IMPLEMENTATION", p, 1) } else { unsetenv("RMW_IMPLEMENTATION") }
            }
            unsetenv("RMW_IMPLEMENTATION")
            let c = RclClient()
            XCTAssertTrue(c.applyRmwImplementationEnv(zenoh: false))
            XCTAssertEqual(getenv("RMW_IMPLEMENTATION").map { String(cString: $0) }, "rmw_cyclonedds_cpp")
            c.restoreRmwImplementationEnv()
        }
    }
#endif
