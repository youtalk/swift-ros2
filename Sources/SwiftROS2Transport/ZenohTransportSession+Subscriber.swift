// ZenohTransportSession+Subscriber.swift
// Subscriber creation and the ZenohTransportSubscriberWrapper concrete type.

import Foundation
import SwiftROS2Wire

extension ZenohTransportSession {
    public func createSubscriber(
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) throws -> any TransportSubscriber {
        guard isConnected else {
            throw TransportError.notConnected
        }

        guard let config = config else {
            throw TransportError.notConnected
        }

        let wireMode = resolvedWireMode ?? .jazzy
        let codec = ZenohWireCodec(distro: wireMode)

        let effectiveTypeHash: String?
        if wireMode.supportsTypeHash {
            effectiveTypeHash = typeHash
        } else {
            effectiveTypeHash = nil
        }

        let keyExpr = codec.makeKeyExpr(
            domainId: config.domainId,
            namespace: extractNamespace(from: topic),
            topic: extractTopicName(from: topic),
            typeName: typeName,
            typeHash: effectiveTypeHash ?? wireMode.typeHashPlaceholder
        )

        let subHandle = try client.subscribe(keyExpr: keyExpr) { sample in
            let timestampNs = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
            handler(sample.payload, timestampNs)
        }

        return ZenohTransportSubscriberWrapper(handle: subHandle, topic: topic)
    }
}

// MARK: - Zenoh Transport Subscriber Wrapper

private final class ZenohTransportSubscriberWrapper: TransportSubscriber, @unchecked Sendable {
    private let handle: any ZenohSubscriberHandle
    public let topic: String
    private var _isActive = true
    private let lock = NSLock()

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isActive
    }

    init(handle: any ZenohSubscriberHandle, topic: String) {
        self.handle = handle
        self.topic = topic
    }

    public func close() throws {
        lock.lock()
        _isActive = false
        lock.unlock()
        try handle.close()
    }
}
