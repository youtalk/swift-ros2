// RclClient.swift
// Concrete RclClientProtocol over the CRclBridge C FFI. Apple-only, gated.

import CDDSBridge
import CRclBridge
import Foundation
import SwiftROS2Transport
import SwiftROS2Wire

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

/// Route-(b) publisher handle for non-bundled (registry-miss) types. Wraps a
/// `CDDSBridge` raw-CDR writer on a sibling CycloneDDS participant — published
/// below rmw, so it is outside rcl's entity graph but interoperable with any
/// ROS 2 subscriber by topic name + DDS type name. The same machinery the
/// pure-Swift DDS backend ships. Per-box lock serializes destroy vs. write.
final class RclRawPublisherBox: RclPublisherHandle, @unchecked Sendable {
    private let writer: OpaquePointer
    private let lock = NSLock()
    private var closed = false
    init(writer: OpaquePointer) { self.writer = writer }
    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
    }
    func close() {
        lock.lock()
        defer { lock.unlock() }
        if !closed {
            closed = true
            dds_bridge_destroy_writer(writer)
        }
    }
    /// Write pre-serialized CDR below rmw. Returns the dds_bridge_write_raw_cdr
    /// status (0 success, negative failure), or nil if the box is already
    /// closed. Locked so a concurrent close() cannot free the writer mid-write.
    func write(_ data: Data) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return nil }
        return data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Int32 in
            guard let base = buf.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            // 0 ⇒ CycloneDDS source-stamps the sample.
            return dds_bridge_write_raw_cdr(writer, base, data.count, 0)
        }
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

// MARK: - Action server

/// Retained by `RclActionServerBox.contextBox` while the action server is
/// alive. Same `@unchecked Sendable` justification as `RclSubscriptionContext`:
/// the only state is an immutable `Sendable` callback bag.
private final class RclActionServerContext: @unchecked Sendable {
    let callbacks: RclActionServerCallbacks
    init(callbacks: RclActionServerCallbacks) {
        self.callbacks = callbacks
    }
}

/// C-callable bridge matching `crcl_action_server_callback_t`. Same Unmanaged
/// borrow contract as `rclRequestCallbackBridge`; the `role` discriminates the
/// three request kinds.
private func rclActionServerCallbackBridge(
    ctx: UnsafeMutableRawPointer?,
    role: Int32,
    requestId: UnsafePointer<UInt8>?,
    buf: UnsafePointer<UInt8>?,
    len: Int
) {
    guard let ctx, let requestId else { return }
    let serverContext = Unmanaged<RclActionServerContext>.fromOpaque(ctx).takeUnretainedValue()

    let blob = [UInt8](UnsafeBufferPointer(start: requestId, count: Int(CRCL_REQUEST_ID_SIZE)))
    let payload: Data
    if let buf, len > 0 {
        payload = Data(bytes: buf, count: len)
    } else {
        payload = Data()
    }

    switch role {
    case CRCL_ACTION_SERVER_GOAL_REQUEST:
        serverContext.callbacks.onGoalRequest(payload, blob)
    case CRCL_ACTION_SERVER_CANCEL_REQUEST:
        serverContext.callbacks.onCancelRequest(payload, blob)
    case CRCL_ACTION_SERVER_RESULT_REQUEST:
        serverContext.callbacks.onResultRequest(payload, blob)
    default:
        break
    }
}

/// Per-box lock serializes destroy vs. send / publish / goal bookkeeping on
/// the same action server pointer. Close contract mirrors `RclServiceBox`
/// exactly, including the leak-on-failed-destroy behavior.
private final class RclActionServerBox: RclActionServerHandle, @unchecked Sendable {
    private var ptr: OpaquePointer?
    private var contextBox: Unmanaged<RclActionServerContext>?
    private let lock = NSLock()

