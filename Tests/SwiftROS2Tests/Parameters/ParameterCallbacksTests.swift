import SwiftROS2Transport
import XCTest

@testable import SwiftROS2

final class ParameterCallbacksTests: XCTestCase {
    private func declared(_ store: ParameterStore, _ name: String, _ value: ROS2ParameterValue) async throws {
        _ = try await store.declare(
            name: name, value: value,
            descriptor: ROS2ParameterDescriptor(name: name, type: value.parameterType))
    }

    private func makeContext() async throws -> ROS2Context {
        let config = TransportConfig.zenoh(locator: "tcp/mock:7447")
        let mock = MockTransportSession()
        mock.installEchoServiceTransport()
        return try await ROS2Context(transport: config, session: mock)
    }

    func testPreSetMutatesProposedList() async throws {
        let store = ParameterStore()
        try await declared(store, "rate", .integer(30))
        _ = await store.registerPreSet { ps in
            ps = ps.map {
                if $0.name == "rate", case .integer(let v) = $0.value {
                    return ROS2Parameter(name: "rate", value: .integer(v * 2))
                }
                return $0
            }
        }
        let r = await store.set(ROS2Parameter(name: "rate", value: .integer(20)))
        XCTAssertTrue(r.successful)
        let stored = try await store.get(name: "rate")
        XCTAssertEqual(stored.value, .integer(40))
    }

    func testOnSetVetoBlocksWrite() async throws {
        let store = ParameterStore()
        try await declared(store, "rate", .integer(30))
        _ = await store.registerOnSet { _ in .failure(reason: "vetoed") }
        let r = await store.set(ROS2Parameter(name: "rate", value: .integer(20)))
        XCTAssertFalse(r.successful)
        XCTAssertEqual(r.reason, "vetoed")
        let stored = try await store.get(name: "rate")
        XCTAssertEqual(stored.value, .integer(30))
    }

    func testPostSetSeesOnlySuccesses() async throws {
        let store = ParameterStore()
        try await declared(store, "a", .integer(1))
        try await declared(store, "b", .integer(2))
        actor Box {
            var seen: [ROS2Parameter] = []
            func add(_ ps: [ROS2Parameter]) { seen += ps }
        }
        let box = Box()
        _ = await store.registerPostSet { ps in Task { await box.add(ps) } }
        _ = await store.setMany([
            ROS2Parameter(name: "a", value: .integer(10)),
            ROS2Parameter(name: "missing", value: .integer(0)),
            ROS2Parameter(name: "b", value: .integer(20)),
        ])
        // Allow the detached Task posting into Box to drain.
        try await Task.sleep(nanoseconds: 20_000_000)
        let names = await box.seen.map { $0.name }
        XCTAssertEqual(names.sorted(), ["a", "b"])
    }

    func testSetAtomicallyVetoLeavesNothingChanged() async throws {
        let store = ParameterStore()
        try await declared(store, "a", .integer(1))
        try await declared(store, "b", .integer(2))
        _ = await store.registerOnSet { _ in .failure(reason: "no") }
        let r = await store.setAtomically([
            ROS2Parameter(name: "a", value: .integer(10)),
            ROS2Parameter(name: "b", value: .integer(20)),
        ])
        XCTAssertFalse(r.successful)
        let a = try await store.get(name: "a")
        let b = try await store.get(name: "b")
        XCTAssertEqual(a.value, .integer(1))
        XCTAssertEqual(b.value, .integer(2))
    }

    func testNodeOnSetCallbackVetoesViaSet() async throws {
        let ctx = try await makeContext()
        let node = try await ctx.createNode(name: "n1")
        defer {
            Task {
                await node.destroy()
                await ctx.shutdown()
            }
        }
        _ = try await node.declareParameter("rate", default: Int64(30))
        _ = await node.setOnSetParametersCallback { _ in
            ROS2SetParametersResult(successful: false, reason: "guarded")
        }
        let r = await node.setParameter(ROS2Parameter(name: "rate", value: .integer(99)))
        XCTAssertFalse(r.successful)
        XCTAssertEqual(r.reason, "guarded")
    }

    func testNodeRemoveParameterCallback() async throws {
        let ctx = try await makeContext()
        let node = try await ctx.createNode(name: "n2")
        defer {
            Task {
                await node.destroy()
                await ctx.shutdown()
            }
        }
        _ = try await node.declareParameter("rate", default: Int64(30))
        let h = await node.setOnSetParametersCallback { _ in
            ROS2SetParametersResult(successful: false, reason: "guarded")
        }
        let removed = await node.removeParameterCallback(h)
        XCTAssertTrue(removed)
        let r = await node.setParameter(ROS2Parameter(name: "rate", value: .integer(99)))
        XCTAssertTrue(r.successful)
    }

    func testRemovedCallbackStopsFiring() async throws {
        let store = ParameterStore()
        try await declared(store, "a", .integer(1))
        actor Counter {
            var n = 0
            func inc() { n += 1 }
        }
        let c = Counter()
        let h = await store.registerPostSet { _ in Task { await c.inc() } }
        _ = await store.set(ROS2Parameter(name: "a", value: .integer(2)))
        try await Task.sleep(nanoseconds: 20_000_000)
        let firstN = await c.n
        XCTAssertEqual(firstN, 1)
        let removed = await store.unregisterCallback(h)
        XCTAssertTrue(removed)
        _ = await store.set(ROS2Parameter(name: "a", value: .integer(3)))
        try await Task.sleep(nanoseconds: 20_000_000)
        let secondN = await c.n
        XCTAssertEqual(secondN, 1)
    }
}
