// NodeScopedSession.swift
// Additive node-aware creation seam (1.x API-frozen).

import Foundation
import SwiftROS2CDR
import SwiftROS2Wire

/// Additive seam: entity creation bound to a specific ROS 2 node, for backends
/// that model real nodes (the rcl backend). A brand-new `package` protocol —
/// it does NOT alter the existing `TransportSession` surface, so the public API
/// digest is unchanged. Only `RclTransportSession` conforms; the wire sessions
/// (Zenoh/DDS) synthesize node identity per publisher and do not.
///
/// `ROS2Node` downcasts its `TransportSession` to `NodeScopedSession`. When the
/// cast succeeds (rcl backend) it passes the owning node's `name` / `namespace`
/// so the entity is bound to the right node; when it fails (wire backends) it
/// falls back to the plain `TransportSession` create methods.
package protocol NodeScopedSession: AnyObject, Sendable {
    /// Create a publisher bound to a specific ROS 2 node.
    ///
    /// `nodeName` / `nodeNamespace` identify the owning ROS 2 node. Backends
    /// that model real nodes (the rcl backend) bind the entity to that node;
    /// passing `nil` falls back to the session's single-node behaviour.
    func createPublisher(
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: TransportQoS,
        nodeName: String?,
        nodeNamespace: String?
    ) throws -> any TransportPublisher

    /// Create a subscriber bound to a specific ROS 2 node.
    ///
    /// `nodeName` / `nodeNamespace` carry the owning-node identity — see
    /// ``createPublisher(topic:typeName:typeHash:qos:nodeName:nodeNamespace:)``.
    func createSubscriber(
        topic: String,
        typeName: String,
        typeHash: String?,
        qos: TransportQoS,
        nodeName: String?,
        nodeNamespace: String?,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) throws -> any TransportSubscriber

    /// Create a Service Server bound to a specific ROS 2 node.
    ///
    /// `serviceTypeName` is the ROS-format service type name (e.g.
    /// `std_srvs/srv/Trigger`). `nodeName` / `nodeNamespace` carry the
    /// owning-node identity.
    func createServiceServer(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS,
        nodeName: String?,
        nodeNamespace: String?,
        handler: @escaping @Sendable (Data) async throws -> Data
    ) throws -> any TransportService

    /// Create a Service Client bound to a specific ROS 2 node.
    ///
    /// `serviceTypeName` is the ROS-format service type name (e.g.
    /// `std_srvs/srv/Trigger`). `nodeName` / `nodeNamespace` carry the
    /// owning-node identity.
    func createServiceClient(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS,
        nodeName: String?,
        nodeNamespace: String?
    ) throws -> any TransportClient

    /// Create an Action Server bound to a specific ROS 2 node.
    ///
    /// `actionTypeName` is the ROS-format action type (e.g.
    /// `example_interfaces/action/Fibonacci`). `nodeName` / `nodeNamespace`
    /// carry the owning-node identity.
    func createActionServer(
        name: String,
        actionTypeName: String,
        roleTypeHashes: ActionRoleTypeHashes,
        qos: TransportQoS,
        nodeName: String?,
        nodeNamespace: String?,
        handlers: TransportActionServerHandlers
    ) throws -> any TransportActionServer

    /// Create an Action Client bound to a specific ROS 2 node.
    ///
    /// `nodeName` / `nodeNamespace` carry the owning-node identity.
    func createActionClient(
        name: String,
        actionTypeName: String,
        roleTypeHashes: ActionRoleTypeHashes,
        qos: TransportQoS,
        nodeName: String?,
        nodeNamespace: String?
    ) throws -> any TransportActionClient
}
