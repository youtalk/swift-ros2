// DDSTransportSession.swift
// TransportSession implementation using DDSClientProtocol
//
// Ported from Conduit's production-proven implementation.
// Uses protocol injection for C bridge independence.

import Foundation
import SwiftROS2Wire

// MARK: - DDS Transport Session

/// TransportSession implementation using DDS via DDSClientProtocol
///
/// The client protocol is injected at construction time, allowing the
/// consuming app (e.g., Conduit) to provide its own CycloneDDS C bridge wrapper.
public final class DDSTransportSession: TransportSession, @unchecked Sendable {
    private let client: any DDSClientProtocol
    private var config: TransportConfig?
    private var publishers: [String: DDSTransportPublisherImpl] = [:]
    private var subscribers: [DDSTransportSubscriberImpl] = []
    private let lock = NSLock()
    private var _sessionId: String = ""
    private var _isOpen = false

    public var transportType: TransportType { .dds }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isOpen && client.isConnected()
    }

    public var sessionId: String {
        lock.lock()
        defer { lock.unlock() }
        return _sessionId
    }

    /// Create a DDS transport session
    /// - Parameter client: DDS client protocol implementation (wraps C bridge)
    public init(client: any DDSClientProtocol) {
        self.client = client
    }

    public func open(config: TransportConfig) async throws {
        guard config.type == .dds else {
            throw TransportError.invalidConfiguration("Expected DDS configuration, got \(config.type)")
        }

        try config.validate()

        guard client.isAvailable else {
            throw TransportError.unsupportedFeature("DDS transport not available (CycloneDDS not compiled)")
        }

        // Build discovery config
        let discoveryMode: DDSBridgeDiscoveryMode
        switch config.ddsDiscoveryMode {
        case .multicast: discoveryMode = .multicast
        case .unicast: discoveryMode = .unicast
        case .hybrid: discoveryMode = .hybrid
        }

        let discoveryConfig = DDSBridgeDiscoveryConfig(
            mode: discoveryMode,
            unicastPeers: config.ddsUnicastPeers.map { $0.address },
            networkInterface: config.ddsNetworkInterface
        )

        try client.createSession(domainId: Int32(config.domainId), discoveryConfig: discoveryConfig)

        lock.lock()
        self.config = config
        self._isOpen = true
        self._sessionId = client.getSessionId() ?? generateFallbackSessionId()
        lock.unlock()
    }

    public func close() throws {
        let pubs = takeAllPublishers()
        for pub in pubs {
            try? pub.close()
        }

        let subs = takeAllSubscribers()
        for sub in subs {
            try? sub.close()
        }

        lock.lock()
        _isOpen = false
        _sessionId = ""
        config = nil
        lock.unlock()

        try client.destroySession()
    }

    public func createPublisher(
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: TransportQoS
    ) throws -> any TransportPublisher {
        guard !topic.isEmpty else {
            throw TransportError.invalidConfiguration("Topic name cannot be empty")
        }

        guard !typeName.isEmpty else {
            throw TransportError.invalidConfiguration("Type name cannot be empty")
        }

        lock.lock()
        guard _isOpen else {
            lock.unlock()
            throw TransportError.notConnected
        }

        if publishers[topic] != nil {
            lock.unlock()
            throw TransportError.publisherCreationFailed("Publisher already exists for topic: \(topic)")
        }
        lock.unlock()

        // Convert ROS 2 names to DDS names
        let ddsCodec = DDSWireCodec()
        let ddsTopicName = ddsCodec.ddsTopic(from: topic)
        let ddsTypeName = ddsCodec.ddsTypeName(from: typeName)
        let userData = ddsCodec.userDataString(typeHash: typeHash)

        // Build QoS
        let cfg = bridgeQoS(from: qos)

        let writerHandle = try client.createRawWriter(
            topicName: ddsTopicName,
            typeName: ddsTypeName,
            qos: cfg,
            userData: userData
        )

        let publisher = DDSTransportPublisherImpl(
            client: client,
            writer: writerHandle,
            topic: topic
        )

        appendPublisher(publisher, for: topic)
        return publisher
    }

    public func createSubscriber(
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) throws -> any TransportSubscriber {
        guard !topic.isEmpty else {
            throw TransportError.invalidConfiguration("Topic name cannot be empty")
        }
        guard !typeName.isEmpty else {
            throw TransportError.invalidConfiguration("Type name cannot be empty")
        }

        lock.lock()
        guard _isOpen else {
            lock.unlock()
            throw TransportError.notConnected
        }
        lock.unlock()

        // Convert ROS 2 names to DDS names
        let ddsCodec = DDSWireCodec()
        let ddsTopicName = ddsCodec.ddsTopic(from: topic)
        let ddsTypeName = ddsCodec.ddsTypeName(from: typeName)
        let userData = ddsCodec.userDataString(typeHash: typeHash)

        // Build QoS
        let cfg = bridgeQoS(from: qos)

        let readerHandle: any DDSReaderHandle
        do {
            readerHandle = try client.createRawReader(
                topicName: ddsTopicName,
                typeName: ddsTypeName,
                qos: cfg,
                userData: userData,
                handler: handler
            )
        } catch let e as DDSError {
            throw TransportError.subscriberCreationFailed(e.errorDescription ?? "\(e)")
        }

        let subscriber = DDSTransportSubscriberImpl(
            client: client,
            reader: readerHandle,
            topic: topic
        )
        appendSubscriber(subscriber)
        return subscriber
    }

    public func checkHealth() -> Bool {
        client.isConnected()
    }

    // MARK: - Private Helpers

    private func appendPublisher(_ publisher: DDSTransportPublisherImpl, for topic: String) {
        lock.lock()
        publishers[topic] = publisher
        lock.unlock()
    }

    private func takeAllPublishers() -> [DDSTransportPublisherImpl] {
        lock.lock()
        let pubs = Array(publishers.values)
        publishers.removeAll()
        lock.unlock()
        return pubs
    }

    private func appendSubscriber(_ subscriber: DDSTransportSubscriberImpl) {
        lock.lock()
        subscribers.append(subscriber)
        lock.unlock()
    }

    private func takeAllSubscribers() -> [DDSTransportSubscriberImpl] {
        lock.lock()
        let subs = subscribers
        subscribers.removeAll()
        lock.unlock()
        return subs
    }

    private func bridgeQoS(from qos: TransportQoS) -> DDSBridgeQoSConfig {
        DDSBridgeQoSConfig(
            reliability: qos.reliability == .reliable ? .reliable : .bestEffort,
            durability: qos.durability == .transientLocal ? .transientLocal : .volatile,
            historyKind: {
                switch qos.history {
                case .keepLast: return .keepLast
                case .keepAll: return .keepAll
                }
            }(),
            historyDepth: {
                switch qos.history {
                case .keepLast(let n): return Int32(n)
                case .keepAll: return 0
                }
            }()
        )
    }

    private func generateFallbackSessionId() -> String {
        UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(32).description
    }
}

