// RclClientProtocol.swift
// FFI seam for the real-rcl backend. The concrete RclClient lives in the
// gated SwiftROS2RCL target; this protocol stays C-free so RclTransportSession
// is unit-testable with a mock (no xcframework) in ordinary CI.

import Foundation

/// Opaque handle to an rcl node owned by the client.
package protocol RclNodeHandle: AnyObject, Sendable {}

/// Opaque handle to an rcl publisher owned by the client.
package protocol RclPublisherHandle: AnyObject, Sendable {
    var isActive: Bool { get }
    func close()
}

/// Opaque handle to an rcl subscription owned by the client.
package protocol RclSubscriptionHandle: AnyObject, Sendable {
    var isActive: Bool { get }
}

/// Opaque handle to an rcl service server owned by the client.
package protocol RclServiceHandle: AnyObject, Sendable {
    var isActive: Bool { get }
}

/// Opaque handle to an rcl service client owned by the client.
package protocol RclClientHandle: AnyObject, Sendable {
    var isActive: Bool { get }
}

/// Lifecycle + publish + subscribe + service operations the rcl C bridge exposes.
package protocol RclClientProtocol: Sendable {
    /// Whether the native rcl stack is linked and usable.
    var isAvailable: Bool { get }

    func createContext(domainId: Int32) throws
    func destroyContext()

    func createNode(name: String, namespace: String) throws -> any RclNodeHandle
    func destroyNode(_ node: any RclNodeHandle)

    func createPublisher(
        node: any RclNodeHandle,
        typeName: String,
        topic: String,
        qos: TransportQoS
    ) throws -> any RclPublisherHandle

    /// Publish pre-serialized CDR bytes (XCDR1 incl. the 4-byte encapsulation header).
    func publishSerialized(_ publisher: any RclPublisherHandle, data: Data) throws

    /// Create a subscription whose receive thread invokes `handler` once per
    /// taken message with the raw CDR bytes (XCDR1 incl. the 4-byte
    /// encapsulation header) and the rmw source timestamp in nanoseconds
    /// (0 when the middleware reports none).
    func createSubscription(
        node: any RclNodeHandle,
        typeName: String,
        topic: String,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) throws -> any RclSubscriptionHandle

    /// Destroy a subscription. Blocks until any in-flight handler invocation completes.
    func destroySubscription(_ subscription: any RclSubscriptionHandle)

    /// Create a service server whose wait thread invokes `onRequest` once per
    /// taken request with the raw request CDR bytes (XCDR1 incl. the 4-byte
    /// encapsulation header) and the opaque 24-byte request-id blob to echo
    /// back via `sendResponse(_:requestId:data:)`. `srvTypeName` is the
    /// canonical ROS service type name (e.g. `example_interfaces/srv/AddTwoInts`).
    func createServiceServer(
        node: any RclNodeHandle,
        srvTypeName: String,
        serviceName: String,
        qos: TransportQoS,
        onRequest: @escaping @Sendable (Data, [UInt8]) -> Void
    ) throws -> any RclServiceHandle

    /// Send the response CDR bytes for a previously delivered 24-byte request
    /// id. Callable from any thread (the async handler's completion).
    func sendResponse(_ service: any RclServiceHandle, requestId: [UInt8], data: Data) throws

    /// Destroy a service server. Blocks until any in-flight onRequest invocation completes.
    func destroyServiceServer(_ service: any RclServiceHandle)

    /// Create a service client whose wait thread invokes `onResponse` once per
    /// taken response with rcl's sequence number (as returned by
    /// `sendRequest(_:data:)` for the matching request) and the raw response
    /// CDR bytes.
    func createServiceClient(
        node: any RclNodeHandle,
        srvTypeName: String,
        serviceName: String,
        qos: TransportQoS,
        onResponse: @escaping @Sendable (Int64, Data) -> Void
    ) throws -> any RclClientHandle

    /// Send pre-serialized request CDR bytes; returns rcl's sequence number —
    /// the correlation key `onResponse` echoes back.
    func sendRequest(_ client: any RclClientHandle, data: Data) throws -> Int64

    /// Whether a matching service server is currently available.
    func serverAvailable(_ client: any RclClientHandle) -> Bool

    /// Destroy a service client. Blocks until any in-flight onResponse invocation completes.
    func destroyServiceClient(_ client: any RclClientHandle)
}
