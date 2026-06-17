// Context.swift
// ROS 2 Context: entry point for the swift-ros2 library

import Foundation
import SwiftROS2DDS
import SwiftROS2Transport
import SwiftROS2Wire

// Absent when the zenoh-rmw RCL variant is selected (SWIFT_ROS2_RCL_RMW=zenoh):
// zenoh-pico and the variant's bundled zenoh-c export the same zenoh C API and
// cannot link into one binary, so the manifest carves the wire family out.
#if canImport(SwiftROS2Zenoh)
    import SwiftROS2Zenoh
#endif

#if SWIFT_ROS2_RCL
    import SwiftROS2RCL
#endif

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
    public convenience init(
        transport: TransportConfig,
        distro: ROS2Distro = .jazzy,
        domainId: Int? = nil
    ) async throws {
        try await self.init(
            transport: transport,
            distro: distro,
            domainId: domainId,
            session: nil
        )
    }

    /// Package-internal initializer for tests / custom transport sessions.
    package init(
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
            self.session = try Self.makeDefaultSession(for: transport)
        }

        if !self.session.isConnected {
            try await self.session.open(config: transport)
        }
    }

    /// Create a node in this context.
    ///
    /// Preserves the pre-1.1 binary signature; delegates to the
    /// `options:`-aware overload with `ROS2NodeOptions.default`.
    public func createNode(
        name: String,
        namespace: String = "/"
    ) async throws -> ROS2Node {
        try await createNode(name: name, namespace: namespace, options: .default)
    }

    /// Create a node in this context with explicit per-node options.
    ///
    /// `options` has no default to avoid an overload-resolution
    /// ambiguity with the binary-stable `createNode(name:namespace:)`
    /// shim above. Pass `.default` to opt in to the standard behaviour
    /// (auto-register parameter services).
    public func createNode(
        name: String,
        namespace: String = "/",
        options: ROS2NodeOptions
    ) async throws -> ROS2Node {
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
        // Let the transport create a real node where it models one (rcl).
        // Wire-level transports default to a no-op. On a later failure the
        // `catch` below calls node.destroy(), which unregisters it.
        try session.registerNode(name: name, namespace: namespace)
        if options.startParameterServices {
            // Register before the node is reachable from `shutdown` — if
            // any of the six createService calls throws, close the services
            // already created on this node before rethrowing so we don't
            // leak transport handles into the caller's hands.
            //
            // `startParameterServices()` also installs the /parameter_events
            // emitter, so the auto-start and manual-start paths leave the
            // node in the same observable state.
            do {
                try await node.startParameterServices()
            } catch {
                await node.destroy()
                throw error
            }
        }
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

// MARK: - Default Session Factory

extension ROS2Context {
    static func makeDefaultSession(for config: TransportConfig) throws -> any TransportSession {
        switch config.type {
        case .zenoh:
            #if canImport(SwiftROS2Zenoh)
                // Wire path (zenoh-pico) — every build except the zenoh-rmw variant.
                return ZenohTransportSession(client: ZenohClient())
            #elseif SWIFT_ROS2_RCL_RMW_ZENOH
                // zenoh-pico is carved out (symbol collision with the variant's
                // zenoh-c); `.zenoh` resolves to rcl + rmw_zenoh_cpp instead. The
                // router locator is plumbed through RclTransportSession.open.
                return RclTransportSession(client: RclClient())
            #else
                throw TransportError.unsupportedFeature(
                    "zenoh wire transport is carved out of the zenoh-rmw RCL build "
                        + "(SWIFT_ROS2_RCL_RMW=zenoh) — use .rcl, or build without the variant")
            #endif
        case .dds:
            return DDSTransportSession(client: DDSClient())
        case .rcl:
            #if SWIFT_ROS2_RCL
                return RclTransportSession(client: RclClient())
            #else
                throw TransportError.unsupportedFeature(
                    "rcl backend not built — set SWIFT_ROS2_ENABLE_RCL=1 and rebuild on an Apple platform")
            #endif
        }
    }
}
