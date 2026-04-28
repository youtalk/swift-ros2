// ZenohTransportSession+Publisher.swift
// Publisher creation and the ZenohTransportPublisher concrete type.

import Foundation
import SwiftROS2Wire

extension ZenohTransportSession {
    public func createPublisher(
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: TransportQoS
    ) throws -> any TransportPublisher {
        guard isConnected else {
            throw TransportError.notConnected
        }

        guard let config = config else {
            throw TransportError.notConnected
        }

        let wireMode = resolvedWireMode ?? (typeHash != nil ? .jazzy : .humble)
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

        // Declare key expression
        let declaredKey: any ZenohKeyExprHandle
        do {
            declaredKey = try client.declareKeyExpr(keyExpr)
        } catch let error as ZenohError {
            throw TransportError.publisherCreationFailed(error.localizedDescription ?? "Key declaration failed")
        }

        // Create liveliness token for ROS 2 discovery
        let sid = (try? client.getSessionId()) ?? "unknown"
        let nodeId = String(entityManager.getNextEntityId())
        let entityId = String(entityManager.getNextEntityId())
        let nodeName = "ios_\(extractTopicName(from: topic))_node"

        let qosPolicy = qos.toQoSPolicy()
        let livelinessKeyExpr = codec.makeLivelinessToken(
            domainId: config.domainId,
            sessionId: sid,
            nodeId: nodeId,
            entityId: entityId,
            namespace: extractNamespace(from: topic),
            nodeName: nodeName,
            topic: extractTopicName(from: topic),
            typeName: typeName,
            typeHash: effectiveTypeHash ?? wireMode.typeHashPlaceholder,
            qos: qosPolicy
        )

        let livelinessToken: (any ZenohLivelinessTokenHandle)?
        do {
            livelinessToken = try client.declareLivelinessToken(livelinessKeyExpr)
        } catch {
            livelinessToken = nil
        }

        let gid = gidManager.getOrCreateGid()

        let publisher = ZenohTransportPublisher(
            client: client,
            declaredKey: declaredKey,
            livelinessToken: livelinessToken,
            codec: codec,
            gid: gid,
            topic: topic
        )

        appendPublisher(publisher, for: topic)
        return publisher
    }

    func appendPublisher(_ publisher: ZenohTransportPublisher, for topic: String) {
        publishersLock.lock()
        publishers[topic] = publisher
        publishersLock.unlock()
    }

    func takeAllPublishers() -> [ZenohTransportPublisher] {
        publishersLock.lock()
        let pubs = Array(publishers.values)
        publishers.removeAll()
        publishersLock.unlock()
        return pubs
    }
}

// MARK: - Zenoh Transport Publisher

/// TransportPublisher using Zenoh
public final class ZenohTransportPublisher: TransportPublisher, @unchecked Sendable {
    private let client: any ZenohClientProtocol
    private var declaredKey: (any ZenohKeyExprHandle)?
    private var livelinessToken: (any ZenohLivelinessTokenHandle)?
    private let codec: ZenohWireCodec
    private let gid: [UInt8]
    public let topic: String
    private let lock = NSLock()
    private var closed = false

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed && declaredKey != nil
    }

    init(
        client: any ZenohClientProtocol,
        declaredKey: any ZenohKeyExprHandle,
        livelinessToken: (any ZenohLivelinessTokenHandle)?,
        codec: ZenohWireCodec,
        gid: [UInt8],
        topic: String
    ) {
        self.client = client
        self.declaredKey = declaredKey
        self.livelinessToken = livelinessToken
        self.codec = codec
        self.gid = gid
        self.topic = topic
    }

    public func publish(data: Data, timestamp: UInt64, sequenceNumber: Int64) throws {
        lock.lock()
        guard !closed, let key = declaredKey else {
            lock.unlock()
            throw TransportError.publisherClosed
        }
        lock.unlock()

        let attachment = codec.buildAttachment(
            seq: sequenceNumber,
            tsNsec: Int64(bitPattern: timestamp),
            gid: gid
        )

        do {
            try client.put(keyExpr: key, payload: data, attachment: attachment)
        } catch let error as ZenohError {
            if case .sessionDisconnected = error {
                throw TransportError.sessionUnhealthy(error.localizedDescription ?? "Disconnected")
            }
            throw TransportError.publishFailed(error.localizedDescription ?? "Put failed")
        }
    }

    public func close() throws {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let token = livelinessToken
        livelinessToken = nil
        declaredKey = nil
        lock.unlock()

        try? token?.close()
    }
}
