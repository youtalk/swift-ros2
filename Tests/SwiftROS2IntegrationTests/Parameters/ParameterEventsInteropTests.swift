import Foundation
import SwiftROS2
import SwiftROS2Messages
import SwiftROS2Transport
import XCTest

final class ParameterEventsInteropTests: XCTestCase {
    func testParameterEventsConsumableByROS2TopicEcho() async throws {
        guard let _ = ProcessInfo.processInfo.environment["LINUX_IP"]
        else { throw XCTSkip("Set LINUX_IP to run this test") }

        let ctx = try await ROS2Context(
            transport: .zenoh(locator: "tcp/127.0.0.1:7447", domainId: 0),
            distro: .jazzy)
        let node = try await ctx.createNode(name: "events_node", namespace: "/test")
        defer { Task { await node.destroy(); await ctx.shutdown() } }

        // Spawn a docker `ros2 topic echo --once` in the background. It
        // returns the next message and exits.
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = [
            "docker", "exec", "ros_jazzy_zenoh", "bash", "-c",
            "source /opt/ros/jazzy/setup.bash && export RMW_IMPLEMENTATION=rmw_zenoh_cpp && timeout 8 ros2 topic echo --once /parameter_events",
        ]
        let out = Pipe()
        p.standardOutput = out
        try p.run()

        // Give the echo subscriber a moment to subscribe before we publish.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        _ = try await node.declareParameter("rate", default: Int64(30))

        p.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(
            stdout.contains("rate"),
            "expected ros2 topic echo to receive ParameterEvent for 'rate', got: \(stdout)")
        XCTAssertTrue(
            stdout.contains("/test/events_node"),
            "expected event.node to match swift-ros2 fqn, got: \(stdout)")
    }
}
