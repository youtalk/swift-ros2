import XCTest

@testable import SwiftROS2
@testable import SwiftROS2Transport

final class MatchedSubscriptionsTests: XCTestCase {
    private func makePublisher() async throws -> (ROS2Node, ROS2Publisher<StringMsg>, MockTransportPublisher) {
        let session = MockTransportSession()
        let ctx = try await ROS2Context(transport: .zenoh(locator: "tcp/m:7447"), session: session)
        let node = try await ctx.createNode(
            name: "matched", namespace: "/t", options: ROS2NodeOptions(startParameterServices: false))
        let pub = try await node.createPublisher(StringMsg.self, topic: "probe")
        let transport = try XCTUnwrap(session.publishers.last)
        return (node, pub, transport)
    }

    func testUnknownTransportStateIsReportedAsMatched() async throws {
        let (_, pub, transport) = try await makePublisher()
        transport.matched = nil
        XCTAssertTrue(pub.hasMatchedSubscriptions)
    }

    func testReflectsTheTransportState() async throws {
        let (_, pub, transport) = try await makePublisher()
        transport.matched = false
        XCTAssertFalse(pub.hasMatchedSubscriptions)
        transport.matched = true
        XCTAssertTrue(pub.hasMatchedSubscriptions)
    }

    func testHandlerGetsTheCurrentStateBeforeRegistrationReturns() async throws {
        let (_, pub, transport) = try await makePublisher()
        transport.matched = false
        let box = ValuesBox()
        pub.onMatchedSubscriptionsChanged { box.append($0) }
        XCTAssertEqual(box.values, [false])
    }

    func testHandlerFiresOnEveryChangeAndNotOtherwise() async throws {
        let (_, pub, transport) = try await makePublisher()
        transport.matched = false
        let box = ValuesBox()
        pub.onMatchedSubscriptionsChanged { box.append($0) }
        transport.matched = true
        try await waitUntil { box.values == [false, true] }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(box.values, [false, true], "an unchanged state must not fire again")
        transport.matched = false
        try await waitUntil { box.values == [false, true, false] }
    }

    func testHandlerIsNotCalledAfterTheNodeIsDestroyed() async throws {
        let (node, pub, transport) = try await makePublisher()
        transport.matched = false
        let box = ValuesBox()
        pub.onMatchedSubscriptionsChanged { box.append($0) }
        await node.destroy()
        transport.matched = true
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(box.values, [false])
    }

    func testMonitorPollReportsOnlyChanges() {
        let state = ValuesBox()
        state.append(false)
        let monitor = MatchedSubscriptionsMonitor(interval: .seconds(3600)) { state.values.last ?? true }
        let seen = ValuesBox()
        monitor.start { seen.append($0) }
        monitor.poll()
        state.append(true)
        monitor.poll()
        monitor.poll()
        monitor.stop()
        state.append(false)
        monitor.poll()
        XCTAssertEqual(seen.values, [false, true])
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition not met within \(timeout) s")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private final class ValuesBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Bool] = []
    var values: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }

    func append(_ v: Bool) {
        lock.lock()
        _values.append(v)
        lock.unlock()
    }
}
