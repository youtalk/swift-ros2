import SwiftROS2Messages
import SwiftROS2Transport
import XCTest

@testable import SwiftROS2

final class ParameterServicesTests: XCTestCase {
    private func makeContextAndNode(
        nodeName: String = "talker",
        options: ROS2NodeOptions = .default
    ) async throws -> (ROS2Context, ROS2Node) {
        let mock = MockTransportSession()
        mock.installEchoServiceTransport()
        let ctx = try await ROS2Context(
            transport: .zenoh(locator: "tcp/mock:7447"), session: mock)
        let node = try await ctx.createNode(name: nodeName, options: options)
        return (ctx, node)
    }

    func testStartParameterServicesRegistersAllSixRoutes() async throws {
        let (_, node) = try await makeContextAndNode(
            nodeName: "talker",
            options: ROS2NodeOptions(startParameterServices: false))

        // Manual registration since auto-start is opted out.
        try await node.startParameterServices()

        // Each client.waitForService is satisfied by MockTransportSession's
        // echo mode as long as the matching server name was registered.
        for path in [
            "/talker/get_parameters",
            "/talker/set_parameters",
            "/talker/set_parameters_atomically",
            "/talker/list_parameters",
            "/talker/describe_parameters",
            "/talker/get_parameter_types",
        ] {
            let cli = try await node.createClient(GetParametersSrv.self, name: path)
            try await cli.waitForService(timeout: .milliseconds(100))
        }
    }

    func testStartParameterServicesIsIdempotent() async throws {
        let (_, node) = try await makeContextAndNode(
            options: ROS2NodeOptions(startParameterServices: false))

        try await node.startParameterServices()
        try await node.startParameterServices()  // second call must be a no-op

        // No exception — and the next createClient still works.
        let cli = try await node.createClient(
            GetParametersSrv.self, name: "/talker/get_parameters")
        try await cli.waitForService(timeout: .milliseconds(100))
    }
}
