import Foundation
import SwiftROS2
import SwiftROS2Messages
import SwiftROS2Transport
import XCTest

// Exec's the `ros2` CLI via Process — native-host only; unavailable on Mac Catalyst.
#if !targetEnvironment(macCatalyst)
    /// LAN-gated `ros2 param` CLI interop. Skips when `LINUX_IP` is unset
    /// or empty. Requires two running docker containers on the host:
    ///   - `ros_jazzy_zenoh` — ROS 2 Jazzy + `rmw_zenoh_cpp` + an active
    ///     `rmw_zenohd` peering at `tcp/127.0.0.1:7447`.
    ///   - `ros_jazzy_dds`   — ROS 2 Jazzy + `rmw_cyclonedds_cpp` reachable
    ///     on the chosen `ROS_DOMAIN_ID`.
    ///
    /// The compose files for these containers live in the downstream Conduit
    /// repository under `support/docker/`; swift-ros2 itself does not ship a
    /// docker stack. Bring the containers up there before running the tests.
    final class ROS2ParamCLIInteropTests: XCTestCase {
        private func skipIfNoLinuxIP() throws -> String {
            guard let ip = ProcessInfo.processInfo.environment["LINUX_IP"], !ip.isEmpty
            else { throw XCTSkip("Set LINUX_IP to run this test (e.g., LINUX_IP=192.168.1.85)") }
            return ip
        }

        /// Exec a command in the named docker container; returns stdout. Throws
        /// on non-zero exit code with stderr in the message.
        private func dockerExec(container: String, _ shell: String) throws -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["docker", "exec", container, "bash", "-c", shell]
            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err
            try p.run()
            p.waitUntilExit()
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if p.terminationStatus != 0 {
                let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw NSError(
                    domain: "DockerExec", code: Int(p.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "\(shell) failed: \(stderr)"])
            }
            return stdout
        }

        func testParamListGetSetDescribeOverZenoh() async throws {
            _ = try skipIfNoLinuxIP()
            let ctx = try await ROS2Context(
                transport: .zenoh(locator: "tcp/127.0.0.1:7447", domainId: 0),
                distro: .jazzy)
            let node = try await ctx.createNode(name: "cli_node", namespace: "/test")
            defer {
                Task {
                    await node.destroy()
                    await ctx.shutdown()
                }
            }

            _ = try await node.declareParameter("rate", default: Int64(30))
            _ = try await node.declareParameter("greeting", default: "hi")
            _ = try await node.declareParameter("enabled", default: true)

            // Allow Zenoh discovery to settle.
            try await Task.sleep(nanoseconds: 1_500_000_000)

            let prelude = "source /opt/ros/jazzy/setup.bash && export RMW_IMPLEMENTATION=rmw_zenoh_cpp"

            let listOut = try dockerExec(
                container: "ros_jazzy_zenoh",
                "\(prelude) && ros2 param list /test/cli_node")
            XCTAssertTrue(listOut.contains("rate"), "list missing rate: \(listOut)")
            XCTAssertTrue(listOut.contains("greeting"))
            XCTAssertTrue(listOut.contains("enabled"))

            let getOut = try dockerExec(
                container: "ros_jazzy_zenoh",
                "\(prelude) && ros2 param get /test/cli_node rate")
            XCTAssertTrue(getOut.contains("30"), "get rate not 30: \(getOut)")

            let setOut = try dockerExec(
                container: "ros_jazzy_zenoh",
                "\(prelude) && ros2 param set /test/cli_node rate 60")
            XCTAssertTrue(
                setOut.contains("successful") || setOut.contains("Set"),
                "set rate output unexpected: \(setOut)")

            let storedAfterSet = try await node.getParameter("rate")
            XCTAssertEqual(storedAfterSet.value, .integer(60))

            let describeOut = try dockerExec(
                container: "ros_jazzy_zenoh",
                "\(prelude) && ros2 param describe /test/cli_node rate")
            XCTAssertTrue(
                describeOut.contains("Type: integer") || describeOut.contains("integer"),
                "describe rate type missing: \(describeOut)")
        }

        func testParamListGetSetDescribeOverDDS() async throws {
            let linuxIP = try skipIfNoLinuxIP()
            let domain = 99
            let ctx = try await ROS2Context(
                transport: .ddsUnicast(
                    peers: [DDSPeer.peer(address: linuxIP, domainId: domain)],
                    domainId: domain),
                distro: .jazzy, domainId: domain)
            let node = try await ctx.createNode(name: "cli_node", namespace: "/test")
            defer {
                Task {
                    await node.destroy()
                    await ctx.shutdown()
                }
            }

            _ = try await node.declareParameter("rate", default: Int64(30))
            _ = try await node.declareParameter("greeting", default: "hi")

            // CycloneDDS SPDP/SEDP needs more time than Zenoh.
            try await Task.sleep(nanoseconds: 4_000_000_000)

            let prelude =
                "source /opt/ros/jazzy/setup.bash && export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp && export ROS_DOMAIN_ID=\(domain)"

            let listOut = try dockerExec(
                container: "ros_jazzy_dds",
                "\(prelude) && ros2 param list /test/cli_node")
            XCTAssertTrue(listOut.contains("rate"), "list missing rate (DDS): \(listOut)")

            let setOut = try dockerExec(
                container: "ros_jazzy_dds",
                "\(prelude) && ros2 param set /test/cli_node rate 60")
            XCTAssertTrue(
                setOut.contains("successful") || setOut.contains("Set"),
                "set rate (DDS) unexpected: \(setOut)")

            let storedAfterSet = try await node.getParameter("rate")
            XCTAssertEqual(storedAfterSet.value, .integer(60))
        }
    }
#endif
