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

    func testGetParametersReturnsDeclaredValues() async throws {
        let (_, node) = try await makeContextAndNode()
        _ = try await node.declareParameter("rate", default: Int64(30))
        _ = try await node.declareParameter("alpha", default: 0.5)
        try await node.startParameterServices()

        let cli = try await node.createClient(
            GetParametersSrv.self, name: "/talker/get_parameters")
        try await cli.waitForService(timeout: .milliseconds(100))

        let resp = try await cli.call(
            GetParametersRequest(names: ["rate", "alpha", "missing"]),
            timeout: .seconds(1))

        XCTAssertEqual(resp.values.count, 3)
        XCTAssertEqual(resp.values[0].type, 2)  // PARAMETER_INTEGER
        XCTAssertEqual(resp.values[0].integerValue, 30)
        XCTAssertEqual(resp.values[1].type, 3)  // PARAMETER_DOUBLE
        XCTAssertEqual(resp.values[1].doubleValue, 0.5)
        XCTAssertEqual(resp.values[2].type, 0)  // PARAMETER_NOT_SET — missing name
    }

    func testSetParametersAcceptsValidWritesAndReportsRangeFailure() async throws {
        let (_, node) = try await makeContextAndNode()
        _ = try await node.declareParameter(
            "rate",
            default: Int64(30),
            descriptor: ROS2ParameterDescriptor(
                name: "rate", type: .integer, integerRange: 1...120))
        _ = try await node.declareParameter("alpha", default: 0.5)
        try await node.startParameterServices()

        let cli = try await node.createClient(
            SetParametersSrv.self, name: "/talker/set_parameters")
        try await cli.waitForService(timeout: .milliseconds(100))

        var goodInt = SwiftROS2Messages.ParameterValue()
        goodInt.type = 2
        goodInt.integerValue = 60
        var badInt = SwiftROS2Messages.ParameterValue()
        badInt.type = 2
        badInt.integerValue = 999  // outside 1...120
        var goodDouble = SwiftROS2Messages.ParameterValue()
        goodDouble.type = 3
        goodDouble.doubleValue = 0.75

        let resp = try await cli.call(
            SetParametersRequest(parameters: [
                Parameter(name: "rate", value: goodInt),
                Parameter(name: "rate", value: badInt),
                Parameter(name: "alpha", value: goodDouble),
                Parameter(name: "missing", value: goodInt),
            ]),
            timeout: .seconds(1))

        XCTAssertEqual(resp.results.count, 4)
        XCTAssertTrue(resp.results[0].successful)
        XCTAssertFalse(resp.results[1].successful)
        XCTAssertTrue(resp.results[2].successful)
        XCTAssertFalse(resp.results[3].successful)  // not declared

        let stored = try await node.getParameter("rate")
        XCTAssertEqual(stored.value, .integer(60))
        let alpha = try await node.getParameter("alpha")
        XCTAssertEqual(alpha.value, .double(0.75))
    }

    func testSetParametersAtomicallyRollsBackOnFailure() async throws {
        let (_, node) = try await makeContextAndNode()
        _ = try await node.declareParameter(
            "rate",
            default: Int64(30),
            descriptor: ROS2ParameterDescriptor(
                name: "rate", type: .integer, integerRange: 1...120))
        _ = try await node.declareParameter("alpha", default: 0.5)
        try await node.startParameterServices()

        let cli = try await node.createClient(
            SetParametersAtomicallySrv.self, name: "/talker/set_parameters_atomically")
        try await cli.waitForService(timeout: .milliseconds(100))

        var goodInt = SwiftROS2Messages.ParameterValue()
        goodInt.type = 2
        goodInt.integerValue = 60
        var goodDouble = SwiftROS2Messages.ParameterValue()
        goodDouble.type = 3
        goodDouble.doubleValue = 0.9
        var badInt = SwiftROS2Messages.ParameterValue()
        badInt.type = 2
        badInt.integerValue = 999

        // First call: every parameter valid → atomic success.
        let okResp = try await cli.call(
            SetParametersAtomicallyRequest(parameters: [
                Parameter(name: "rate", value: goodInt),
                Parameter(name: "alpha", value: goodDouble),
            ]),
            timeout: .seconds(1))
        XCTAssertTrue(okResp.result.successful)
        let rate1 = try await node.getParameter("rate")
        XCTAssertEqual(rate1.value, .integer(60))
        let alpha1 = try await node.getParameter("alpha")
        XCTAssertEqual(alpha1.value, .double(0.9))

        // Second call: second parameter is out-of-range → both rolled back.
        let failResp = try await cli.call(
            SetParametersAtomicallyRequest(parameters: [
                Parameter(name: "alpha", value: goodDouble),
                Parameter(name: "rate", value: badInt),
            ]),
            timeout: .seconds(1))
        XCTAssertFalse(failResp.result.successful)

        // Net effect of failed call must be zero — values match the previous successful call.
        let rate2 = try await node.getParameter("rate")
        XCTAssertEqual(rate2.value, .integer(60))
        let alpha2 = try await node.getParameter("alpha")
        XCTAssertEqual(alpha2.value, .double(0.9))
    }
}
