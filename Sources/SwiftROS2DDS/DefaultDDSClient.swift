// DefaultDDSClient.swift
// Default implementation of DDSClientProtocol using the CDDSBridge C FFI.

import Foundation
import CDDSBridge
import SwiftROS2Transport

// MARK: - Writer handle

private final class DDSWriterHandleBox: DDSWriterHandle {
    private var writer: OpaquePointer?

    var isActive: Bool {
        guard let w = writer else { return false }
        return dds_bridge_writer_is_active(w)
    }

    init(_ writer: OpaquePointer) {
        self.writer = writer
    }

    func close() {
        if let w = writer {
            dds_bridge_destroy_writer(w)
            writer = nil
        }
    }

    var raw: OpaquePointer? { writer }
}

// MARK: - DefaultDDSClient

/// Thread-safety: internal `NSLock` serializes `createSession` / `destroySession` /
/// `isConnected` / `getSessionId` / `createRawWriter`. `writeRawCDR` and
/// `destroyWriter` are intentionally lock-free — CycloneDDS writer operations are
/// thread-safe, and taking the lock on the publish hot path would serialize all
/// writers. Callers must ensure writers outlive the session.
public final class DefaultDDSClient: DDSClientProtocol {
    private var session: OpaquePointer?
    private let lock = NSLock()

    public init() {}

    public var isAvailable: Bool {
        dds_bridge_is_available()
    }

    public func createSession(
        domainId: Int32,
        discoveryConfig: DDSBridgeDiscoveryConfig
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard session == nil else {
            throw DDSError.sessionCreationFailed("session already exists")
        }

        guard dds_bridge_is_available() else {
            throw DDSError.notAvailable
        }

        var cConfig = bridge_discovery_config_t()
        switch discoveryConfig.mode {
        case .multicast: cConfig.mode = BRIDGE_DISCOVERY_MULTICAST
        case .unicast:   cConfig.mode = BRIDGE_DISCOVERY_UNICAST
        case .hybrid:    cConfig.mode = BRIDGE_DISCOVERY_HYBRID
        }

        // Build peer C-string array
        var peerCStrings: [UnsafeMutablePointer<CChar>?] = discoveryConfig.unicastPeers.map { strdup($0) }
        peerCStrings.append(nil) // NULL-terminator for C array

        let peersPtr = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: peerCStrings.count)
        defer {
            // Free peer strings + pointer array once dds_bridge_create_session returns
            for s in peerCStrings where s != nil {
                free(s)
            }
            peersPtr.deallocate()
        }
        for (i, s) in peerCStrings.enumerated() {
            peersPtr[i] = s.map { UnsafePointer($0) }
        }
        if !discoveryConfig.unicastPeers.isEmpty {
            cConfig.unicast_peers = peersPtr
            cConfig.peer_count = Int32(discoveryConfig.unicastPeers.count)
        }

        var interfaceCString: UnsafeMutablePointer<CChar>?
        if let ifaceName = discoveryConfig.networkInterface {
            interfaceCString = strdup(ifaceName)
            cConfig.network_interface = UnsafePointer(interfaceCString)
        }
        defer {
            if let s = interfaceCString { free(s) }
        }

        guard let newSession = dds_bridge_create_session(domainId, &cConfig) else {
            let msg = String(cString: dds_bridge_get_last_error())
            throw DDSError.sessionCreationFailed(msg)
        }
        session = newSession
    }

    public func destroySession() throws {
        lock.lock()
        defer { lock.unlock() }

        guard let s = session else { return }
        dds_bridge_destroy_session(s)
        session = nil
    }

    public func isConnected() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let s = session else { return false }
        return dds_bridge_session_is_connected(s)
    }

    public func getSessionId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let s = session else { return nil }
        var buf = [CChar](repeating: 0, count: 33)
        guard dds_bridge_get_session_id(s, &buf, 33) == 0 else { return nil }
        return String(cString: buf)
    }

    public func createRawWriter(
        topicName: String,
        typeName: String,
        qos: DDSBridgeQoSConfig,
        userData: String?
    ) throws -> any DDSWriterHandle {
        lock.lock()
        defer { lock.unlock() }

        guard let s = session else {
            throw DDSError.notConnected
        }

        var cQos = bridge_qos_config_t()
        cQos.reliability = qos.reliability == .reliable ? BRIDGE_RELIABILITY_RELIABLE : BRIDGE_RELIABILITY_BEST_EFFORT
        cQos.durability = qos.durability == .transientLocal ? BRIDGE_DURABILITY_TRANSIENT_LOCAL : BRIDGE_DURABILITY_VOLATILE
        cQos.history_kind = qos.historyKind == .keepAll ? BRIDGE_HISTORY_KEEP_ALL : BRIDGE_HISTORY_KEEP_LAST
        cQos.history_depth = qos.historyDepth

        let writerOrNil: OpaquePointer? = topicName.withCString { topicCStr in
            typeName.withCString { typeCStr in
                if let userData = userData {
                    return userData.withCString { userDataCStr in
                        dds_bridge_create_raw_writer(s, topicCStr, typeCStr, &cQos, userDataCStr)
                    }
                } else {
                    return dds_bridge_create_raw_writer(s, topicCStr, typeCStr, &cQos, nil)
                }
            }
        }

        guard let writer = writerOrNil else {
            let msg = String(cString: dds_bridge_get_last_error())
            throw DDSError.writerCreationFailed(msg)
        }
        return DDSWriterHandleBox(writer)
    }

    public func writeRawCDR(
        writer: any DDSWriterHandle,
        data: Data,
        timestamp: UInt64
    ) throws {
        guard let box = writer as? DDSWriterHandleBox, let raw = box.raw else {
            throw DDSError.writeFailed("foreign or closed DDS writer handle")
        }
        let result: Int32 = data.withUnsafeBytes { buf -> Int32 in
            guard let ptr = buf.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return dds_bridge_write_raw_cdr(raw, ptr, data.count, timestamp)
        }
        if result != 0 {
            let msg = String(cString: dds_bridge_get_last_error())
            throw DDSError.writeFailed("dds_bridge_write_raw_cdr=\(result): \(msg)")
        }
    }

    public func destroyWriter(_ writer: any DDSWriterHandle) {
        guard let box = writer as? DDSWriterHandleBox else { return }
        box.close()
    }
}
