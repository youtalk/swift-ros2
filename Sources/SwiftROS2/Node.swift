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
    private var services: [AnyObject] = []
    private var clients: [AnyObject] = []
    private var actionServers: [AnyObject] = []
    private var actionClients: [AnyObject] = []
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

    // MARK: - Service

    /// Create a service server for a specific ``ROS2ServiceType``.
    ///
    /// The handler closure receives a typed request and returns a typed
    /// response. Throwing from the handler surfaces to the caller as a
    /// ``ServiceError/handlerFailed(_:)`` (Zenoh) or as a dropped reply
    /// (DDS) — see the swift-ros2 docs for the per-transport contract.
    public func createService<S: ROS2ServiceType>(
        _ serviceType: S.Type,
        name: String,
        qos: QoSProfile = .servicesDefault,
        handler: @escaping @Sendable (S.Request) async throws -> S.Response
    ) async throws -> ROS2Service<S> {
        let fullName = buildFullTopic(name)
        let typeInfo = S.typeInfo
        let transportQoS = qos.toTransportQoS()
        let supportsHash = context.distro.supportsTypeHash
        let isLegacy = context.distro.isLegacySchema
        let requestHash = supportsHash ? typeInfo.requestTypeHash : nil
        let responseHash = supportsHash ? typeInfo.responseTypeHash : nil

        // Wrap the typed user handler in a CDR-bytes handler the transport
        // can call without knowing about S.Request / S.Response.
        let cdrHandler: @Sendable (Data) async throws -> Data = { reqData in
            let decoder: CDRDecoder
            do {
                decoder = try CDRDecoder(data: reqData, isLegacySchema: isLegacy)
            } catch {
                throw ServiceError.requestDecodingFailed(error.localizedDescription)
            }
            let typedRequest: S.Request
            do {
                typedRequest = try S.Request(from: decoder)
            } catch {
                throw ServiceError.requestDecodingFailed(error.localizedDescription)
            }
            let typedResponse = try await handler(typedRequest)
            let encoder = CDREncoder(isLegacySchema: isLegacy)
            do {
                try typedResponse.encode(to: encoder)
            } catch {
                throw ServiceError.responseEncodingFailed(error.localizedDescription)
            }
            return encoder.getData()
        }

        let transportSvc = try session.createServiceServer(
            name: fullName,
            serviceTypeName: typeInfo.serviceName,
            requestTypeHash: requestHash,
            responseTypeHash: responseHash,
            qos: transportQoS,
            handler: cdrHandler
        )

        let service = ROS2Service<S>(transport: transportSvc)
        appendService(service)
        return service
    }

    /// Create a service client for a specific ``ROS2ServiceType``.
    public func createClient<S: ROS2ServiceType>(
        _ serviceType: S.Type,
        name: String,
        qos: QoSProfile = .servicesDefault
    ) async throws -> ROS2Client<S> {
        let fullName = buildFullTopic(name)
        let typeInfo = S.typeInfo
        let transportQoS = qos.toTransportQoS()
        let supportsHash = context.distro.supportsTypeHash
        let requestHash = supportsHash ? typeInfo.requestTypeHash : nil
        let responseHash = supportsHash ? typeInfo.responseTypeHash : nil

        let transportClient = try session.createServiceClient(
            name: fullName,
            serviceTypeName: typeInfo.serviceName,
            requestTypeHash: requestHash,
            responseTypeHash: responseHash,
            qos: transportQoS
        )

        let client = ROS2Client<S>(
            transport: transportClient,
            isLegacySchema: context.distro.isLegacySchema
        )
        appendClient(client)
        return client
    }

    // MARK: - Action

    /// Create an action server for a specific ``ROS2Action``.
    public func createActionServer<H: ActionServerHandler>(
        _ actionType: H.Action.Type,
        name: String,
        qos: QoSProfile = .actionDefault,
        handler: H
    ) async throws -> ROS2ActionServer<H> {
        let fullName = buildFullTopic(name)
        let typeInfo = H.Action.typeInfo
        let transportQoS = qos.toTransportQoS()
        let supportsHash = context.distro.supportsTypeHash
        let hashes = ActionRoleTypeHashes(
            sendGoalRequest: supportsHash ? typeInfo.sendGoalRequestTypeHash : nil,
            sendGoalResponse: supportsHash ? typeInfo.sendGoalResponseTypeHash : nil,
            cancelGoalRequest: supportsHash ? CancelGoalSrv.typeInfo.requestTypeHash : nil,
            cancelGoalResponse: supportsHash ? CancelGoalSrv.typeInfo.responseTypeHash : nil,
            getResultRequest: supportsHash ? typeInfo.getResultRequestTypeHash : nil,
            getResultResponse: supportsHash ? typeInfo.getResultResponseTypeHash : nil,
            feedbackMessage: supportsHash ? typeInfo.feedbackMessageTypeHash : nil,
            statusArray: supportsHash ? GoalStatusArray.typeInfo.typeHash : nil
        )

        let serverHolder = WeakHolder<ROS2ActionServer<H>>()
        let handlers = ROS2ActionServer<H>.makeHandlers { serverHolder.value }
        let transportServer = try session.createActionServer(
            name: fullName,
            actionTypeName: typeInfo.actionName,
            roleTypeHashes: hashes,
            qos: transportQoS,
            handlers: handlers
        )
        let server = ROS2ActionServer<H>(
            transport: transportServer,
            handler: handler,
            isLegacySchema: context.distro.isLegacySchema
        )
        serverHolder.value = server
        appendActionServer(server)
        return server
    }

    /// Create an action client for a specific ``ROS2Action``.
    public func createActionClient<A: ROS2Action>(
        _ actionType: A.Type,
        name: String,
        qos: QoSProfile = .actionDefault
    ) async throws -> ROS2ActionClient<A> {
        let fullName = buildFullTopic(name)
        let typeInfo = A.typeInfo
        let transportQoS = qos.toTransportQoS()
        let supportsHash = context.distro.supportsTypeHash
        let hashes = ActionRoleTypeHashes(
            sendGoalRequest: supportsHash ? typeInfo.sendGoalRequestTypeHash : nil,
            sendGoalResponse: supportsHash ? typeInfo.sendGoalResponseTypeHash : nil,
            cancelGoalRequest: supportsHash ? CancelGoalSrv.typeInfo.requestTypeHash : nil,
            cancelGoalResponse: supportsHash ? CancelGoalSrv.typeInfo.responseTypeHash : nil,
            getResultRequest: supportsHash ? typeInfo.getResultRequestTypeHash : nil,
            getResultResponse: supportsHash ? typeInfo.getResultResponseTypeHash : nil,
            feedbackMessage: supportsHash ? typeInfo.feedbackMessageTypeHash : nil,
            statusArray: supportsHash ? GoalStatusArray.typeInfo.typeHash : nil
        )

        let transportClient = try session.createActionClient(
            name: fullName,
            actionTypeName: typeInfo.actionName,
            roleTypeHashes: hashes,
            qos: transportQoS
        )
        let client = ROS2ActionClient<A>(
            transport: transportClient,
            isLegacySchema: context.distro.isLegacySchema
        )
        appendActionClient(client)
        return client
    }

    // MARK: - Lifecycle

    /// Destroy this node and release all resources
    public func destroy() async {
        let (pubs, subs, svcs, clis, aSrvs, aClis) = takeAllEntities()
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
        for svc in svcs {
            if let s = svc as? ServiceCloseable {
                try? s.closeService()
            }
        }
        for cli in clis {
            if let c = cli as? ClientCloseable {
                try? c.closeClient()
            }
        }
        for s in aSrvs {
            if let s = s as? ActionServerCloseable {
                try? s.closeActionServer()
            }
        }
        for c in aClis {
            if let c = c as? ActionClientCloseable {
                try? c.closeActionClient()
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

    private func appendService(_ service: AnyObject) {
        lock.lock()
        services.append(service)
        lock.unlock()
    }

    private func appendClient(_ client: AnyObject) {
        lock.lock()
        clients.append(client)
        lock.unlock()
    }

    private func appendActionServer(_ server: AnyObject) {
        lock.lock()
        actionServers.append(server)
        lock.unlock()
    }

    private func appendActionClient(_ client: AnyObject) {
        lock.lock()
        actionClients.append(client)
        lock.unlock()
    }

    private func takeAllEntities() -> (
        [AnyObject], [AnyObject], [AnyObject], [AnyObject], [AnyObject], [AnyObject]
    ) {
        lock.lock()
        let pubs = publishers
        let subs = subscriptions
        let svcs = services
        let clis = clients
        let aSrvs = actionServers
        let aClis = actionClients
        publishers.removeAll()
        subscriptions.removeAll()
        services.removeAll()
        clients.removeAll()
        actionServers.removeAll()
        actionClients.removeAll()
        lock.unlock()
        return (pubs, subs, svcs, clis, aSrvs, aClis)
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
