import Foundation
import SwiftROS2Messages
import SwiftROS2Transport
import XCTest

@testable import SwiftROS2

final class ROS2ParameterClientTests: XCTestCase {
    private func makeContext() async throws -> (ROS2Context, MockTransportSession) {
        let session = MockTransportSession()
        session.installEchoServiceTransport()
        let ctx = try await ROS2Context(
            transport: .zenoh(locator: "tcp/127.0.0.1:7447"),
            distro: .jazzy,
            session: session
        )
        return (ctx, session)
    }

    /// Spin up one node that serves parameters and a second node that hosts
    /// the client. Both share one MockTransportSession so the in-process
    /// echo transport sees both sides.
    private func makeServerAndClient(
        params: [(String, ROS2ParameterValue)] = []
    ) async throws -> (ROS2Context, ROS2Node, ROS2Node, ROS2ParameterClient) {
        let (ctx, _) = try await makeContext()
        let server = try await ctx.createNode(name: "server", namespace: "/test")
        for (name, value) in params {
            switch value {
            case .integer(let v): _ = try await server.declareParameter(name, default: v)
            case .double(let v): _ = try await server.declareParameter(name, default: v)
            case .string(let v): _ = try await server.declareParameter(name, default: v)
            case .bool(let v): _ = try await server.declareParameter(name, default: v)
            default:
                XCTFail("test helper does not declare \(value)")
                throw XCTestError(.failureWhileWaiting)
            }
        }
        let client = try await ctx.createNode(
            name: "client", namespace: "/test",
            options: ROS2NodeOptions(startParameterServices: false)
        )
        let pc = try await client.createParameterClient(
            remoteNode: server.fullyQualifiedName)
        return (ctx, server, client, pc)
    }

    func testInitCreatesAllSixUnderlyingClients() async throws {
        let (ctx, server, client, pc) = try await makeServerAndClient()
        defer {
            Task {
                await pc.close()
                await client.destroy()
                await server.destroy()
                await ctx.shutdown()
            }
        }
        XCTAssertEqual(pc.remoteNodeName, "/test/server")
    }

    func testCloseIsIdempotent() async throws {
        let (ctx, server, client, pc) = try await makeServerAndClient()
        defer {
            Task {
                await client.destroy()
                await server.destroy()
                await ctx.shutdown()
            }
        }
        await pc.close()
        await pc.close()  // must not crash
    }

    func testGetParameters() async throws {
        let (ctx, server, client, pc) = try await makeServerAndClient(
            params: [("rate", .integer(30)), ("greeting", .string("hi"))])
        defer {
            Task {
                await pc.close()
                await client.destroy()
                await server.destroy()
                await ctx.shutdown()
            }
        }
        let values = try await pc.getParameters(["rate", "greeting", "missing"])
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], .integer(30))
        XCTAssertEqual(values[1], .string("hi"))
        XCTAssertEqual(values[2], .notSet)
    }
}
