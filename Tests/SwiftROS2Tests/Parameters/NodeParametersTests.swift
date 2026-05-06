import SwiftROS2Transport
import XCTest

@testable import SwiftROS2

final class NodeParametersTests: XCTestCase {
    private func makeContext() async throws -> ROS2Context {
        let config = TransportConfig.zenoh(locator: "tcp/mock:7447")
        let mock = MockTransportSession()
        // Phase-3 Task 10 auto-registers parameter services on createNode;
        // give the mock an echo dispatcher so that registration succeeds.
        mock.installEchoServiceTransport()
        return try await ROS2Context(transport: config, session: mock)
    }

    func testDeclareAndGet() async throws {
        let ctx = try await makeContext()
        let node = try await ctx.createNode(name: "node_params_test")

        let stored = try await node.declareParameter(
            "rate", default: Int64(30))
        XCTAssertEqual(stored, 30)

        let p = try await node.getParameter("rate")
        XCTAssertEqual(p, ROS2Parameter(name: "rate", value: .integer(30)))
    }

    func testHasParameter() async throws {
        let ctx = try await makeContext()
        let node = try await ctx.createNode(name: "node_params_has")
        let before = await node.hasParameter("nope")
        XCTAssertFalse(before)
        _ = try await node.declareParameter("rate", default: Int64(1))
        let after = await node.hasParameter("rate")
        XCTAssertTrue(after)
    }

    func testSetWithRange() async throws {
        let ctx = try await makeContext()
        let node = try await ctx.createNode(name: "node_params_range")
        _ = try await node.declareParameter(
            "rate",
            default: Int64(30),
            descriptor: ROS2ParameterDescriptor(
                name: "rate", type: .integer, integerRange: 1...120))

        let ok = await node.setParameter(
            ROS2Parameter(name: "rate", value: .integer(60)))
        XCTAssertTrue(ok.successful)

        let bad = await node.setParameter(
            ROS2Parameter(name: "rate", value: .integer(999)))
        XCTAssertFalse(bad.successful)
    }

    func testListAndDescribe() async throws {
        let ctx = try await makeContext()
        let node = try await ctx.createNode(name: "node_params_list")
        _ = try await node.declareParameter(
            "rate",
            default: Int64(30),
            descriptor: ROS2ParameterDescriptor(name: "rate", type: .integer))
        _ = try await node.declareParameter("alpha", default: 0.5)

        let list = await node.listParameters()
        XCTAssertEqual(Set(list.names), ["alpha", "rate"])

        let d = try await node.describeParameter("rate")
        XCTAssertEqual(d.type, .integer)
    }

    func testGetParameterOrDefaultFallback() async throws {
        let ctx = try await makeContext()
        let node = try await ctx.createNode(name: "node_params_default")
        let v = await node.getParameterOrDefault("missing", default: Int64(7))
        XCTAssertEqual(v, 7)
    }

    func testDeclareOverridesNonEmptyDescriptorName() async throws {
        // If the caller passes a descriptor whose .name disagrees with the
        // declared key, the key wins — describeParameter must then report
        // the same name we declared under.
        let ctx = try await makeContext()
        let node = try await ctx.createNode(name: "node_params_name_override")
        _ = try await node.declareParameter(
            "rate",
            default: Int64(30),
            descriptor: ROS2ParameterDescriptor(name: "fps", type: .integer))
        let d = try await node.describeParameter("rate")
        XCTAssertEqual(d.name, "rate")
    }
}