    init(_ ptr: OpaquePointer, contextBox: Unmanaged<RclActionServerContext>) {
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
            // crcl_action_server_destroy joins the wait thread before any
            // fini, so it blocks until any in-flight callback has returned.
            let rc = crcl_action_server_destroy(p)
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

// MARK: - Action client

/// Retained by `RclActionClientBox.contextBox` while the action client is alive.
private final class RclActionClientContext: @unchecked Sendable {
    let callbacks: RclActionClientCallbacks
    init(callbacks: RclActionClientCallbacks) {
        self.callbacks = callbacks
    }
}

/// Parse the flattened status records the C bridge emits for
/// CRCL_ACTION_CLIENT_STATUS (see CRCL_GOAL_STATUS_RECORD_SIZE).
private func rclParseStatusRecords(buf: UnsafePointer<UInt8>?, len: Int) -> [RclGoalStatusRecord] {
    let stride = Int(CRCL_GOAL_STATUS_RECORD_SIZE)
    guard let buf, len >= stride else { return [] }
    let count = len / stride
    var out: [RclGoalStatusRecord] = []
    out.reserveCapacity(count)
    for i in 0..<count {
        let rec = buf + i * stride
        let goalId = [UInt8](UnsafeBufferPointer(start: rec, count: 16))
        var sec: UInt32 = 0
        var nsec: UInt32 = 0
        for b in 0..<4 {
            sec |= UInt32(rec[16 + b]) << (8 * b)
            nsec |= UInt32(rec[20 + b]) << (8 * b)
        }
        out.append(
            RclGoalStatusRecord(
                goalId: goalId,
                stampSec: Int32(bitPattern: sec),
                stampNanosec: nsec,
                status: Int8(bitPattern: rec[24])
            ))
    }
    return out
}

/// C-callable bridge matching `crcl_action_client_callback_t`. Same Unmanaged
/// borrow contract as `rclResponseCallbackBridge`.
private func rclActionClientCallbackBridge(
    ctx: UnsafeMutableRawPointer?,
    role: Int32,
    sequenceNumber: Int64,
    buf: UnsafePointer<UInt8>?,
    len: Int
) {
    guard let ctx else { return }
    let clientContext = Unmanaged<RclActionClientContext>.fromOpaque(ctx).takeUnretainedValue()

    if role == CRCL_ACTION_CLIENT_STATUS {
        clientContext.callbacks.onStatus(rclParseStatusRecords(buf: buf, len: len))
        return
    }

    let payload: Data
    if let buf, len > 0 {
        payload = Data(bytes: buf, count: len)
    } else {
        payload = Data()
    }

    switch role {
    case CRCL_ACTION_CLIENT_GOAL_RESPONSE:
        clientContext.callbacks.onGoalResponse(sequenceNumber, payload)
    case CRCL_ACTION_CLIENT_CANCEL_RESPONSE:
        clientContext.callbacks.onCancelResponse(sequenceNumber, payload)
    case CRCL_ACTION_CLIENT_RESULT_RESPONSE:
        clientContext.callbacks.onResultResponse(sequenceNumber, payload)
    case CRCL_ACTION_CLIENT_FEEDBACK:
        clientContext.callbacks.onFeedback(payload)
    default:
        break
    }
}

/// Per-box lock serializes destroy vs. sends / availability checks on the
/// same action client pointer. Close contract mirrors `RclServiceClientBox`
/// exactly, including the leak-on-failed-destroy behavior.
private final class RclActionClientBox: RclActionClientHandle, @unchecked Sendable {
    private var ptr: OpaquePointer?
    private var contextBox: Unmanaged<RclActionClientContext>?
    private let lock = NSLock()

    init(_ ptr: OpaquePointer, contextBox: Unmanaged<RclActionClientContext>) {
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
            // crcl_action_client_destroy joins the wait thread before any
            // fini, so it blocks until any in-flight callback has returned.
            let rc = crcl_action_client_destroy(p)
            ptr = nil
            if rc < 0 {
                // Refused destroy — leak the retained handler context.
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
    /// Serializes every CYCLONEDDS_URI read/write across all RclClient instances
    /// in the process. CYCLONEDDS_URI is a single process-global slot and
    /// setenv/getenv are not mutually thread-safe, so the save+export and the
    /// read+restore must each run as one critical section under a SHARED lock —
    /// the per-instance `lock` cannot guard a process-global. (Concurrent
    /// contexts still share that one env slot; rmw_cyclonedds reads it once at
    /// first-participant creation, so this serializes the mutations rather than
    /// giving each context an independent value.)
    private static let envLock = NSLock()
    /// Saved CYCLONEDDS_URI to restore on destroyContext. Guarded by `envLock`.
    /// Outer optional = "we saved"; inner = "was previously set".
    private var priorCyclonedDDSURI: String??
    /// Route-(b) sibling-participant session (`bridge_dds_session_t*`), created
    /// lazily on the first non-bundled publisher and matched to the rcl
    /// context's discovery. nil until then.
    private var rawSession: OpaquePointer?
    /// Discovery inputs captured at createContext so the route-(b) raw session
    /// discovers identically to the rcl context.
    private var ctxDomainId: Int32 = 0
    private var ctxUnicastPeerAddresses: [String] = []
    private var ctxNetworkInterface: String?

    public init() {}

    package var isAvailable: Bool { true }

    /// Build the CycloneDDS domain-config XML via the SHARED CDDSBridge builder
    /// (byte-identical to the wire DDS path → Axis-3 parity). Pure: no env, no
    /// DDS runtime. Returns nil on OOM. `package` so SwiftROS2RCLTests can assert
    /// the XML shape without starting rmw.
    package func makeDiscoveryURIXML(
        domainId: Int32, unicastPeerAddresses: [String], networkInterface: String?
    ) -> String? {
        var cConfig = bridge_discovery_config_t()
        cConfig.mode =
            unicastPeerAddresses.isEmpty ? BRIDGE_DISCOVERY_MULTICAST : BRIDGE_DISCOVERY_UNICAST
        var peerCStrings: [UnsafeMutablePointer<CChar>?] = unicastPeerAddresses.map { strdup($0) }
        peerCStrings.append(nil)
        let peersPtr = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(
            capacity: peerCStrings.count)
        defer {
            for s in peerCStrings where s != nil { free(s) }
            peersPtr.deallocate()
        }
        for (i, s) in peerCStrings.enumerated() { peersPtr[i] = s.map { UnsafePointer($0) } }
        if !unicastPeerAddresses.isEmpty {
            cConfig.unicast_peers = peersPtr
            cConfig.peer_count = Int32(unicastPeerAddresses.count)
        }
        var interfaceCString: UnsafeMutablePointer<CChar>?
        if let networkInterface {
            interfaceCString = strdup(networkInterface)
            cConfig.network_interface = UnsafePointer(interfaceCString)
        }
        defer { if let s = interfaceCString { free(s) } }
        guard let xmlPtr = dds_bridge_build_domain_config_xml(domainId, &cConfig) else { return nil }
        defer { dds_bridge_free_string(xmlPtr) }
        return String(cString: xmlPtr)
    }

    /// Export the discovery XML as CYCLONEDDS_URI (saving the prior value) when
    /// discovery is non-default. Returns true if it set the env. rmw_cyclonedds
    /// reads CYCLONEDDS_URI once, at the first participant; pair with
    /// restoreDiscoveryEnv() on teardown or on a failed createContext.
    package func applyDiscoveryEnv(
        domainId: Int32, unicastPeerAddresses: [String], networkInterface: String?
    ) -> Bool {
        guard !unicastPeerAddresses.isEmpty || networkInterface != nil,
            let xml = makeDiscoveryURIXML(
                domainId: domainId, unicastPeerAddresses: unicastPeerAddresses,
                networkInterface: networkInterface)
        else { return false }
        // Save + export under the shared lock as one critical section: getenv and
        // setenv must not interleave with another instance's, or the saved value
        // and the live env desynchronize.
        Self.envLock.lock()
        defer { Self.envLock.unlock() }
        // Wrap in Optional(...) so a previously-UNSET env becomes .some(.none)
        // ("saved, was unset") rather than collapsing to .none ("never saved") —
        // restoreDiscoveryEnv relies on that distinction to unset vs. no-op.
        priorCyclonedDDSURI = Optional(getenv("CYCLONEDDS_URI").map { String(cString: $0) })
        setenv("CYCLONEDDS_URI", xml, 1)
        return true
    }

    /// Restore CYCLONEDDS_URI to its pre-applyDiscoveryEnv value (unset it if it
    /// was previously unset). Idempotent: a no-op when nothing was saved.
    package func restoreDiscoveryEnv() {
        // Read + restore under the shared lock as one critical section (see
        // applyDiscoveryEnv): the saved slot and the live env move together.
        Self.envLock.lock()
        defer { Self.envLock.unlock() }
        guard let prior = priorCyclonedDDSURI else { return }
        priorCyclonedDDSURI = nil
        if let p = prior { setenv("CYCLONEDDS_URI", p, 1) } else { unsetenv("CYCLONEDDS_URI") }
    }

    package func createContext(
        domainId: Int32, unicastPeerAddresses: [String], networkInterface: String?
    ) throws {
        lock.lock()
        guard ctx == nil else {
            lock.unlock()
            throw TransportError.alreadyConnected
        }
        // Capture the discovery inputs so a later route-(b) raw session matches
        // the rcl context's domain + peers + interface.
        ctxDomainId = domainId
        ctxUnicastPeerAddresses = unicastPeerAddresses
        ctxNetworkInterface = networkInterface
        lock.unlock()
        // rmw_cyclonedds reads CYCLONEDDS_URI once, at the first participant. Only
        // export when discovery is non-default; restore the prior value on
        // teardown OR if context creation fails (so a failed open doesn't leak it).
        let appliedDiscoveryEnv = applyDiscoveryEnv(
            domainId: domainId, unicastPeerAddresses: unicastPeerAddresses,
            networkInterface: networkInterface)
        guard let c = crcl_context_create(Int(domainId)) else {
            if appliedDiscoveryEnv { restoreDiscoveryEnv() }
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
        let rs = rawSession
        rawSession = nil
        lock.unlock()
        if let rs { dds_bridge_destroy_session(rs) }
        if let c { crcl_context_destroy(c) }
        restoreDiscoveryEnv()
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
        node: any RclNodeHandle, typeName: String, typeHash: String?, topic: String,
        qos: TransportQoS
    ) throws -> any RclPublisherHandle {
        guard let b = node as? RclNodeBox else {
            throw TransportError.publisherCreationFailed("invalid node handle")
        }
        // Discriminate a registry miss (unbundled type → route (b)) from a real
        // rmw failure. crcl_publisher_create returns NULL for BOTH the
        // "unsupported type" registry gate AND genuine failures (invalid topic,
        // rcl_publisher_init error, OOM, bad node); it gates on the same
        // crcl_marshal_resolve_typesupport this checks. So: bundled type → a nil
        // is a real error, surface it; only an actual registry miss falls back.
        if crcl_marshal_resolve_typesupport(typeName) != nil {
            let q = makeCrclQoS(qos)
            guard let p = crcl_publisher_create(b.ptr, typeName, topic, q) else {
                throw TransportError.publisherCreationFailed(lastError())
            }
            return RclPublisherBox(p)
        }
        // Registry miss (unbundled type) → route-(b) raw-CDR writer below rmw.
        return try createRawWriterPublisher(
            typeName: typeName, typeHash: typeHash, topic: topic, qos: qos)
    }

    /// Lazily create (or reuse) the route-(b) sibling CycloneDDS participant,
    /// matching the rcl context's discovery (mirrors `makeDiscoveryURIXML`'s
    /// `bridge_discovery_config_t` marshalling, but calls
    /// `dds_bridge_create_session` instead of building XML).
    private func ensureRawSession() throws -> OpaquePointer {
        lock.lock()
        if let s = rawSession {
            lock.unlock()
            return s
        }
        let domain = ctxDomainId
        let peers = ctxUnicastPeerAddresses
        let iface = ctxNetworkInterface
        lock.unlock()

        var cConfig = bridge_discovery_config_t()
        cConfig.mode = peers.isEmpty ? BRIDGE_DISCOVERY_MULTICAST : BRIDGE_DISCOVERY_UNICAST
        var peerCStrings: [UnsafeMutablePointer<CChar>?] = peers.map { strdup($0) }
        peerCStrings.append(nil)
        let peersPtr = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(
            capacity: peerCStrings.count)
        defer {
            for s in peerCStrings where s != nil { free(s) }
            peersPtr.deallocate()
        }
        for (i, s) in peerCStrings.enumerated() { peersPtr[i] = s.map { UnsafePointer($0) } }
        if !peers.isEmpty {
            cConfig.unicast_peers = peersPtr
            cConfig.peer_count = Int32(peers.count)
        }
        var ifaceC: UnsafeMutablePointer<CChar>?
        if let iface {
            ifaceC = strdup(iface)
            cConfig.network_interface = UnsafePointer(ifaceC)
        }
        defer { if let s = ifaceC { free(s) } }

        guard let s = dds_bridge_create_session(domain, &cConfig) else {
            throw TransportError.publisherCreationFailed(
                "route-b raw session create failed: "
                    + "\(String(cString: dds_bridge_get_last_error()))")
        }
        lock.lock()
        // Re-check: another thread may have created the session while we were
        // unlocked building/creating ours. Keep the winner and destroy our
        // redundant one — overwriting rawSession here would leak a participant.
        if let existing = rawSession {
            lock.unlock()
            dds_bridge_destroy_session(s)
            return existing
        }
        rawSession = s
        lock.unlock()
        return s
    }

    /// Open a route-(b) raw-CDR writer for an unbundled type: a sibling
    /// participant on the context domain, keyed by the DDS topic + DDS type
    /// name (via SwiftROS2Wire) + USER_DATA typehash. rmw_cyclonedds does no
    /// XTypes checking, so a real ROS 2 subscriber matches on topic-name +
    /// DDS-type-name string.
    private func createRawWriterPublisher(
        typeName: String, typeHash: String?, topic: String, qos: TransportQoS
    ) throws -> any RclPublisherHandle {
        let session = try ensureRawSession()
        let ddsTopic = DDSWireCodec().ddsTopic(from: topic)  // "rt/<topic>"
        let ddsType = TypeNameConverter.toDDSTypeName(typeName)  // "<pkg>::msg::dds_::<Type>_"
        let userData: String? = typeHash.map { "typehash=\($0);" }
        // Honour the caller's QoS — a nil here makes the C bridge default to
        // best-effort/volatile (BRIDGE_QOS_SENSOR_DATA), silently dropping a
        // reliable/transient-local request the bundled (route-a) path would keep.
        var cQos = makeBridgeQoS(qos)
        let writer: OpaquePointer? = ddsTopic.withCString { t in
            ddsType.withCString { ty in
                if let ud = userData {
                    return ud.withCString {
                        dds_bridge_create_raw_writer(session, t, ty, &cQos, $0)
                    }
                }
                return dds_bridge_create_raw_writer(session, t, ty, &cQos, nil)
            }
        }
        guard let w = writer else {
            throw TransportError.publisherCreationFailed(
                "route-b raw writer create failed for \(typeName): "
                    + "\(String(cString: dds_bridge_get_last_error()))")
        }
        return RclRawPublisherBox(writer: w)
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

    // MARK: Actions (M8)

    package func createActionServer(
        node: any RclNodeHandle,
        actionTypeName: String,
        actionName: String,
        qos: TransportQoS,
        callbacks: RclActionServerCallbacks
    ) throws -> any RclActionServerHandle {
        guard let b = node as? RclNodeBox else {
            throw TransportError.subscriberCreationFailed("invalid node handle")
        }
        var q = makeCrclQoS(qos)

        let contextBox = Unmanaged.passRetained(RclActionServerContext(callbacks: callbacks))
        let contextPtr = UnsafeMutableRawPointer(contextBox.toOpaque())

        guard
            let s = crcl_action_server_create(
                b.ptr, actionTypeName, actionName, &q, rclActionServerCallbackBridge, contextPtr)
        else {
            contextBox.release()
            throw TransportError.subscriberCreationFailed(lastError())
        }
        return RclActionServerBox(s, contextBox: contextBox)
    }

    /// Shared body for the three action-server response sends.
    private func sendActionResponse(
        _ server: any RclActionServerHandle, requestId: [UInt8], data: Data,
        send: (OpaquePointer, UnsafePointer<UInt8>?, UnsafePointer<UInt8>?, Int) -> Int32
    ) throws {
        guard let box = server as? RclActionServerBox else {
            throw TransportError.publishFailed("invalid action server handle")
        }
        guard requestId.count == Int(CRCL_REQUEST_ID_SIZE) else {
            throw TransportError.publishFailed(
                "request id must be \(CRCL_REQUEST_ID_SIZE) bytes, got \(requestId.count)")
        }
        let rc: Int32? = requestId.withUnsafeBufferPointer { idBuf -> Int32? in
            data.withUnsafeBytes { raw -> Int32? in
                let base = raw.bindMemory(to: UInt8.self).baseAddress
                return box.withPtr { p in
                    send(p, idBuf.baseAddress, base, data.count)
                }
            }
        }
        guard let rc else { throw TransportError.sessionClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
    }

    package func sendGoalResponse(
        _ server: any RclActionServerHandle, requestId: [UInt8], data: Data
    ) throws {
        try sendActionResponse(server, requestId: requestId, data: data) {
            crcl_action_server_send_goal_response($0, $1, $2, $3)
        }
    }

    package func sendCancelResponse(
        _ server: any RclActionServerHandle, requestId: [UInt8], data: Data
    ) throws {
        try sendActionResponse(server, requestId: requestId, data: data) {
            crcl_action_server_send_cancel_response($0, $1, $2, $3)
        }
    }

    package func sendResultResponse(
        _ server: any RclActionServerHandle, requestId: [UInt8], data: Data
    ) throws {
        try sendActionResponse(server, requestId: requestId, data: data) {
            crcl_action_server_send_result_response($0, $1, $2, $3)
        }
    }

    package func publishActionFeedback(_ server: any RclActionServerHandle, data: Data) throws {
        guard let box = server as? RclActionServerBox else {
            throw TransportError.publishFailed("invalid action server handle")
        }
        let rc: Int32? = data.withUnsafeBytes { raw -> Int32? in
            let base = raw.bindMemory(to: UInt8.self).baseAddress
            return box.withPtr { p in
                crcl_action_server_publish_feedback(p, base, data.count)
            }
        }
        guard let rc else { throw TransportError.publisherClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
    }

    package func publishActionStatus(_ server: any RclActionServerHandle) throws {
        guard let box = server as? RclActionServerBox else {
            throw TransportError.publishFailed("invalid action server handle")
        }
        let rc: Int32? = box.withPtr { crcl_action_server_publish_status($0) }
        guard let rc else { throw TransportError.publisherClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
    }

    package func acceptGoal(
        _ server: any RclActionServerHandle, goalId: [UInt8], stampSec: Int32,
        stampNanosec: UInt32
    ) throws {
        guard let box = server as? RclActionServerBox else {
            throw TransportError.publishFailed("invalid action server handle")
        }
        guard goalId.count == 16 else {
            throw TransportError.publishFailed("goal id must be 16 bytes, got \(goalId.count)")
        }
        let rc: Int32? = goalId.withUnsafeBufferPointer { idBuf -> Int32? in
            box.withPtr { p in
                crcl_action_server_accept_goal(p, idBuf.baseAddress, stampSec, stampNanosec)
            }
        }
        guard let rc else { throw TransportError.sessionClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
    }

    package func updateGoalState(
        _ server: any RclActionServerHandle, goalId: [UInt8], event: RclGoalEvent
    ) throws {
        guard let box = server as? RclActionServerBox else {
            throw TransportError.publishFailed("invalid action server handle")
        }
        guard goalId.count == 16 else {
            throw TransportError.publishFailed("goal id must be 16 bytes, got \(goalId.count)")
        }
        let rc: Int32? = goalId.withUnsafeBufferPointer { idBuf -> Int32? in
            box.withPtr { p in
                crcl_action_server_update_goal_state(p, idBuf.baseAddress, event.rawValue)
            }
        }
        guard let rc else { throw TransportError.sessionClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
    }

    package func notifyGoalDone(_ server: any RclActionServerHandle) throws {
        guard let box = server as? RclActionServerBox else {
            throw TransportError.publishFailed("invalid action server handle")
        }
        let rc: Int32? = box.withPtr { crcl_action_server_notify_goal_done($0) }
        guard let rc else { throw TransportError.sessionClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
    }

    package func destroyActionServer(_ server: any RclActionServerHandle) {
        guard let box = server as? RclActionServerBox else { return }
        box.close()
    }

    package func createActionClient(
        node: any RclNodeHandle,
        actionTypeName: String,
        actionName: String,
        qos: TransportQoS,
        callbacks: RclActionClientCallbacks
    ) throws -> any RclActionClientHandle {
        guard let b = node as? RclNodeBox else {
            throw TransportError.subscriberCreationFailed("invalid node handle")
        }
        var q = makeCrclQoS(qos)

        let contextBox = Unmanaged.passRetained(RclActionClientContext(callbacks: callbacks))
        let contextPtr = UnsafeMutableRawPointer(contextBox.toOpaque())

        guard
            let c = crcl_action_client_create(
                b.ptr, actionTypeName, actionName, &q, rclActionClientCallbackBridge, contextPtr)
        else {
            contextBox.release()
            throw TransportError.subscriberCreationFailed(lastError())
        }
        return RclActionClientBox(c, contextBox: contextBox)
    }

    /// Shared body for the three action-client request sends.
    private func sendActionRequest(
        _ client: any RclActionClientHandle, data: Data,
        send: (OpaquePointer, UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<Int64>) -> Int32
    ) throws -> Int64 {
        guard let box = client as? RclActionClientBox else {
            throw TransportError.publishFailed("invalid action client handle")
        }
        var seq: Int64 = 0
        let rc: Int32? = data.withUnsafeBytes { raw -> Int32? in
            let base = raw.bindMemory(to: UInt8.self).baseAddress
            return box.withPtr { p in
                send(p, base, data.count, &seq)
            }
        }
        guard let rc else { throw TransportError.sessionClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
        return seq
    }

    package func sendGoalRequest(_ client: any RclActionClientHandle, data: Data) throws -> Int64 {
        try sendActionRequest(client, data: data) {
            crcl_action_client_send_goal_request($0, $1, $2, $3)
        }
    }

    package func sendCancelRequest(_ client: any RclActionClientHandle, data: Data) throws -> Int64 {
        try sendActionRequest(client, data: data) {
            crcl_action_client_send_cancel_request($0, $1, $2, $3)
        }
    }

    package func sendResultRequest(_ client: any RclActionClientHandle, data: Data) throws -> Int64 {
        try sendActionRequest(client, data: data) {
            crcl_action_client_send_result_request($0, $1, $2, $3)
        }
    }

    package func actionServerAvailable(_ client: any RclActionClientHandle) -> Bool {
        guard let box = client as? RclActionClientBox else { return false }
        return box.withPtr { crcl_action_client_server_available($0) == 1 } ?? false
    }

    package func destroyActionClient(_ client: any RclActionClientHandle) {
        guard let box = client as? RclActionClientBox else { return }
        box.close()
    }

    package func publishSerialized(_ publisher: any RclPublisherHandle, data: Data) throws {
        // Route-(b) raw-CDR writer (unbundled type) — publish below rmw. Surface
        // a write failure the same way the typed path does, instead of reporting
        // success when nothing went on the wire.
        if let raw = publisher as? RclRawPublisherBox {
            guard let rc = raw.write(data) else { throw TransportError.publisherClosed }
            if rc != 0 {
                throw TransportError.publishFailed(String(cString: dds_bridge_get_last_error()))
            }
            return
        }
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

    /// Map TransportQoS to the CDDSBridge config used by the route-(b) raw
    /// writer (mirrors the pure-Swift DDS backend's QoS marshalling), so an
    /// unbundled-type publisher honours the same reliability/durability/history
    /// knobs as a bundled one instead of falling back to sensor-data defaults.
    /// `package` so SwiftROS2RCLTests can assert the mapping without rmw.
    package func makeBridgeQoS(_ qos: TransportQoS) -> bridge_qos_config_t {
        var c = bridge_qos_config_t()
        c.reliability =
            qos.reliability == .reliable ? BRIDGE_RELIABILITY_RELIABLE : BRIDGE_RELIABILITY_BEST_EFFORT
        c.durability =
            qos.durability == .transientLocal ? BRIDGE_DURABILITY_TRANSIENT_LOCAL : BRIDGE_DURABILITY_VOLATILE
        switch qos.history {
        case .keepLast(let depth):
            c.history_kind = BRIDGE_HISTORY_KEEP_LAST
            c.history_depth = Int32(depth)
        case .keepAll:
            c.history_kind = BRIDGE_HISTORY_KEEP_ALL
            c.history_depth = 0
        }
        return c
    }

    private func lastError() -> String { String(cString: crcl_last_error()) }
}
