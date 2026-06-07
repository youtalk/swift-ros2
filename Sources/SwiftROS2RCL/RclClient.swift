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
private final class RclPublisherBox: RclPublisherHandle, @unchecked Sendable {
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

// MARK: - Client

/// Concrete implementation of ``RclClientProtocol`` wrapping the `CRclBridge` C FFI.
///
/// Thread-safety: the client-level `NSLock` serializes `createContext` /
/// `destroyContext`. Publisher creation/destroy delegate thread-safety to the
/// per-`RclPublisherBox` lock, mirroring the `DDSClient` pattern.
public final class RclClient: RclClientProtocol, @unchecked Sendable {
    private var ctx: OpaquePointer?
    private let lock = NSLock()

    public init() {}

    package var isAvailable: Bool { true }

    package func createContext(domainId: Int32) throws {
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
            throw TransportError.publisherCreationFailed(lastError())
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
        guard let p = crcl_publisher_create(b.ptr, typeName, topic, q) else {
            throw TransportError.publisherCreationFailed(lastError())
        }
        return RclPublisherBox(p)
    }

    package func publishSerialized(_ publisher: any RclPublisherHandle, data: Data) throws {
        guard let b = publisher as? RclPublisherBox else {
            throw TransportError.publishFailed("invalid publisher handle")
        }
        let rc: Int32? = data.withUnsafeBytes { raw in
            b.withPtr { p in
                crcl_publish_serialized(
                    p, raw.bindMemory(to: UInt8.self).baseAddress, data.count)
            }
        }
        guard let rc else { throw TransportError.publisherClosed }
        if rc != 0 { throw TransportError.publishFailed(lastError()) }
    }

    private func lastError() -> String { String(cString: crcl_last_error()) }
}
