// RclClient.swift
// Concrete RclClientProtocol over the CRclBridge C FFI. Apple-only, gated.

import CRclBridge
import Foundation
import SwiftROS2Transport

// MARK: - Handles

private final class RclNodeBox: RclNodeHandle, @unchecked Sendable {
    let ptr: OpaquePointer
    init(_ ptr: OpaquePointer) { self.ptr = ptr }
}

/// Per-box lock serializes destroy vs. publish on the same publisher pointer.
final class RclPublisherBox: RclPublisherHandle, @unchecked Sendable {
    private var ptr: OpaquePointer?
    private let lock = NSLock()

    init(_ ptr: OpaquePointer) { self.ptr = ptr }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ptr != nil
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if let p = ptr {
            crcl_publisher_destroy(p)
            ptr = nil
        }
    }

    func withPtr<R>(_ body: (OpaquePointer) -> R) -> R? {
        lock.lock()
        defer { lock.unlock() }
        guard let p = ptr else { return nil }
        return body(p)
    }
}

/// Retained by `RclSubscriptionBox.contextBox` while the subscription is
/// alive. The `@unchecked Sendable` is justified: the class holds an
/// immutable `@Sendable` closure reference; the closure captures are the only
/// state shared across threads, and Swift's concurrency model already
/// requires those to be Sendable.
private final class RclSubscriptionContext: @unchecked Sendable {
    let handler: @Sendable (Data, UInt64) -> Void
    init(handler: @escaping @Sendable (Data, UInt64) -> Void) {
        self.handler = handler
    }
}

/// C-callable bridge matching `crcl_take_callback_t`.
/// The `ctx` pointer is an `Unmanaged<RclSubscriptionContext>` opaque pointer
/// created via `passRetained` in `createSubscription`; here we only borrow it
/// (`takeUnretainedValue`) — retention is released in `RclSubscriptionBox.close()`.
private func rclTakeCallbackBridge(
    ctx: UnsafeMutableRawPointer?,
    buf: UnsafePointer<UInt8>?,
    len: Int,
    sourceTimestampNs: Int64
) {
    guard let ctx else { return }
    let subscriptionContext = Unmanaged<RclSubscriptionContext>.fromOpaque(ctx).takeUnretainedValue()

    let payload: Data
    if let buf, len > 0 {
        payload = Data(bytes: buf, count: len)
    } else {
        payload = Data()
    }

    subscriptionContext.handler(payload, sourceTimestampNs > 0 ? UInt64(sourceTimestampNs) : 0)
}

/// Per-box lock serializes destroy vs. isActive checks for the same
/// subscription. Different subscriptions hold different locks.
private final class RclSubscriptionBox: RclSubscriptionHandle, @unchecked Sendable {
    private var ptr: OpaquePointer?
    private var contextBox: Unmanaged<RclSubscriptionContext>?
    private let lock = NSLock()

    init(_ ptr: OpaquePointer, contextBox: Unmanaged<RclSubscriptionContext>) {
        self.ptr = ptr
        self.contextBox = contextBox
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ptr != nil
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if let p = ptr {
            // crcl_subscription_destroy joins the wait thread before any fini,
            // so it blocks until any in-flight callback has returned. Only
            // after it returns is it safe to release the retained closure
            // context, because no further callback invocations will
            // dereference it.
            let rc = crcl_subscription_destroy(p)
            ptr = nil
            if rc < 0 {
                // The C side refused to destroy (self-destroy from the take
                // callback, or a failed join): the wait thread may still
                // invoke the callback, so the retained handler context must
                // leak alongside the C subscription rather than be released
                // under a live thread.
                contextBox = nil
                return
            }
        }
        if let box = contextBox {
            box.release()
            contextBox = nil
        }
    }
}

// MARK: - Service server

/// Retained by `RclServiceBox.contextBox` while the service is alive. Same
/// `@unchecked Sendable` justification as `RclSubscriptionContext`: the only
/// state is an immutable `@Sendable` closure reference.
private final class RclServiceContext: @unchecked Sendable {
    let onRequest: @Sendable (Data, [UInt8]) -> Void
    init(onRequest: @escaping @Sendable (Data, [UInt8]) -> Void) {
        self.onRequest = onRequest
    }
}

