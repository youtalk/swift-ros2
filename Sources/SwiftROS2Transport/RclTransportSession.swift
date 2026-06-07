// RclTransportSession.swift
// TransportSession backed by the real rcl + rmw_cyclonedds_cpp stack via
// RclClientProtocol. M1 is publish-only and assumes a single node.

import Foundation

public final class RclTransportSession: TransportSession, @unchecked Sendable {
    let client: any RclClientProtocol
    private let lock = NSLock()
    private var isOpen = false
    private var _sessionId = ""
    private var nodes: [String: any RclNodeHandle] = [:]
    private var currentNode: (any RclNodeHandle)?
    var publishers: [String: RclTransportPublisher] = [:]

    public var transportType: TransportType { .rcl }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isOpen
    }

    public var sessionId: String {
        lock.lock()
        defer { lock.unlock() }
        return _sessionId
    }

    package init(client: any RclClientProtocol) {
        self.client = client
    }

    public func open(config: TransportConfig) async throws {
        guard config.type == .rcl else {
            throw TransportError.invalidConfiguration("Expected RCL configuration, got \(config.type)")
        }
        try config.validate()
        guard client.isAvailable else {
            throw TransportError.unsupportedFeature("RCL transport not available (CRos2Jazzy not built)")
        }
        try client.createContext(domainId: Int32(config.domainId))
        lock.lock()
        isOpen = true
        _sessionId = "rcl-\(config.domainId)"
        lock.unlock()
    }

    public func registerNode(name: String, namespace: String) throws {
        lock.lock()
        guard isOpen else {
            lock.unlock()
            throw TransportError.notConnected
        }
        lock.unlock()
        let node = try client.createNode(name: name, namespace: namespace)
        lock.lock()
        nodes[nodeKey(name, namespace)] = node
        currentNode = node
        lock.unlock()
    }

    public func unregisterNode(name: String, namespace: String) {
        lock.lock()
        let removed = nodes.removeValue(forKey: nodeKey(name, namespace))
        if let removed, currentNode === removed {
            currentNode = nodes.values.first
        }
        lock.unlock()
        if let removed {
            client.destroyNode(removed)
        }
    }

    /// Atomically validate the session is open, the topic is free, and a node
    /// exists; returns the node a new publisher attaches to (M1 single-node).
    func preflightPublisher(topic: String) throws -> any RclNodeHandle {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen else { throw TransportError.notConnected }
        guard publishers[topic] == nil else {
            throw TransportError.publisherCreationFailed("Publisher already exists for topic: \(topic)")
        }
        guard let node = currentNode else {
            throw TransportError.publisherCreationFailed("no node registered — create a node first")
        }
        return node
    }

    package func createSubscriber(
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) throws -> any TransportSubscriber {
        throw TransportError.unsupportedFeature("createSubscriber (transport: rcl) — M1 is publish-only")
    }

    public func close() throws {
        lock.lock()
        let wasOpen = isOpen
        let pubs = Array(publishers.values)
        publishers.removeAll()
        let ns = Array(nodes.values)
        nodes.removeAll()
        currentNode = nil
        isOpen = false
        _sessionId = ""
        lock.unlock()
        for p in pubs { try? p.close() }
        for n in ns { client.destroyNode(n) }
        if wasOpen { client.destroyContext() }
    }

    public func checkHealth() -> Bool { isConnected }

    // MARK: - Helpers

    private func nodeKey(_ name: String, _ namespace: String) -> String {
        let ns = namespace.isEmpty ? "/" : namespace
        return ns.hasSuffix("/") ? "\(ns)\(name)" : "\(ns)/\(name)"
    }

    func appendPublisher(_ pub: RclTransportPublisher, for topic: String) {
        lock.lock()
        publishers[topic] = pub
        lock.unlock()
    }

    package func createServiceServer(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data) async throws -> Data
    ) throws -> any TransportService {
        throw TransportError.unsupportedFeature("createServiceServer (transport: rcl) — not supported in M1")
    }

    package func createServiceClient(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS
    ) throws -> any TransportClient {
        throw TransportError.unsupportedFeature("createServiceClient (transport: rcl) — not supported in M1")
    }
}
