import Foundation

@testable import SwiftROS2Transport

final class MockRclNode: RclNodeHandle, @unchecked Sendable {
    let name: String
    let namespace: String
    init(name: String, namespace: String) {
        self.name = name
        self.namespace = namespace
    }
}

final class MockRclPublisher: RclPublisherHandle, @unchecked Sendable {
    let topic: String
    let typeName: String
    private let lock = NSLock()
    private var closed = false
    init(topic: String, typeName: String) {
        self.topic = topic
        self.typeName = typeName
    }
    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
    }
    func close() {
        lock.lock()
        defer { lock.unlock() }
        closed = true
    }
}

final class MockRclSubscription: RclSubscriptionHandle, @unchecked Sendable {
    let node: any RclNodeHandle
    let topic: String
    let typeName: String
    let qos: TransportQoS
    private let handler: @Sendable (Data, UInt64) -> Void
    private let lock = NSLock()
    private var destroyed = false

    init(
        node: any RclNodeHandle, topic: String, typeName: String, qos: TransportQoS,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) {
        self.node = node
        self.topic = topic
        self.typeName = typeName
        self.qos = qos
        self.handler = handler
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !destroyed
    }

    func markDestroyed() {
        lock.lock()
        defer { lock.unlock() }
        destroyed = true
    }

    /// Test hook: simulate the wait thread delivering one taken message.
    func fire(_ data: Data, timestamp: UInt64) {
        handler(data, timestamp)
    }
}

final class MockRclClient: RclClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private func sync<T>(_ b: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return b()
    }

    var isAvailable = true

    private(set) var contextCreated = false
    private(set) var contextDestroyed = false
    private(set) var lastDomainId: Int32 = -1
    private(set) var nodesCreated: [(name: String, namespace: String)] = []
    /// Handles returned by createNode, in creation order — lets tests assert
    /// entity-to-node attachment by identity.
    private(set) var nodeHandles: [MockRclNode] = []
    private(set) var nodesDestroyed: [(name: String, namespace: String)] = []
    private(set) var publishersCreated: [(topic: String, typeName: String)] = []
    private(set) var publishedPayloads: [Data] = []
    private(set) var subscriptionsCreated: [MockRclSubscription] = []
    private(set) var subscriptionsDestroyed: [(topic: String, typeName: String)] = []
    /// Teardown order log: "subscription:<topic>" / "node:<name>" / "context".
    private(set) var teardownEvents: [String] = []

    var createPublisherShouldThrow: TransportError?
    var createSubscriptionShouldThrow: TransportError?
    /// Test hook: runs inside createSubscription before the handle is
    /// returned — lets tests interleave a session close() into the
    /// preflight-create-append window.
    var onCreateSubscription: (() -> Void)?

    func createContext(domainId: Int32) throws {
        sync {
            contextCreated = true
            lastDomainId = domainId
        }
    }
    func destroyContext() {
        sync {
            contextDestroyed = true
            teardownEvents.append("context")
        }
    }

    func createNode(name: String, namespace: String) throws -> any RclNodeHandle {
        let node = MockRclNode(name: name, namespace: namespace)
        sync {
            nodesCreated.append((name, namespace))
            nodeHandles.append(node)
        }
        return node
    }
    func destroyNode(_ node: any RclNodeHandle) {
        guard let n = node as? MockRclNode else { return }
        sync {
            nodesDestroyed.append((n.name, n.namespace))
            teardownEvents.append("node:\(n.name)")
        }
    }

    func createPublisher(
        node: any RclNodeHandle, typeName: String, topic: String, qos: TransportQoS
    ) throws -> any RclPublisherHandle {
        if let e = createPublisherShouldThrow { throw e }
        sync { publishersCreated.append((topic, typeName)) }
        return MockRclPublisher(topic: topic, typeName: typeName)
    }

    func publishSerialized(_ publisher: any RclPublisherHandle, data: Data) throws {
        sync { publishedPayloads.append(data) }
    }

    func createSubscription(
        node: any RclNodeHandle,
        typeName: String,
        topic: String,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) throws -> any RclSubscriptionHandle {
        if let e = createSubscriptionShouldThrow { throw e }
        onCreateSubscription?()
        let sub = MockRclSubscription(
            node: node, topic: topic, typeName: typeName, qos: qos, handler: handler)
        sync { subscriptionsCreated.append(sub) }
        return sub
    }

    func destroySubscription(_ subscription: any RclSubscriptionHandle) {
        guard let s = subscription as? MockRclSubscription else { return }
        s.markDestroyed()
        sync {
            subscriptionsDestroyed.append((s.topic, s.typeName))
            teardownEvents.append("subscription:\(s.topic)")
        }
    }
}
