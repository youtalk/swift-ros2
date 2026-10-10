import SwiftROS2
import SwiftROS2Messages
import SwiftROS2Transport
import XCTest

/// Wire Zenoh matched-subscription check through a real router. Requires
/// `ZENOH_ROUTER` (for example `tcp/192.168.1.85:7447`) pointing at an
/// `rmw_zenohd` or `zenohd`. Skips otherwise. Run it against each distro's
/// router: an old router that never reports interest leaves
/// `hasMatchedSubscriptions` false forever, which would silence lazy topics.
final class ZenohMatchingIntegrationTests: XCTestCase {
    func testMatchedSubscriptionsFollowsASubscriberThroughTheRouter() async throws {
        guard let router = ProcessInfo.processInfo.environment["ZENOH_ROUTER"], !router.isEmpty else {
            throw XCTSkip("Set ZENOH_ROUTER to run this test (for example tcp/192.168.1.85:7447)")
        }
        // Two contexts: zenoh-pico does not route a session's own puts to its own subscribers.
        let pubCtx = try await ROS2Context(
            transport: .zenoh(locator: router, domainId: 0, wireMode: .jazzy), distro: .jazzy)
        let subCtx = try await ROS2Context(
            transport: .zenoh(locator: router, domainId: 0, wireMode: .jazzy), distro: .jazzy)
        let pubNode = try await pubCtx.createNode(name: "matched_pub", namespace: "/matched")
        let subNode = try await subCtx.createNode(name: "matched_sub", namespace: "/matched")
        let pub = try await pubNode.createPublisher(StringMsg.self, topic: "probe")

        try await waitUntil { !pub.hasMatchedSubscriptions }
        let sub = try await subNode.createSubscription(StringMsg.self, topic: "probe")
        try await waitUntil { pub.hasMatchedSubscriptions }
        sub.cancel()
        try await waitUntil { !pub.hasMatchedSubscriptions }

        await subCtx.shutdown()
        await pubCtx.shutdown()
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition not met within \(timeout) s")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
