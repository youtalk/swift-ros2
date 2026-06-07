import XCTest

@testable import SwiftROS2
@testable import SwiftROS2Transport

final class NodeRegistrationTests: XCTestCase {
    private func makeContext(
        _ session: MockTransportSession
    ) async throws -> ROS2Context {
        try await ROS2Context(
            transport: .zenoh(locator: "tcp/m:7447"),
            session: session
        )
    }

    func testCreateNodeRegistersNodeOnSession() async throws {
        let session = MockTransportSession()
        let ctx = try await makeContext(session)
        _ = try await ctx.createNode(
            name: "imu_node", namespace: "/ios",
            options: ROS2NodeOptions(startParameterServices: false)
        )
        XCTAssertEqual(session.registeredNodes.count, 1)
        XCTAssertEqual(session.registeredNodes.first?.name, "imu_node")
        XCTAssertEqual(session.registeredNodes.first?.namespace, "/ios")
    }

    func testDestroyNodeUnregistersNodeOnSession() async throws {
        let session = MockTransportSession()
        let ctx = try await makeContext(session)
        let node = try await ctx.createNode(
            name: "imu_node", namespace: "/ios",
            options: ROS2NodeOptions(startParameterServices: false)
        )
        await node.destroy()
        XCTAssertEqual(session.unregisteredNodes.count, 1)
        XCTAssertEqual(session.unregisteredNodes.first?.name, "imu_node")
        XCTAssertEqual(session.unregisteredNodes.first?.namespace, "/ios")
    }

    func testRegisterNodeFailureDoesNotTriggerUnregister() async throws {
        let session = MockTransportSession()
        session.registerNodeShouldThrow = TransportError.connectionFailed("simulated")
        let ctx = try await makeContext(session)
        do {
            _ = try await ctx.createNode(
                name: "imu_node", namespace: "/ios",
                options: ROS2NodeOptions(startParameterServices: false))
            XCTFail("Expected createNode to throw")
        } catch {}
        XCTAssertEqual(session.registeredNodes.count, 0)
        XCTAssertEqual(session.unregisteredNodes.count, 0)
    }

    func testContextShutdownUnregistersAllNodes() async throws {
        let session = MockTransportSession()
        let ctx = try await makeContext(session)
        _ = try await ctx.createNode(
            name: "a", namespace: "/ns",
            options: ROS2NodeOptions(startParameterServices: false))
        _ = try await ctx.createNode(
            name: "b", namespace: "/ns",
            options: ROS2NodeOptions(startParameterServices: false))
        await ctx.shutdown()
        XCTAssertEqual(session.unregisteredNodes.count, 2)
    }
}