/// C-callable bridge matching `crcl_request_callback_t`.
/// The `ctx` pointer is an `Unmanaged<RclServiceContext>` opaque pointer
/// created via `passRetained` in `createServiceServer`; here we only borrow it
/// (`takeUnretainedValue`) — retention is released in `RclServiceBox.close()`.
private func rclRequestCallbackBridge(
    ctx: UnsafeMutableRawPointer?,
    requestId: UnsafePointer<UInt8>?,
    buf: UnsafePointer<UInt8>?,
    len: Int
) {
    guard let ctx, let requestId else { return }
    let serviceContext = Unmanaged<RclServiceContext>.fromOpaque(ctx).takeUnretainedValue()

    let blob = [UInt8](UnsafeBufferPointer(start: requestId, count: Int(CRCL_REQUEST_ID_SIZE)))
    let payload: Data
    if let buf, len > 0 {
        payload = Data(bytes: buf, count: len)
    } else {
        payload = Data()
    }

    serviceContext.onRequest(payload, blob)
}

/// Per-box lock serializes destroy vs. sendResponse on the same service
/// pointer. Close contract mirrors `RclSubscriptionBox` exactly, including the
/// leak-on-failed-destroy behavior.
private final class RclServiceBox: RclServiceHandle, @unchecked Sendable {
    private var ptr: OpaquePointer?
    private var contextBox: Unmanaged<RclServiceContext>?
    private let lock = NSLock()

    init(_ ptr: OpaquePointer, contextBox: Unmanaged<RclServiceContext>) {
        self.ptr = ptr
        self.contextBox = contextBox
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ptr != nil
    }

    func withPtr<R>(_ body: (OpaquePointer) -> R) -> R? {
        lock.lock()
        defer { lock.unlock() }
        guard let p = ptr else { return nil }
        return body(p)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if let p = ptr {
            // crcl_service_destroy joins the wait thread before any fini, so
            // it blocks until any in-flight callback has returned. Only after
            // it returns is it safe to release the retained closure context.
            let rc = crcl_service_destroy(p)
            ptr = nil
            if rc < 0 {
                // The C side refused to destroy (self-destroy from the take
                // callback, or a failed join): the wait thread may still
                // invoke the callback, so the retained handler context must
                // leak alongside the C service rather than be released under
                // a live thread.
                contextBox = nil
                return
            }
        }
        if let box = contextBox {
            box.release()
            contextBox = nil
        }
    }
}

// MARK: - Service client

/// Retained by `RclServiceClientBox.contextBox` while the client is alive.
private final class RclServiceClientContext: @unchecked Sendable {
    let onResponse: @Sendable (Int64, Data) -> Void
    init(onResponse: @escaping @Sendable (Int64, Data) -> Void) {
        self.onResponse = onResponse
    }
}

/// C-callable bridge matching `crcl_response_callback_t`. Same Unmanaged
/// borrow contract as `rclRequestCallbackBridge`.
private func rclResponseCallbackBridge(
    ctx: UnsafeMutableRawPointer?,
    sequenceNumber: Int64,
    buf: UnsafePointer<UInt8>?,
    len: Int
) {
    guard let ctx else { return }
    let clientContext = Unmanaged<RclServiceClientContext>.fromOpaque(ctx).takeUnretainedValue()

    let payload: Data
    if let buf, len > 0 {
        payload = Data(bytes: buf, count: len)
    } else {
        payload = Data()
    }

    clientContext.onResponse(sequenceNumber, payload)
}

/// Per-box lock serializes destroy vs. sendRequest / serverAvailable on the
/// same client pointer. Close contract mirrors `RclSubscriptionBox` exactly,
/// including the leak-on-failed-destroy behavior.
private final class RclServiceClientBox: RclClientHandle, @unchecked Sendable {
    private var ptr: OpaquePointer?
    private var contextBox: Unmanaged<RclServiceClientContext>?
    private let lock = NSLock()

    init(_ ptr: OpaquePointer, contextBox: Unmanaged<RclServiceClientContext>) {
        self.ptr = ptr
        self.contextBox = contextBox
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ptr != nil
    }

    func withPtr<R>(_ body: (OpaquePointer) -> R) -> R? {
        lock.lock()
        defer { lock.unlock() }
        guard let p = ptr else { return nil }
        return body(p)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        if let p = ptr {
            // crcl_client_destroy joins the wait thread before any fini, so
            // it blocks until any in-flight callback has returned.
            let rc = crcl_client_destroy(p)
            ptr = nil
            if rc < 0 {
                // Refused destroy — leak the retained handler context rather
                // than release it under a live thread.
                contextBox = nil
                return
            }
        }
        if let box = contextBox {
            box.release()
            contextBox = nil
        }
    }
}

