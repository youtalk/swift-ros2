import Foundation
import SwiftROS2Transport

/// In-memory TransportSession used by SwiftROS2 umbrella unit tests.
///
/// Records publisher/subscriber creations and forwards published payloads
/// through the matching subscriber's handler so tests can drive end-to-end
/// flow without any real transport.
///
/// All mutable state is private and read/written only inside `synchronized`.
/// Public accessors (including the `*ShouldThrow` knobs and `isConnected`
/// setter that tests reach for directly) take the lock so the type's
/// `@unchecked Sendable` conformance is honest under `swift test --parallel`.
final class MockTransportSession: TransportSession, @unchecked Sendable {
    private let lock = NSLock()

    private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    var transportType: TransportType { .zenoh }

    // MARK: - Mutable state (private + lock-guarded)

    private var _isConnected = true
    private var _sessionIdValue = "mock-umbrella-session"
    private var _openShouldThrow: TransportError?
    private var _createPublisherShouldThrow: TransportError?
    private var _createSubscriberShouldThrow: TransportError?
    private var _openedConfigs: [TransportConfig] = []
    private var _publishers: [MockTransportPublisher] = []
    private var _subscribers: [MockTransportSubscriber] = []
    private var _closedCount = 0

    // MARK: - Public accessors (synchronized)

    var isConnected: Bool {
        get { synchronized { _isConnected } }
        set { synchronized { _isConnected = newValue } }
    }

    var sessionId: String {
        get { synchronized { _sessionIdValue } }
        set { synchronized { _sessionIdValue = newValue } }
    }

    var openShouldThrow: TransportError? {
        get { synchronized { _openShouldThrow } }
        set { synchronized { _openShouldThrow = newValue } }
    }

    var createPublisherShouldThrow: TransportError? {
        get { synchronized { _createPublisherShouldThrow } }
        set { synchronized { _createPublisherShouldThrow = newValue } }
    }

    var createSubscriberShouldThrow: TransportError? {
        get { synchronized { _createSubscriberShouldThrow } }
        set { synchronized { _createSubscriberShouldThrow = newValue } }
    }

    var openedConfigs: [TransportConfig] { synchronized { _openedConfigs } }
    var publishers: [MockTransportPublisher] { synchronized { _publishers } }
    var subscribers: [MockTransportSubscriber] { synchronized { _subscribers } }
    var closedCount: Int { synchronized { _closedCount } }

    // MARK: - TransportSession

    func open(config: TransportConfig) async throws {
        if let e = synchronized({ _openShouldThrow }) { throw e }
        // Mirror real Zenoh / DDS sessions: reject configs whose transport type
        // doesn't match this session and run the same validate() check.
        guard config.type == transportType else {
            throw TransportError.invalidConfiguration(
                "Expected \(transportType) configuration, got \(config.type)"
            )
        }
        try config.validate()
        synchronized {
            _openedConfigs.append(config)
            _isConnected = true
        }
    }

    func close() throws {
        let (publishersToClose, subscribersToClose): ([MockTransportPublisher], [MockTransportSubscriber]) =
            synchronized {
                _closedCount += 1
                _isConnected = false
                return (_publishers, _subscribers)
            }
        for publisher in publishersToClose {
            try publisher.close()
        }
        for subscriber in subscribersToClose {
            try subscriber.close()
        }
    }

    func checkHealth() -> Bool { synchronized { _isConnected } }

    func createPublisher(
        topic: String, typeName: String, typeHash: String?, qos: TransportQoS
    ) throws -> any TransportPublisher {
        // Snapshot the throw-knob and connection state in a single critical section
        // so a concurrent flip can't slip between checks.
        let connected: Bool = try synchronized {
            if let e = _createPublisherShouldThrow { throw e }
            return _isConnected
        }
        // Mirror real Zenoh / DDS sessions: refuse on a closed session and
        // reject empty topic / type names.
        guard connected else {
            throw TransportError.notConnected
        }
        guard !topic.isEmpty else {
            throw TransportError.invalidConfiguration("Topic name cannot be empty")
        }
        guard !typeName.isEmpty else {
            throw TransportError.invalidConfiguration("Type name cannot be empty")
        }
        let pub = MockTransportPublisher(topic: topic, typeName: typeName, typeHash: typeHash, qos: qos)
        synchronized { _publishers.append(pub) }
        // Wire publisher → matching subscribers so publish() forwards through.
        // Match on topic + typeName + typeHash, and skip subscribers that
        // have already been closed/cancelled.
        pub.deliveryFanout = { [weak self] data, ts in
            guard let self = self else { return }
            let matches: [MockTransportSubscriber] = self.synchronized {
                self._subscribers.filter { sub in
                    sub.isActive && sub.topic == topic && sub.typeName == typeName && sub.typeHash == typeHash
                }
            }
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
        let connected: Bool = try synchronized {
            if let e = _createSubscriberShouldThrow { throw e }
            return _isConnected
        }
        guard connected else {
            throw TransportError.notConnected
        }
        guard !topic.isEmpty else {
            throw TransportError.invalidConfiguration("Topic name cannot be empty")
        }
        guard !typeName.isEmpty else {
            throw TransportError.invalidConfiguration("Type name cannot be empty")
        }
        let sub = MockTransportSubscriber(
            topic: topic,
            typeName: typeName,
            typeHash: typeHash,
            qos: qos,
            handler: handler
        )
        synchronized { _subscribers.append(sub) }
        return sub
    }

    func createServiceServer(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data) async throws -> Data
    ) throws -> any TransportService {
        throw TransportError.unsupportedFeature("MockTransportSession service server (override per test)")
    }

    func createServiceClient(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS
    ) throws -> any TransportClient {
        throw TransportError.unsupportedFeature("MockTransportSession service client (override per test)")
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
