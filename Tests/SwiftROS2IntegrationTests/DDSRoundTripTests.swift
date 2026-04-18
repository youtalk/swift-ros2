import SwiftROS2
import SwiftROS2Messages
import SwiftROS2Transport
import XCTest

/// Round-trip integration test over CycloneDDS. Requires:
/// - `LINUX_IP` env var (the host running a matching-domain ros2 topic echo)
/// - A running `ros2 topic echo /test/imu` on that host with
///   `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` and `ROS_DOMAIN_ID=99`
///
/// Uses unicast discovery so the test works across WiFi / Parallels /
/// environments where DDS multicast may be filtered.
final class DDSRoundTripTests: XCTestCase {
    func testImuPublishReceivedByLinuxDDS() async throws {
        guard let linuxIP = ProcessInfo.processInfo.environment["LINUX_IP"], !linuxIP.isEmpty else {
            throw XCTSkip("Set LINUX_IP to run this test (e.g., LINUX_IP=192.168.1.85)")
        }

        let domain = 99
        let ctx = try await ROS2Context(
            transport: .ddsUnicast(
                peers: [DDSPeer.peer(address: linuxIP, domainId: domain)],
                domainId: domain
            ),
            distro: .jazzy,
            domainId: domain
        )
        let node = try await ctx.createNode(name: "swift_ros2_it_dds", namespace: "/test")
        let pub = try await node.createPublisher(Imu.self, topic: "imu")

        // DDS endpoint discovery through SPDP/SEDP is slower than Zenoh.
        try await Task.sleep(nanoseconds: 3_000_000_000)

        for i in 0..<10 {
            try pub.publish(
                Imu(
                    header: Header.now(frameId: "imu_link"),
                    linearAcceleration: Vector3(x: 0.0, y: 0.0, z: 9.81 + Double(i) * 0.01)
                ))
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        try await Task.sleep(nanoseconds: 500_000_000)
        await ctx.shutdown()
    }
}
