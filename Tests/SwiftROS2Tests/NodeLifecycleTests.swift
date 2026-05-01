import SwiftROS2
import SwiftROS2Messages
import SwiftROS2Transport
import XCTest

final class NodeLifecycleTests: XCTestCase {
    private func makeContext(
        session: MockTransportSession = MockTransportSession()
    ) async throws -> (ROS2Context, MockTransportSession) {
        let config = TransportConfig.zenoh(locator: "tcp/mock:7447")
        let ctx = try await ROS2Context(transport: config, session: session)
        return (ctx, session)
    }

    // MARK: - Node creation

    func testContextWithInjectedSessionSkipsFactory() async throws {
        let (ctx, session) = try await makeContext()
        XCTAssertTrue(ctx.isConnected)
        // The mock starts as already-connected, so open() should not be called.
        XCTAssertEqual(session.openedConfigs.count, 0)
    }

    func testContextOpensSessionWhenNotConnected() async throws {
        let session = MockTransportSession()
        session.isConnected = false
        _ = try await ROS2Context(transport: .zenoh(locator: "tcp/m:7447"), session: session)
        XCTAssertEqual(session.openedConfigs.count, 1)
    }

    func testCreateNodeReturnsNodeWithFullyQualifiedName() async throws {
        let (ctx, _) = try await makeContext()
        let node = try await ctx.createNode(name: "imu_node", namespace: "/ios")
        XCTAssertEqual(node.name, "imu_node")
        XCTAssertEqual(node.namespace, "/ios")
        XCTAssertEqual(node.fullyQualifiedName, "/ios/imu_node")
    }

    func testCreateNodeWithRootNamespaceUsesSlashJoin() async throws {
        let (ctx, _) = try await makeContext()
        let node = try await ctx.createNode(name: "n", namespace: "/")
        XCTAssertEqual(node.fullyQualifiedName, "/n")
    }

    // MARK: - Publisher

    func testCreatePublisherForwardsToSession() async throws {
        let (ctx, session) = try await makeContext()
        let node = try await ctx.createNode(name: "n", namespace: "/ns")
        _ = try await node.createPublisher(StringMsg.self, topic: "chatter")

        XCTAssertEqual(session.publishers.count, 1)
        let recorded = session.publishers[0]
        XCTAssertEqual(recorded.topic, "/ns/chatter", "Topic must be namespace-prefixed")
        XCTAssertEqual(recorded.typeName, StringMsg.typeInfo.typeName)
    }

    func testPublishMessageEncodesAndDelegates() async throws {
        let (ctx, session) = try await makeContext()
        let node = try await ctx.createNode(name: "n", namespace: "/ns")
        let pub = try await node.createPublisher(StringMsg.self, topic: "chatter")
        try pub.publish(StringMsg(data: "hello"))

        let recorded = session.publishers[0]
        XCTAssertEqual(recorded.publishedPayloads.count, 1)
        let payload = recorded.publishedPayloads[0]
        XCTAssertGreaterThanOrEqual(payload.data.count, 4, "CDR encapsulation header must be present")
        XCTAssertEqual(payload.sequenceNumber, 0)
    }

    func testPublishIncrementsSequenceNumber() async throws {
        let (ctx, session) = try await makeContext()
        let node = try await ctx.createNode(name: "n", namespace: "/ns")
        let pub = try await node.createPublisher(StringMsg.self, topic: "chatter")
        try pub.publish(StringMsg(data: "a"))
        try pub.publish(StringMsg(data: "b"))
        try pub.publish(StringMsg(data: "c"))

        let seqs = session.publishers[0].publishedPayloads.map { $0.sequenceNumber }
        XCTAssertEqual(seqs, [0, 1, 2])
    }

    func testPublisherUsesAbsoluteTopicWhenLeadingSlash() async throws {
        let (ctx, session) = try await makeContext()
        let node = try await ctx.createNode(name: "n", namespace: "/ns")
        _ = try await node.createPublisher(StringMsg.self, topic: "/abs/topic")
        XCTAssertEqual(session.publishers[0].topic, "/abs/topic")
    }

    // MARK: - Subscription

    func testSubscriptionForwardsToSession() async throws {
        let (ctx, session) = try await makeContext()
        let node = try await ctx.createNode(name: "n", namespace: "/ns")
        _ = try await node.createSubscription(StringMsg.self, topic: "chatter")
        XCTAssertEqual(session.subscribers.count, 1)
        XCTAssertEqual(session.subscribers[0].topic, "/ns/chatter")
    }

    func testPublishedMessageIsDeliveredToMatchingSubscription() async throws {
        let (ctx, _) = try await makeContext()
        let node = try await ctx.createNode(name: "n", namespace: "/ns")
        let sub = try await node.createSubscription(StringMsg.self, topic: "chatter")
        let pub = try await node.createPublisher(StringMsg.self, topic: "chatter")

        try pub.publish(StringMsg(data: "hello world"))

        let task = Task { () -> StringMsg? in
            for await msg in sub.messages {
                return msg
            }
            return nil
        }
        // Give the AsyncStream a moment.
        try await Task.sleep(nanoseconds: 50_000_000)
        sub.cancel()
        let received = await task.value
        XCTAssertEqual(received?.data, "hello world")
    }

    // MARK: - QoS propagation

    func testQoSProfileFlowsThroughToTransport() async throws {
        let (ctx, session) = try await makeContext()
        let node = try await ctx.createNode(name: "n", namespace: "/ns")
        _ = try await node.createPublisher(
            StringMsg.self,
            topic: "chatter",
            qos: QoSProfile(reliability: .reliable, durability: .transientLocal, history: .keepLast(7))
        )

        let qos = session.publishers[0].qos
        XCTAssertEqual(qos.reliability, .reliable)
        XCTAssertEqual(qos.durability, .transientLocal)
        if case .keepLast(let n) = qos.history {
            XCTAssertEqual(n, 7)
        } else {
            XCTFail("Expected keepLast(7)")
        }
    }

    // MARK: - Shutdown

    func testShutdownClosesSession() async throws {
        let (ctx, session) = try await makeContext()
        await ctx.shutdown()
        XCTAssertEqual(session.closedCount, 1)
    }

    func testShutdownClosesAllPublishers() async throws {
        let (ctx, session) = try await makeContext()
        let node = try await ctx.createNode(name: "n", namespace: "/ns")
        _ = try await node.createPublisher(StringMsg.self, topic: "a")
        _ = try await node.createPublisher(StringMsg.self, topic: "b")

        await ctx.shutdown()
        for pub in session.publishers {
            XCTAssertFalse(pub.isActive)
        }
    }
}
