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
    private(set) var nodesDestroyed: [(name: String, namespace: String)] = []
    private(set) var publishersCreated: [(topic: String, typeName: String)] = []
    private(set) var publishedPayloads: [Data] = []

    var createPublisherShouldThrow: TransportError?

    func createContext(domainId: Int32) throws {
        sync {
            contextCreated = true
            lastDomainId = domainId
        }
    }
    func destroyContext() { sync { contextDestroyed = true } }

    func createNode(name: String, namespace: String) throws -> any RclNodeHandle {
        sync { nodesCreated.append((name, namespace)) }
        return MockRclNode(name: name, namespace: namespace)
    }
    func destroyNode(_ node: any RclNodeHandle) {
        guard let n = node as? MockRclNode else { return }
        sync { nodesDestroyed.append((n.name, n.namespace)) }
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
}
