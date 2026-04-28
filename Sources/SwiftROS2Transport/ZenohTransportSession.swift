// ZenohTransportSession.swift
// TransportSession implementation using ZenohClientProtocol
//
// Ported from Conduit's production-proven implementation.
// Uses protocol injection for C bridge independence.

import Foundation
import SwiftROS2Wire

// MARK: - Zenoh Transport Session

/// TransportSession implementation using Zenoh via ZenohClientProtocol
///
/// The client protocol is injected at construction time, allowing the
/// consuming app (e.g., Conduit) to provide its own C bridge wrapper.
public final class ZenohTransportSession: TransportSession, @unchecked Sendable {
    let client: any ZenohClientProtocol
    var config: TransportConfig?
    var publishers: [String: ZenohTransportPublisher] = [:]
    let publishersLock = NSLock()
    let entityManager: EntityManager
    let gidManager: GIDManager

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
                // Auto-detection requires VersionDetector (provided by SwiftROS2 module)
                // Default to jazzy if not configured
                self.resolvedWireMode = config.wireMode ?? .jazzy
            }
        } catch let error as ZenohError {
            throw TransportError.connectionFailed(error.localizedDescription ?? "Zenoh connection failed")
        } catch let error as TransportError {
            throw error
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

    public func checkHealth() -> Bool {
        client.isSessionHealthy()
    }

    // MARK: - Private Helpers

    func extractNamespace(from topic: String) -> String {
        let components = topic.split(separator: "/").map(String.init)
        if components.count > 1 {
            return "/" + components.dropLast().joined(separator: "/")
        }
        return "/"
    }

    func extractTopicName(from topic: String) -> String {
        let components = topic.split(separator: "/").map(String.init)
        return components.last ?? topic
    }
}
