// RclTransportSession.swift
// TransportSession backed by the real rcl + rmw_cyclonedds_cpp stack via
// RclClientProtocol. Publish (M1) + subscribe (M4); assumes a single node.

import Foundation

/// `TransportSession` backed by the real `rcl` + `rmw_cyclonedds_cpp` stack via
/// `RclClientProtocol`. Publish (M1) + subscribe (M4); assumes a single node.
public final class RclTransportSession: TransportSession, @unchecked Sendable {
    let client: any RclClientProtocol
    private let lock = NSLock()
    private var isOpen = false
    private var _sessionId = ""
    private var nodes: [String: any RclNodeHandle] = [:]
    private var currentNode: (any RclNodeHandle)?
    var publishers: [String: RclTransportPublisher] = [:]
    var subscribers: [RclTransportSubscriber] = []
    var serviceServers: [RclTransportServiceServer] = []
    var serviceClients: [RclTransportServiceClient] = []
    var actionServers: [RclTransportActionServer] = []
    var actionClients: [RclTransportActionClient] = []

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
        // Bare host addresses (`peer.address`), mirroring the wire DDS path
        // (DDSTransportSession): the C bridge drops each verbatim into
        // `<Peer address="%s"/>`, where CycloneDDS needs a bare host (not a
        // `udp/host:port` locator).
        try client.createContext(
            domainId: Int32(config.domainId),
            unicastPeerAddresses: config.ddsUnicastPeers.map { $0.address },
            networkInterface: config.ddsNetworkInterface)
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

    /// Resolve the node a new entity attaches to: look up by (name, namespace)
    /// when supplied, else fall back to the last-registered node (single-node
    /// back-compat). An unknown (name, namespace) also falls back to
    /// `currentNode`. Caller holds `lock`.
    private func resolveNodeLocked(_ name: String?, _ namespace: String?) -> (any RclNodeHandle)? {
        if let name {
            let ns = namespace ?? "/"
            if let node = nodes[nodeKey(name, ns)] { return node }
        }
        return currentNode
    }

    /// Atomically validate the session is open, the topic is free, and a node
    /// exists; returns the node a new publisher attaches to. With
    /// `nodeName`/`nodeNamespace` the entity binds to that registered node
    /// (multi-node); nil falls back to the last-registered node.
    func preflightPublisher(
        topic: String, nodeName: String?, nodeNamespace: String?
    ) throws -> any RclNodeHandle {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen else { throw TransportError.notConnected }
        guard publishers[topic] == nil else {
            throw TransportError.publisherCreationFailed("Publisher already exists for topic: \(topic)")
        }
        guard let node = resolveNodeLocked(nodeName, nodeNamespace) else {
            throw TransportError.publisherCreationFailed("no node registered — create a node first")
        }
        return node
    }

    /// Atomically validate the session is open and a node exists; returns the
    /// node a new subscriber attaches to. Resolves by (name, namespace) when
    /// supplied, else the last-registered node.
    func preflightSubscriber(
        nodeName: String?, nodeNamespace: String?
    ) throws -> any RclNodeHandle {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen else { throw TransportError.notConnected }
        guard let node = resolveNodeLocked(nodeName, nodeNamespace) else {
            throw TransportError.subscriberCreationFailed("no node registered — create a node first")
        }
        return node
    }

    public func close() throws {
        lock.lock()
        let wasOpen = isOpen
        let actClients = actionClients
        actionClients.removeAll()
        let actServers = actionServers
        actionServers.removeAll()
        let srvClients = serviceClients
        serviceClients.removeAll()
        let srvServers = serviceServers
        serviceServers.removeAll()
        let subs = subscribers
        subscribers.removeAll()
        let pubs = Array(publishers.values)
        publishers.removeAll()
        let ns = Array(nodes.values)
        nodes.removeAll()
        currentNode = nil
        isOpen = false
        _sessionId = ""
        lock.unlock()
        // Wait-thread entities first (action clients, action servers, service
        // clients, service servers, then subscribers): each close joins the
        // entity's wait thread, so no handler can fire against a node/context
        // being torn down below. Clients go before their server counterparts
        // so pending calls / goals resume with sessionClosed before the
        // server disappears.
        for c in actClients { try? c.close() }
        for s in actServers { try? s.close() }
        for c in srvClients { try? c.close() }
        for s in srvServers { try? s.close() }
        for s in subs { try? s.close() }
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

    /// Register a created subscriber, re-checking that the session is still
    /// open: if `close()` interleaved between `preflightSubscriber()` and the
    /// client create call, the new subscription would escape teardown — its
    /// wait thread never joined, its handler context leaked. Destroy it here
    /// (joins the wait thread) and surface `notConnected` instead.
    func appendSubscriber(_ sub: RclTransportSubscriber) throws {
        lock.lock()
        guard isOpen else {
            lock.unlock()
            try? sub.close()
            throw TransportError.notConnected
        }
        subscribers.append(sub)
        lock.unlock()
    }

    /// Atomically validate the session is open and a node exists; returns the
    /// node a new service / action server / client attaches to. Resolves by
    /// (name, namespace) when supplied, else the last-registered node.
    func preflightServiceEntity(
        nodeName: String?, nodeNamespace: String?
    ) throws -> any RclNodeHandle {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen else { throw TransportError.notConnected }
        guard let node = resolveNodeLocked(nodeName, nodeNamespace) else {
            throw TransportError.subscriberCreationFailed("no node registered — create a node first")
        }
        return node
    }

    /// Register a created service server, re-checking that the session is
    /// still open — same close-race contract as `appendSubscriber`.
    func appendServiceServer(_ server: RclTransportServiceServer) throws {
        lock.lock()
        guard isOpen else {
            lock.unlock()
            try? server.close()
            throw TransportError.notConnected
        }
        serviceServers.append(server)
        lock.unlock()
    }

    /// Register a created service client, re-checking that the session is
    /// still open — same close-race contract as `appendSubscriber`.
    func appendServiceClient(_ serviceClient: RclTransportServiceClient) throws {
        lock.lock()
        guard isOpen else {
            lock.unlock()
            try? serviceClient.close()
            throw TransportError.notConnected
        }
        serviceClients.append(serviceClient)
        lock.unlock()
    }

    /// Register a created action server, re-checking that the session is
    /// still open — same close-race contract as `appendSubscriber`.
    func appendActionServer(_ server: RclTransportActionServer) throws {
        lock.lock()
        guard isOpen else {
            lock.unlock()
            try? server.close()
            throw TransportError.notConnected
        }
        actionServers.append(server)
        lock.unlock()
    }

    /// Register a created action client, re-checking that the session is
    /// still open — same close-race contract as `appendSubscriber`.
    func appendActionClient(_ actionClient: RclTransportActionClient) throws {
        lock.lock()
        guard isOpen else {
            lock.unlock()
            try? actionClient.close()
            throw TransportError.notConnected
        }
        actionClients.append(actionClient)
        lock.unlock()
    }
}

// MARK: - NodeScopedSession conformance
//
// Additive node-aware seam (see `NodeScopedSession.swift`). The node-aware
// 6-arg create methods live in the `RclTransportSession+{Publisher,Subscriber,
// Service,Action}.swift` extensions and satisfy these requirements; the plain
// `TransportSession` 4-/5-arg methods there forward to them with
// `nodeName: nil, nodeNamespace: nil`.
extension RclTransportSession: NodeScopedSession {}
