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

    func testInitWiresRemoteNameAndAllSixServiceClients() async throws {
        // The init contract has two halves: the public `remoteNodeName` is
        // recorded, and one underlying ROS2Client is created per service so
        // every public method has somewhere to dispatch. Exercise both.
        let (ctx, server, client, pc) = try await makeServerAndClient(
            params: [("rate", .integer(30))])
        defer {
            Task {
                await pc.close()
                await client.destroy()
                await server.destroy()
                await ctx.shutdown()
            }
        }
        XCTAssertEqual(pc.remoteNodeName, "/test/server")
        XCTAssertEqual(pc.defaultTimeout, .seconds(5))

        // One round-trip per service confirms each underlying client was
        // created against the right service name and connects to a handler.
        _ = try await pc.getParameters(["rate"])
        _ = try await pc.setParameters([
            ROS2Parameter(name: "rate", value: .integer(31))
        ])
        _ = try await pc.setParametersAtomically([
            ROS2Parameter(name: "rate", value: .integer(32))
        ])
        _ = try await pc.listParameters()
        _ = try await pc.describeParameters(["rate"])
        _ = try await pc.getParameterTypes(["rate"])
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

    func testSetParameters() async throws {
        let (ctx, server, client, pc) = try await makeServerAndClient(
            params: [("rate", .integer(30))])
        defer {
            Task {
                await pc.close()
                await client.destroy()
                await server.destroy()
                await ctx.shutdown()
            }
        }
        let results = try await pc.setParameters([
            ROS2Parameter(name: "rate", value: .integer(99)),
            ROS2Parameter(name: "missing", value: .integer(1)),
        ])
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].successful)
        XCTAssertFalse(results[1].successful)
        let stored = try await server.getParameter("rate")
        XCTAssertEqual(stored.value, .integer(99))
    }

    func testSetParametersAtomicallyBatchSuccess() async throws {
        let (ctx, server, client, pc) = try await makeServerAndClient(
            params: [("a", .integer(1)), ("b", .integer(2))])
        defer {
            Task {
                await pc.close()
                await client.destroy()
                await server.destroy()
                await ctx.shutdown()
            }
        }
        let r = try await pc.setParametersAtomically([
            ROS2Parameter(name: "a", value: .integer(10)),
            ROS2Parameter(name: "b", value: .integer(20)),
        ])
        XCTAssertTrue(r.successful)
        let a = try await server.getParameter("a")
        let b = try await server.getParameter("b")
        XCTAssertEqual(a.value, .integer(10))
        XCTAssertEqual(b.value, .integer(20))
    }

    func testSetParametersAtomicallyRollsBackOnFailure() async throws {
        let (ctx, server, client, pc) = try await makeServerAndClient(
            params: [("a", .integer(1))])
        defer {
            Task {
                await pc.close()
                await client.destroy()
                await server.destroy()
                await ctx.shutdown()
            }
        }
        let r = try await pc.setParametersAtomically([
            ROS2Parameter(name: "a", value: .integer(10)),
            ROS2Parameter(name: "missing", value: .integer(0)),
        ])
        XCTAssertFalse(r.successful)
        let a = try await server.getParameter("a")
        XCTAssertEqual(a.value, .integer(1))
    }

    func testListParameters() async throws {
        let (ctx, server, client, pc) = try await makeServerAndClient(
            params: [("a.x", .integer(1)), ("a.y", .integer(2)), ("b", .integer(3))])
        defer {
            Task {
                await pc.close()
                await client.destroy()
                await server.destroy()
                await ctx.shutdown()
            }
        }
        let r = try await pc.listParameters()
        XCTAssertEqual(Set(r.names), ["a.x", "a.y", "b"])
        XCTAssertEqual(Set(r.prefixes), ["a"])
    }

    func testDescribeParameters() async throws {
        let (ctx, server, client, pc) = try await makeServerAndClient()
        defer {
            Task {
                await pc.close()
                await client.destroy()
                await server.destroy()
                await ctx.shutdown()
            }
        }
        _ = try await server.declareParameter(
            "rate",
            default: Int64(30),
            descriptor: ROS2ParameterDescriptor(
                name: "rate", type: .integer,
                description: "tick rate",
                integerRange: 1...120))
        let descs = try await pc.describeParameters(["rate"])
        XCTAssertEqual(descs.count, 1)
        XCTAssertEqual(descs[0].name, "rate")
        XCTAssertEqual(descs[0].type, .integer)
        XCTAssertEqual(descs[0].description, "tick rate")
        XCTAssertEqual(descs[0].integerRange, 1...120)
    }

    func testGetParameterTypes() async throws {
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
        let types = try await pc.getParameterTypes(["rate", "greeting", "missing"])
        XCTAssertEqual(types, [.integer, .string, .notSet])
    }

    func testWaitForServiceSucceedsWhenAllSixAreUp() async throws {
        let (ctx, server, client, pc) = try await makeServerAndClient()
        defer {
            Task {
                await pc.close()
                await client.destroy()
                await server.destroy()
                await ctx.shutdown()
            }
        }
        try await pc.waitForService(timeout: .seconds(2))
    }
}
