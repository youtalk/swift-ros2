// DDSTransportSession+Subscriber.swift
// Subscriber creation and the DDSTransportSubscriberImpl concrete type.

import Foundation
import SwiftROS2Wire

extension DDSTransportSession {
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

    private func appendSubscriber(_ subscriber: DDSTransportSubscriberImpl) {
        lock.lock()
        subscribers.append(subscriber)
        lock.unlock()
    }

    func takeAllSubscribers() -> [DDSTransportSubscriberImpl] {
        lock.lock()
        let subs = subscribers
        subscribers.removeAll()
        lock.unlock()
        return subs
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
