// RclTransportSession+Subscriber.swift
// Subscriber creation and the RclTransportSubscriber concrete type.

import Foundation

extension RclTransportSession {
    package func createSubscriber(
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
        // typeHash is unused on this backend: rcl derives the hash from the
        // typesupport handle, so the wire-level pin the Zenoh/DDS sessions
        // need does not apply here.
        let node = try preflightSubscriber()
        let handle = try client.createSubscription(
            node: node, typeName: typeName, topic: topic, qos: qos, handler: handler)
        let sub = RclTransportSubscriber(client: client, handle: handle, topic: topic)
        appendSubscriber(sub)
        return sub
    }
}

final class RclTransportSubscriber: TransportSubscriber, @unchecked Sendable {
    private let client: any RclClientProtocol
    private var handle: (any RclSubscriptionHandle)?
    public let topic: String
    private let lock = NSLock()
    private var closed = false

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        if closed { return false }
        return handle?.isActive ?? false
    }

    init(client: any RclClientProtocol, handle: any RclSubscriptionHandle, topic: String) {
        self.client = client
        self.handle = handle
        self.topic = topic
    }

    public func close() throws {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let h = handle
        handle = nil
        lock.unlock()
        if let h {
            // Blocks until any in-flight handler invocation has returned.
            client.destroySubscription(h)
        }
    }
}
