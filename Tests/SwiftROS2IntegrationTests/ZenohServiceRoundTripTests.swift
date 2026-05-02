import SwiftROS2
import SwiftROS2Messages
import SwiftROS2Transport
import XCTest

/// Round-trip integration test for Service Server / Client over Zenoh.
/// Requires:
/// - `LINUX_IP` env var set to the host running `rmw_zenohd` (skipped if absent).
/// - On the host: `ros2 run rmw_zenoh_cpp rmw_zenohd` listening on
///   `tcp/<LINUX_IP>:7447`.
/// - On the host: `ros2 service call /test/trigger std_srvs/srv/Trigger {}`
///   running with `RMW_IMPLEMENTATION=rmw_zenoh_cpp` (the swift-ros2 client
///   side acts as the service server in this scenario).
///
/// Skips gracefully when `LINUX_IP` is not set so CI stays deterministic.
final class ZenohServiceRoundTripTests: XCTestCase {
    /// Calls a remote service hosted on the Linux host. The remote service
    /// is expected to be a stock `std_srvs/srv/Trigger` server (e.g. the
    /// `srv-server` example running on the host, or any rmw_zenoh_cpp
    /// node serving `/test/trigger`).
    func testTriggerCallOverZenoh() async throws {
        guard let linuxIP = ProcessInfo.processInfo.environment["LINUX_IP"], !linuxIP.isEmpty else {
            throw XCTSkip("Set LINUX_IP to run this test (e.g., LINUX_IP=192.168.1.85)")
        }

        let ctx = try await ROS2Context(
            transport: .zenoh(locator: "tcp/\(linuxIP):7447", domainId: 0, wireMode: .jazzy),
            distro: .jazzy
        )
        let node = try await ctx.createNode(name: "swift_ros2_it_zenoh_srv", namespace: "/test")
        let cli = try await node.createClient(TriggerSrv.self, name: "trigger")

        // Zenoh discovery is effectively instant via the admin space; a
        // small explicit wait still matches what rmw_zenoh_cpp does.
        try await Task.sleep(nanoseconds: 500_000_000)

        let response = try await cli.call(.init(), timeout: .seconds(5))
        // A live ROS 2 Trigger server typically replies success=true; the
        // message field is implementation-dependent. Accept any non-empty
        // reply as "round-trip succeeded".
        XCTAssertTrue(response.success || !response.message.isEmpty)

        await ctx.shutdown()
    }
}
