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

final class MockRclService: RclServiceHandle, @unchecked Sendable {
    let node: any RclNodeHandle
    let serviceName: String
    let srvTypeName: String
    let qos: TransportQoS
    private let onRequest: @Sendable (Data, [UInt8]) -> Void
    private let lock = NSLock()
    private var destroyed = false
    /// Responses recorded by MockRclClient.sendResponse, in send order.
    private(set) var responsesSent: [(requestId: [UInt8], data: Data)] = []

    init(
        node: any RclNodeHandle, serviceName: String, srvTypeName: String, qos: TransportQoS,
        onRequest: @escaping @Sendable (Data, [UInt8]) -> Void
    ) {
        self.node = node
        self.serviceName = serviceName
        self.srvTypeName = srvTypeName
        self.qos = qos
        self.onRequest = onRequest
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

    func recordResponse(requestId: [UInt8], data: Data) {
        lock.lock()
        defer { lock.unlock() }
        responsesSent.append((requestId, data))
    }

    /// Test hook: simulate the wait thread delivering one taken request.
    func fire(_ data: Data, requestId: [UInt8]) {
        onRequest(data, requestId)
    }
}

final class MockRclServiceClient: RclClientHandle, @unchecked Sendable {
    let node: any RclNodeHandle
    let serviceName: String
    let srvTypeName: String
    let qos: TransportQoS
    private let onResponse: @Sendable (Int64, Data) -> Void
    private let lock = NSLock()
    private var destroyed = false
    private var nextSeq: Int64 = 0
    /// Requests recorded by MockRclClient.sendRequest, in send order; the
    /// element index + 1 is the sequence number that was returned.
    private(set) var sentRequests: [Data] = []

    init(
        node: any RclNodeHandle, serviceName: String, srvTypeName: String, qos: TransportQoS,
        onResponse: @escaping @Sendable (Int64, Data) -> Void
    ) {
        self.node = node
        self.serviceName = serviceName
        self.srvTypeName = srvTypeName
        self.qos = qos
        self.onResponse = onResponse
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

    func recordRequest(_ data: Data) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        nextSeq += 1
        sentRequests.append(data)
        return nextSeq
    }

    /// Test hook: simulate the wait thread delivering one taken response.
    func fire(sequenceNumber: Int64, data: Data) {
        onResponse(sequenceNumber, data)
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
    private(set) var servicesCreated: [MockRclService] = []
    private(set) var servicesDestroyed: [(serviceName: String, srvTypeName: String)] = []
    private(set) var serviceClientsCreated: [MockRclServiceClient] = []
    private(set) var serviceClientsDestroyed: [(serviceName: String, srvTypeName: String)] = []
    /// Teardown order log: "subscription:<topic>" / "service:<name>" /
    /// "client:<name>" / "node:<name>" / "context".
    private(set) var teardownEvents: [String] = []

    var createPublisherShouldThrow: TransportError?
    var createSubscriptionShouldThrow: TransportError?
    var createServiceServerShouldThrow: TransportError?
    var createServiceClientShouldThrow: TransportError?
    var sendResponseShouldThrow: TransportError?
    var sendRequestShouldThrow: TransportError?
    var serverAvailableValue = true
    /// Test hook: runs inside createSubscription before the handle is
    /// returned — lets tests interleave a session close() into the
    /// preflight-create-append window.
    var onCreateSubscription: (() -> Void)?
    /// Same close-race hooks for the service entities.
    var onCreateServiceServer: (() -> Void)?
    var onCreateServiceClient: (() -> Void)?
    /// Test hook: fires after a response is recorded (lets tests await the
    /// async handler-to-sendResponse round trip deterministically).
    var onSendResponse: ((Data) -> Void)?
    /// Test hook: fires after a request is recorded, with its sequence number.
    var onSendRequest: ((Int64, Data) -> Void)?

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

    func createServiceServer(
        node: any RclNodeHandle,
        srvTypeName: String,
        serviceName: String,
        qos: TransportQoS,
        onRequest: @escaping @Sendable (Data, [UInt8]) -> Void
    ) throws -> any RclServiceHandle {
        if let e = createServiceServerShouldThrow { throw e }
        onCreateServiceServer?()
        let service = MockRclService(
            node: node, serviceName: serviceName, srvTypeName: srvTypeName, qos: qos,
            onRequest: onRequest)
        sync { servicesCreated.append(service) }
        return service
    }

    func sendResponse(_ service: any RclServiceHandle, requestId: [UInt8], data: Data) throws {
        if let e = sendResponseShouldThrow { throw e }
        guard let s = service as? MockRclService else { return }
        guard s.isActive else { throw TransportError.sessionClosed }
        s.recordResponse(requestId: requestId, data: data)
        onSendResponse?(data)
    }

    func destroyServiceServer(_ service: any RclServiceHandle) {
        guard let s = service as? MockRclService else { return }
        s.markDestroyed()
        sync {
            servicesDestroyed.append((s.serviceName, s.srvTypeName))
            teardownEvents.append("service:\(s.serviceName)")
        }
    }

    func createServiceClient(
        node: any RclNodeHandle,
        srvTypeName: String,
        serviceName: String,
        qos: TransportQoS,
        onResponse: @escaping @Sendable (Int64, Data) -> Void
    ) throws -> any RclClientHandle {
        if let e = createServiceClientShouldThrow { throw e }
        onCreateServiceClient?()
        let serviceClient = MockRclServiceClient(
            node: node, serviceName: serviceName, srvTypeName: srvTypeName, qos: qos,
            onResponse: onResponse)
        sync { serviceClientsCreated.append(serviceClient) }
        return serviceClient
    }

    func sendRequest(_ client: any RclClientHandle, data: Data) throws -> Int64 {
        if let e = sendRequestShouldThrow { throw e }
        guard let c = client as? MockRclServiceClient else {
            throw TransportError.publishFailed("invalid service client handle")
        }
        guard c.isActive else { throw TransportError.sessionClosed }
        let seq = c.recordRequest(data)
        onSendRequest?(seq, data)
        return seq
    }

    func serverAvailable(_ client: any RclClientHandle) -> Bool {
        guard let c = client as? MockRclServiceClient, c.isActive else { return false }
        return serverAvailableValue
    }

    func destroyServiceClient(_ client: any RclClientHandle) {
        guard let c = client as? MockRclServiceClient else { return }
        c.markDestroyed()
        sync {
            serviceClientsDestroyed.append((c.serviceName, c.srvTypeName))
            teardownEvents.append("client:\(c.serviceName)")
        }
    }
}
