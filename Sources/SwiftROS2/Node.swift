// Node.swift
// ROS 2 Node: creates publishers, subscribers, services, and actions

import Foundation
import SwiftROS2CDR
import SwiftROS2Messages
import SwiftROS2Transport
import SwiftROS2Wire

/// ROS 2 node — owns publishers, subscribers, services, and actions
///
/// ```swift
/// let node = try await ctx.createNode(name: "sensor_node", namespace: "/ios")
/// let pub = try await node.createPublisher(Imu.self, topic: "imu")
/// let sub = try await node.createSubscription(Imu.self, topic: "imu")
/// ```
public final class ROS2Node: @unchecked Sendable {
    public let name: String
    public let namespace: String
    public let fullyQualifiedName: String

    let context: ROS2Context
    private let session: any TransportSession
    private let nodeId: Int
    private let entityManager: EntityManager
    private let gidManager: GIDManager

    private var publishers: [AnyObject] = []
    private var subscriptions: [AnyObject] = []
    private let lock = NSLock()

    init(
        name: String,
        namespace: String,
        context: ROS2Context,
        session: any TransportSession,
        nodeId: Int,
        entityManager: EntityManager,
        gidManager: GIDManager
    ) {
        self.name = name
        self.namespace = namespace
        self.fullyQualifiedName = namespace.hasSuffix("/") ? "\(namespace)\(name)" : "\(namespace)/\(name)"
        self.context = context
        self.session = session
        self.nodeId = nodeId
        self.entityManager = entityManager
        self.gidManager = gidManager
    }

    // MARK: - Publisher

    /// Create a publisher for a message type
    public func createPublisher<M: CDREncodable & ROS2MessageType>(
        _ messageType: M.Type,
        topic: String,
        qos: QoSProfile = .sensorData
    ) async throws -> ROS2Publisher<M> {
        let fullTopic = buildFullTopic(topic)
        let typeInfo = M.typeInfo
        let transportQoS = qos.toTransportQoS()
        let effectiveTypeHash = context.distro.supportsTypeHash ? typeInfo.typeHash : nil

        let transportPub = try session.createPublisher(
            topic: fullTopic,
            typeName: typeInfo.typeName,
            typeHash: effectiveTypeHash,
            qos: transportQoS
        )

        let publisher = ROS2Publisher<M>(
            transportPublisher: transportPub,
            isLegacySchema: context.distro.isLegacySchema
        )
        appendPublisher(publisher)
        return publisher
    }

    // MARK: - Subscription

    /// Create a subscription for a message type (AsyncStream-based)
    public func createSubscription<M: CDRDecodable & ROS2MessageType>(
        _ messageType: M.Type,
        topic: String,
        qos: QoSProfile = .sensorData
    ) async throws -> ROS2Subscription<M> {
        let fullTopic = buildFullTopic(topic)
        let typeInfo = M.typeInfo
        let transportQoS = qos.toTransportQoS()
        let effectiveTypeHash = context.distro.supportsTypeHash ? typeInfo.typeHash : nil

        let subscription = ROS2Subscription<M>()

        let transportSub = try session.createSubscriber(
            topic: fullTopic,
            typeName: typeInfo.typeName,
            typeHash: effectiveTypeHash,
            qos: transportQoS,
            handler: { [weak subscription, isLegacy = context.distro.isLegacySchema] data, _ in
                guard let subscription = subscription else { return }
                do {
                    let decoder = try CDRDecoder(data: data, isLegacySchema: isLegacy)
                    let message = try M(from: decoder)
                    subscription.receive(message)
                } catch {
                    // Log deserialization error - silently drop malformed messages
                }
            }
        )

        subscription.setTransportSubscriber(transportSub)
        appendSubscription(subscription)
        return subscription
    }

    // MARK: - Lifecycle

    /// Destroy this node and release all resources
    public func destroy() async {
        let (pubs, subs) = takeAllEntities()
        for pub in pubs {
            if let p = pub as? PublisherCloseable {
                try? p.closePublisher()
            }
        }
        for sub in subs {
            if let s = sub as? SubscriptionCloseable {
                try? s.closeSubscription()
            }
        }
    }

    // MARK: - Private (synchronous lock helpers)

    private func appendPublisher(_ publisher: AnyObject) {
        lock.lock()
        publishers.append(publisher)
        lock.unlock()
    }

    private func appendSubscription(_ subscription: AnyObject) {
        lock.lock()
        subscriptions.append(subscription)
        lock.unlock()
    }

    private func takeAllEntities() -> ([AnyObject], [AnyObject]) {
        lock.lock()
        let pubs = publishers
        let subs = subscriptions
        publishers.removeAll()
        subscriptions.removeAll()
        lock.unlock()
        return (pubs, subs)
    }

    // MARK: - Helpers

    private func buildFullTopic(_ topic: String) -> String {
        if topic.hasPrefix("/") {
            return topic
        }
        let ns = namespace.hasSuffix("/") ? namespace : namespace + "/"
        return "\(ns)\(topic)"
    }
}

// Internal protocols for type-erased cleanup
protocol PublisherCloseable {
    func closePublisher() throws
}

protocol SubscriptionCloseable {
    func closeSubscription() throws
}
