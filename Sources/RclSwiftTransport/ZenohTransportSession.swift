// ZenohTransportSession.swift
// TransportSession implementation using ZenohClientProtocol
//
// Ported from Conduit's production-proven implementation.
// Uses protocol injection for C bridge independence.

import Foundation
import RclSwiftWire

// MARK: - Zenoh Transport Session

/// TransportSession implementation using Zenoh via ZenohClientProtocol
///
/// The client protocol is injected at construction time, allowing the
/// consuming app (e.g., Conduit) to provide its own C bridge wrapper.
public final class ZenohTransportSession: TransportSession, @unchecked Sendable {
    private let client: any ZenohClientProtocol
    private var config: TransportConfig?
    private var publishers: [String: ZenohTransportPublisher] = [:]
    private let lock = NSLock()
    private let entityManager: EntityManager
    private let gidManager: GIDManager

    /// Detected or configured wire mode (set after open)
    public private(set) var resolvedWireMode: ROS2Distro?

    public var transportType: TransportType { .zenoh }

    public var isConnected: Bool {
        client.isSessionHealthy()
    }

    public var sessionId: String {
        (try? client.getSessionId()) ?? "unknown"
    }

    /// Create a Zenoh transport session
    /// - Parameters:
    ///   - client: Zenoh client protocol implementation (wraps C bridge)
    ///   - entityManager: Entity ID generator (optional, creates new if nil)
    ///   - gidManager: GID manager (optional, creates new if nil)
    public init(
        client: any ZenohClientProtocol,
        entityManager: EntityManager? = nil,
        gidManager: GIDManager? = nil
    ) {
        self.client = client
        self.entityManager = entityManager ?? EntityManager()
        self.gidManager = gidManager ?? GIDManager()
    }

    public func open(config: TransportConfig) async throws {
        guard config.type == .zenoh else {
            throw TransportError.invalidConfiguration("Expected Zenoh configuration, got \(config.type)")
        }

        guard let locator = config.zenohLocator, !locator.isEmpty else {
            throw TransportError.invalidConfiguration("Zenoh locator is required")
        }

        do {
            try config.validate()

            let timeout = config.connectionTimeout > 0 ? config.connectionTimeout : 10.0
            try await connectWithTimeout(locator: locator, timeout: timeout)

            self.config = config

            // Resolve wire mode: use explicit config or default to jazzy
            if let wireMode = config.wireMode {
                self.resolvedWireMode = wireMode
            } else {
                // Auto-detection requires VersionDetector (provided by RclSwift module)
                // Default to jazzy if not configured
                self.resolvedWireMode = config.wireMode ?? .jazzy
            }
        } catch let error as ZenohError {
            throw TransportError.connectionFailed(error.localizedDescription ?? "Zenoh connection failed")
        } catch let error as TransportError {
            throw error
        }
    }

    private func connectWithTimeout(locator: String, timeout: TimeInterval) async throws {
        let result = ConnectionResult()
        let client = self.client

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try client.open(locator: locator)
                result.setCompleted()
            } catch {
                result.setError(error)
            }
        }

        let startTime = Date()
        while !result.isCompleted() {
            if Date().timeIntervalSince(startTime) > timeout {
                throw TransportError.connectionTimeout(timeout)
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms polling
        }

        if let error = result.getError() {
            throw TransportError.connectionFailed(error.localizedDescription)
        }
    }

    public func close() throws {
        let pubs = takeAllPublishers()
        for pub in pubs {
            try? pub.close()
        }

        do {
            try client.close()
        } catch {
            throw TransportError.sessionClosed
        }

        resolvedWireMode = nil
        config = nil
    }

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

    public func checkHealth() -> Bool {
        client.isSessionHealthy()
    }

    // MARK: - Private Helpers

    private func appendPublisher(_ publisher: ZenohTransportPublisher, for topic: String) {
        lock.lock()
        publishers[topic] = publisher
        lock.unlock()
    }

    private func takeAllPublishers() -> [ZenohTransportPublisher] {
        lock.lock()
        let pubs = Array(publishers.values)
        publishers.removeAll()
        lock.unlock()
        return pubs
    }

    private func extractNamespace(from topic: String) -> String {
        let components = topic.split(separator: "/").map(String.init)
        if components.count > 1 {
            return "/" + components.dropLast().joined(separator: "/")
        }
        return "/"
    }

    private func extractTopicName(from topic: String) -> String {
        let components = topic.split(separator: "/").map(String.init)
        return components.last ?? topic
    }
}

// MARK: - Connection Result (Thread-safe)

final class ConnectionResult: @unchecked Sendable {
    private var error: Error?
    private var completed = false
    private let lock = NSLock()

    func setCompleted() {
        lock.lock()
        completed = true
        lock.unlock()
    }

    func setError(_ err: Error) {
        lock.lock()
        error = err
        completed = true
        lock.unlock()
    }

    func isCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func getError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return error
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

// MARK: - Zenoh Transport Subscriber Wrapper

final class ZenohTransportSubscriberWrapper: TransportSubscriber, @unchecked Sendable {
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

// MARK: - TransportQoS → QoSPolicy Conversion

extension TransportQoS {
    /// Convert to wire-level QoSPolicy for liveliness token encoding
    public func toQoSPolicy() -> QoSPolicy {
        let rel: QoSPolicy.Reliability = self.reliability == .reliable ? .reliable : .bestEffort
        let dur: QoSPolicy.Durability = self.durability == .transientLocal ? .transientLocal : .volatile
        let hist: QoSPolicy.HistoryPolicy
        let depth: Int

        switch self.history {
        case .keepLast(let n):
            hist = .keepLast
            depth = n
        case .keepAll:
            hist = .keepAll
            depth = 1000
        }

        return QoSPolicy(
            reliability: rel,
            durability: dur,
            historyPolicy: hist,
            historyDepth: depth
        )
    }
}