// MARK: - DDS Transport Publisher

final class DDSTransportPublisherImpl: TransportPublisher, @unchecked Sendable {
    private let client: any DDSClientProtocol
    private var writer: (any DDSWriterHandle)?
    public let topic: String
    private let lock = NSLock()
    private var closed = false

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        if closed { return false }
        return writer?.isActive ?? false
    }

    init(client: any DDSClientProtocol, writer: any DDSWriterHandle, topic: String) {
        self.client = client
        self.writer = writer
        self.topic = topic
    }

    public func publish(data: Data, timestamp: UInt64, sequenceNumber: Int64) throws {
        guard !data.isEmpty else {
            throw TransportError.publishFailed("Data is empty")
        }

        guard data.count >= 4 else {
            throw TransportError.publishFailed("Data too short: missing CDR encapsulation header")
        }

        lock.lock()
        guard !closed, let w = writer else {
            lock.unlock()
            throw TransportError.publisherClosed
        }
        lock.unlock()

        try client.writeRawCDR(writer: w, data: data, timestamp: timestamp)
    }

    public func close() throws {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let w = writer
        writer = nil
        lock.unlock()

        if let w = w {
            client.destroyWriter(w)
        }
    }
}

// MARK: - DDS Transport Subscriber

final class DDSTransportSubscriberImpl: TransportSubscriber, @unchecked Sendable {
    private let client: any DDSClientProtocol
    private var reader: (any DDSReaderHandle)?
    public let topic: String
    private let lock = NSLock()
    private var closed = false

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        if closed { return false }
        return reader?.isActive ?? false
    }

    init(client: any DDSClientProtocol, reader: any DDSReaderHandle, topic: String) {
        self.client = client
        self.reader = reader
        self.topic = topic
    }

    public func close() throws {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let r = reader
        reader = nil
        lock.unlock()

        if let r = r {
            client.destroyReader(r)
        }
    }
}
