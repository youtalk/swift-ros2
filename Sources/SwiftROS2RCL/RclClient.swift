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
            _ = crcl_subscription_destroy(p)
            ptr = nil
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
