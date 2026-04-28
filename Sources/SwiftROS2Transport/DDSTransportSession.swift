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
    let client: any DDSClientProtocol
    private var config: TransportConfig?
    var publishers: [String: DDSTransportPublisherImpl] = [:]
    var subscribers: [DDSTransportSubscriberImpl] = []
    let lock = NSLock()
    private var _sessionId: String = ""
    var _isOpen = false

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

    public func checkHealth() -> Bool {
        client.isConnected()
    }

    // MARK: - Helpers

    func bridgeQoS(from qos: TransportQoS) -> DDSBridgeQoSConfig {
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