// MARK: - Client

/// Concrete implementation of ``RclClientProtocol`` wrapping the `CRclBridge` C FFI.
///
/// Thread-safety: the `ctx` pointer is read/written under `lock`.
/// `crcl_context_create` runs outside the lock (one-time init); the guard rejects
/// a second `createContext` call with `alreadyConnected`. `destroyContext`
/// snapshots and nils `ctx` under lock, then calls `crcl_context_destroy` outside.
/// Publisher and subscription create/destroy delegate thread-safety to the
/// per-`RclPublisherBox` / per-`RclSubscriptionBox` locks, mirroring the
/// `DDSClient` pattern. The retained `Unmanaged<RclSubscriptionContext>`
/// holding the user handler is released only *after* `crcl_subscription_destroy`
/// returns — the C bridge joins the wait thread before any fini, so a racing
/// callback can never dereference a freed closure context.
public final class RclClient: RclClientProtocol, @unchecked Sendable {
    private var ctx: OpaquePointer?
    private let lock = NSLock()

    public init() {}

    package var isAvailable: Bool { true }

    package func createContext(domainId: Int32) throws {
        lock.lock()
        guard ctx == nil else {
            lock.unlock()
            throw TransportError.alreadyConnected
        }
        lock.unlock()
        guard let c = crcl_context_create(Int(domainId)) else {
            throw TransportError.connectionFailed(lastError())
        }
        lock.lock()
        ctx = c
        lock.unlock()
    }

    package func destroyContext() {
        lock.lock()
        let c = ctx
        ctx = nil
        lock.unlock()
        if let c { crcl_context_destroy(c) }
    }

    package func createNode(name: String, namespace: String) throws -> any RclNodeHandle {
        lock.lock()
        let c = ctx
        lock.unlock()
        guard let c else { throw TransportError.notConnected }
        guard let n = crcl_node_create(c, name, namespace) else {
            throw TransportError.connectionFailed(lastError())
        }
        return RclNodeBox(n)
    }

    package func destroyNode(_ node: any RclNodeHandle) {
        guard let b = node as? RclNodeBox else { return }
        crcl_node_destroy(b.ptr)
    }

    package func createPublisher(
        node: any RclNodeHandle, typeName: String, topic: String, qos: TransportQoS
    ) throws -> any RclPublisherHandle {
        guard let b = node as? RclNodeBox else {
            throw TransportError.publisherCreationFailed("invalid node handle")
        }
        let q = makeCrclQoS(qos)
        guard let p = crcl_publisher_create(b.ptr, typeName, topic, q) else {
            throw TransportError.publisherCreationFailed(lastError())
        }
        return RclPublisherBox(p)
    }

