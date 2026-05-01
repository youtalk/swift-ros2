import Foundation

import SwiftROS2Transport

/// In-memory TransportSession used by SwiftROS2 umbrella unit tests.
///
/// Records publisher/subscriber creations and forwards published payloads
/// through the matching subscriber's handler so tests can drive end-to-end
/// flow without any real transport.
final class MockTransportSession: TransportSession, @unchecked Sendable {
    private let lock = NSLock()

    var transportType: TransportType { .zenoh }
    var isConnected: Bool = true
    var sessionId: String = "mock-umbrella-session"

    var openShouldThrow: TransportError?
    var createPublisherShouldThrow: TransportError?
    var createSubscriberShouldThrow: TransportError?

    private(set) var openedConfigs: [TransportConfig] = []
    private(set) var publishers: [MockTransportPublisher] = []
    private(set) var subscribers: [MockTransportSubscriber] = []
    private(set) var closedCount = 0

    func open(config: TransportConfig) async throws {
        if let e = openShouldThrow { throw e }
        lock.lock()
        defer { lock.unlock() }
        openedConfigs.append(config)
        isConnected = true
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        closedCount += 1
        isConnected = false
    }

    func checkHealth() -> Bool { isConnected }

    func createPublisher(
        topic: String, typeName: String, typeHash: String?, qos: TransportQoS
    ) throws -> any TransportPublisher {
        if let e = createPublisherShouldThrow { throw e }
        let pub = MockTransportPublisher(topic: topic, typeName: typeName, typeHash: typeHash, qos: qos)
        lock.lock()
        defer { lock.unlock() }
        publishers.append(pub)
        // Wire publisher → matching subscribers so publish() forwards through.
        pub.deliveryFanout = { [weak self] data, ts in
            guard let self = self else { return }
            let matches: [MockTransportSubscriber] = {
                self.lock.lock()
                defer { self.lock.unlock() }
                return self.subscribers.filter { $0.topic == topic }
            }()
            for sub in matches {
                sub.handler(data, ts)
            }
        }
        return pub
    }

    func createSubscriber(
        topic: String, typeName: String, typeHash: String?, qos: TransportQoS,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) throws -> any TransportSubscriber {
        if let e = createSubscriberShouldThrow { throw e }
        let sub = MockTransportSubscriber(
            topic: topic,
            typeName: typeName,
            typeHash: typeHash,
            qos: qos,
            handler: handler
        )
        lock.lock()
        defer { lock.unlock() }
        subscribers.append(sub)
        return sub
    }
}

final class MockTransportPublisher: TransportPublisher, @unchecked Sendable {
    let topic: String
    let typeName: String
    let typeHash: String?
    let qos: TransportQoS

    private let lock = NSLock()
    private var closed = false
    private(set) var publishedPayloads: [(data: Data, timestamp: UInt64, sequenceNumber: Int64)] = []
    var deliveryFanout: ((Data, UInt64) -> Void)?

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
    }

    init(topic: String, typeName: String, typeHash: String?, qos: TransportQoS) {
        self.topic = topic
        self.typeName = typeName
        self.typeHash = typeHash
        self.qos = qos
    }

    func publish(data: Data, timestamp: UInt64, sequenceNumber: Int64) throws {
        lock.lock()
        guard !closed else {
            lock.unlock()
            throw TransportError.publisherClosed
        }
        publishedPayloads.append((data, timestamp, sequenceNumber))
        let fanout = deliveryFanout
        lock.unlock()
        fanout?(data, timestamp)
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        closed = true
    }
}

final class MockTransportSubscriber: TransportSubscriber, @unchecked Sendable {
    let topic: String
    let typeName: String
    let typeHash: String?
    let qos: TransportQoS
    let handler: @Sendable (Data, UInt64) -> Void

    private let lock = NSLock()
    private var closed = false

    init(
        topic: String, typeName: String, typeHash: String?, qos: TransportQoS,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) {
        self.topic = topic
        self.typeName = typeName
        self.typeHash = typeHash
        self.qos = qos
        self.handler = handler
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        closed = true
    }
}
