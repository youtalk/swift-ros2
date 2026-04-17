// Context.swift
// ROS 2 Context: entry point for the swift-ros2 library

import Foundation
import SwiftROS2Transport
import SwiftROS2Wire

/// ROS 2 context — the entry point for creating nodes
///
/// A context owns a single transport session. All nodes created from this context
/// share the session. Multiple contexts can coexist (e.g., Zenoh + DDS simultaneously).
///
/// ```swift
/// let ctx = try await ROS2Context(transport: .zenoh(locator: "tcp/192.168.1.1:7447"))
/// let node = try await ctx.createNode(name: "my_node", namespace: "/ios")
/// ```
public final class ROS2Context: @unchecked Sendable {
    public let config: TransportConfig
    public let distro: ROS2Distro
    public let domainId: Int

    private let session: any TransportSession
    private let entityManager: EntityManager
    private let gidManager: GIDManager
    private var nodes: [ROS2Node] = []
    private let lock = NSLock()

    /// Create a new ROS 2 context
    ///
    /// - Parameters:
    ///   - transport: Transport configuration (Zenoh or DDS)
    ///   - distro: ROS 2 distribution for wire format (default: .jazzy)
    ///   - domainId: ROS 2 domain ID (default: 0)
    ///   - session: Custom transport session (nil to use factory)
    public init(
        transport: TransportConfig,
        distro: ROS2Distro = .jazzy,
        domainId: Int? = nil,
        session: (any TransportSession)? = nil
    ) async throws {
        self.config = transport
        self.distro = distro
        self.domainId = domainId ?? transport.domainId
        self.entityManager = EntityManager()
        self.gidManager = GIDManager()

        if let session = session {
            self.session = session
        } else {
            throw TransportError.unsupportedFeature(
                "Transport session must be provided. Built-in Zenoh/DDS sessions require their respective modules."
            )
        }

        if !self.session.isConnected {
            try await self.session.open(config: transport)
        }
    }

    /// Create a node in this context
    public func createNode(name: String, namespace: String = "/") async throws -> ROS2Node {
        let nodeId = entityManager.getNextEntityId()
        let node = ROS2Node(
            name: name,
            namespace: namespace,
            context: self,
            session: session,
            nodeId: nodeId,
            entityManager: entityManager,
            gidManager: gidManager
        )
        appendNode(node)
        return node
    }

    /// Shutdown the context and all nodes
    public func shutdown() async {
        let currentNodes = takeAllNodes()
        for node in currentNodes {
            await node.destroy()
        }
        try? session.close()
    }

    // MARK: - Private (synchronous lock helpers)

    private func appendNode(_ node: ROS2Node) {
        lock.lock()
        nodes.append(node)
        lock.unlock()
    }

    private func takeAllNodes() -> [ROS2Node] {
        lock.lock()
        let result = nodes
        nodes.removeAll()
        lock.unlock()
        return result
    }

    /// The session ID for debugging
    public var sessionId: String {
        session.sessionId
    }

    /// Whether the session is connected
    public var isConnected: Bool {
        session.isConnected
    }
}