    package func createSubscription(
        node: any RclNodeHandle,
        typeName: String,
        topic: String,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data, UInt64) -> Void
    ) throws -> any RclSubscriptionHandle {
        guard let b = node as? RclNodeBox else {
            throw TransportError.subscriberCreationFailed("invalid node handle")
        }
        var q = makeCrclQoS(qos)

        let contextBox = Unmanaged.passRetained(RclSubscriptionContext(handler: handler))
        let contextPtr = UnsafeMutableRawPointer(contextBox.toOpaque())

        guard
            let s = crcl_subscription_create(
                b.ptr, typeName, topic, &q, rclTakeCallbackBridge, contextPtr)
        else {
            contextBox.release()
            throw TransportError.subscriberCreationFailed(lastError())
        }
        return RclSubscriptionBox(s, contextBox: contextBox)
    }

    package func destroySubscription(_ subscription: any RclSubscriptionHandle) {
        guard let box = subscription as? RclSubscriptionBox else { return }
        box.close()
    }

    package func createServiceServer(
        node: any RclNodeHandle,
        srvTypeName: String,
        serviceName: String,
        qos: TransportQoS,
        onRequest: @escaping @Sendable (Data, [UInt8]) -> Void
    ) throws -> any RclServiceHandle {
        guard let b = node as? RclNodeBox else {
            throw TransportError.subscriberCreationFailed("invalid node handle")
        }
        var q = makeCrclQoS(qos)

        let contextBox = Unmanaged.passRetained(RclServiceContext(onRequest: onRequest))
        let contextPtr = UnsafeMutableRawPointer(contextBox.toOpaque())

        guard
            let s = crcl_service_create(
                b.ptr, srvTypeName, serviceName, &q, rclRequestCallbackBridge, contextPtr)
        else {
            contextBox.release()
            throw TransportError.subscriberCreationFailed(lastError())
        }
        return RclServiceBox(s, contextBox: contextBox)
    }

    package func sendResponse(_ service: any RclServiceHandle, requestId: [UInt8], data: Data) throws {
        guard let box = service as? RclServiceBox else {
            throw TransportError.publishFailed("invalid service handle")
        }
        guard requestId.count == Int(CRCL_REQUEST_ID_SIZE) else {
            throw TransportError.publishFailed(
                "request id must be \(CRCL_REQUEST_ID_SIZE) bytes, got \(requestId.count)")
        }
        let rc: Int32? = requestId.withUnsafeBufferPointer { idBuf -> Int32? in
            data.withUnsafeBytes { raw -> Int32? in
                let base = raw.bindMemory(to: UInt8.self).baseAddress
                return box.withPtr { p in
                    crcl_service_send_response(p, idBuf.baseAddress, base, data.count)
                }
            }
        }
        guard let rc else { throw TransportError.sessionClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
    }

    package func destroyServiceServer(_ service: any RclServiceHandle) {
        guard let box = service as? RclServiceBox else { return }
        box.close()
    }

    package func createServiceClient(
        node: any RclNodeHandle,
        srvTypeName: String,
        serviceName: String,
        qos: TransportQoS,
        onResponse: @escaping @Sendable (Int64, Data) -> Void
    ) throws -> any RclClientHandle {
        guard let b = node as? RclNodeBox else {
            throw TransportError.subscriberCreationFailed("invalid node handle")
        }
        var q = makeCrclQoS(qos)

        let contextBox = Unmanaged.passRetained(RclServiceClientContext(onResponse: onResponse))
        let contextPtr = UnsafeMutableRawPointer(contextBox.toOpaque())

        guard
            let c = crcl_client_create(
                b.ptr, srvTypeName, serviceName, &q, rclResponseCallbackBridge, contextPtr)
        else {
            contextBox.release()
            throw TransportError.subscriberCreationFailed(lastError())
        }
        return RclServiceClientBox(c, contextBox: contextBox)
    }

    package func sendRequest(_ client: any RclClientHandle, data: Data) throws -> Int64 {
        guard let box = client as? RclServiceClientBox else {
            throw TransportError.publishFailed("invalid service client handle")
        }
        var seq: Int64 = 0
        let rc: Int32? = data.withUnsafeBytes { raw -> Int32? in
            let base = raw.bindMemory(to: UInt8.self).baseAddress
            return box.withPtr { p in
                crcl_client_send_request(p, base, data.count, &seq)
            }
        }
        guard let rc else { throw TransportError.sessionClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
        return seq
    }

    package func serverAvailable(_ client: any RclClientHandle) -> Bool {
        guard let box = client as? RclServiceClientBox else { return false }
        return box.withPtr { crcl_client_server_available($0) == 1 } ?? false
    }

    package func destroyServiceClient(_ client: any RclClientHandle) {
        guard let box = client as? RclServiceClientBox else { return }
        box.close()
    }

    package func publishSerialized(_ publisher: any RclPublisherHandle, data: Data) throws {
        guard let b = publisher as? RclPublisherBox else {
            throw TransportError.publishFailed("invalid publisher handle")
        }
        let rc: Int32? = data.withUnsafeBytes { raw -> Int32? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return b.withPtr { p in
                crcl_publish_serialized(p, base, data.count)
            }
        }
        guard let rc else { throw TransportError.publisherClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
    }

    private func makeCrclQoS(_ qos: TransportQoS) -> crcl_qos_t {
        var q = crcl_qos_t()
        q.reliability = qos.reliability == .reliable ? Int32(1) : Int32(0)
        q.durability = qos.durability == .transientLocal ? Int32(1) : Int32(0)
        switch qos.history {
        case .keepLast(let depth):
            q.history = Int32(0)
            q.depth = depth
        case .keepAll:
            q.history = Int32(1)
            q.depth = 0
        }
        return q
    }

    private func lastError() -> String { String(cString: crcl_last_error()) }
}
