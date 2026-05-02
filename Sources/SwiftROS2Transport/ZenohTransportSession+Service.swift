// ZenohTransportSession+Service.swift
// Service Server / Client implementation for the Zenoh transport.
//
// `rmw_zenoh_cpp` models a ROS 2 service as a Zenoh queryable on the request
// key expression. The server declares a queryable; the client issues a `get`
// against the same key expression with the request CDR as payload. The first
// reply (success or error) resolves the call.
//
// The wire payload on each side is the raw user CDR (no `RMWRequestId`
// prefix) — Zenoh handles request / reply correlation natively.
//
// Liveliness tokens (`SS` / `SC`) are not declared yet — declaring the
// queryable itself makes the service discoverable via the Zenoh admin
// space, which is sufficient for round-trip operation. Adding explicit
// `SS` / `SC` liveliness tokens is future work.

import Foundation
import SwiftROS2Wire

extension ZenohTransportSession {
    public func createServiceServer(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS,
        handler: @escaping @Sendable (Data) async throws -> Data
    ) throws -> any TransportService {
        guard !name.isEmpty else {
            throw TransportError.invalidConfiguration("Service name cannot be empty")
        }
        guard !serviceTypeName.isEmpty else {
            throw TransportError.invalidConfiguration("Service type name cannot be empty")
        }
        guard isConnected else {
            throw TransportError.notConnected
        }
        guard let cfg = config else {
            throw TransportError.notConnected
        }

        let codec = ZenohWireCodec(distro: resolvedWireMode ?? .jazzy)
        let keyExpr = codec.makeServiceKeyExpr(
            domainId: cfg.domainId,
            namespace: extractNamespace(from: name),
            serviceName: extractTopicName(from: name),
            serviceTypeName: serviceTypeName,
            requestTypeHash: requestTypeHash
        )

        let server = ZenohTransportServiceServerImpl(
            name: name,
            keyExpr: keyExpr,
            handler: handler
        )

        let queryable: any ZenohQueryableHandle
        do {
            queryable = try client.declareQueryable(keyExpr) { [weak server] query in
                server?.handleQuery(query)
            }
        } catch let error as ZenohError {
            throw TransportError.subscriberCreationFailed(error.localizedDescription ?? "declareQueryable failed")
        }
        server.attachQueryable(queryable)

        appendServiceServer(server)
        return server
    }

    public func createServiceClient(
        name: String,
        serviceTypeName: String,
        requestTypeHash: String?,
        responseTypeHash: String?,
        qos: TransportQoS
    ) throws -> any TransportClient {
        guard !name.isEmpty else {
            throw TransportError.invalidConfiguration("Service name cannot be empty")
        }
        guard !serviceTypeName.isEmpty else {
            throw TransportError.invalidConfiguration("Service type name cannot be empty")
        }
        guard isConnected else {
            throw TransportError.notConnected
        }
        guard let cfg = config else {
            throw TransportError.notConnected
        }

        let codec = ZenohWireCodec(distro: resolvedWireMode ?? .jazzy)
        let keyExpr = codec.makeServiceKeyExpr(
            domainId: cfg.domainId,
            namespace: extractNamespace(from: name),
            serviceName: extractTopicName(from: name),
            serviceTypeName: serviceTypeName,
            requestTypeHash: requestTypeHash
        )

        let serviceClient = ZenohTransportServiceClientImpl(
            client: client,
            codec: codec,
            gid: gidManager.getOrCreateGid(),
            keyExpr: keyExpr,
            name: name
        )
        appendServiceClient(serviceClient)
        return serviceClient
    }

    // MARK: - Internal lock helpers

    func appendServiceServer(_ server: ZenohTransportServiceServerImpl) {
        publishersLock.lock()
        serviceServers.append(server)
        publishersLock.unlock()
    }

    func appendServiceClient(_ serviceClient: ZenohTransportServiceClientImpl) {
        publishersLock.lock()
        serviceClients.append(serviceClient)
        publishersLock.unlock()
    }

    func takeAllServiceServers() -> [ZenohTransportServiceServerImpl] {
        publishersLock.lock()
        let out = serviceServers
        serviceServers.removeAll()
        publishersLock.unlock()
        return out
    }

    func takeAllServiceClients() -> [ZenohTransportServiceClientImpl] {
        publishersLock.lock()
        let out = serviceClients
        serviceClients.removeAll()
        publishersLock.unlock()
        return out
    }
}

// MARK: - Zenoh Transport Service Server

final class ZenohTransportServiceServerImpl: TransportService, @unchecked Sendable {
    public let name: String
    private let keyExpr: String
    private let handler: @Sendable (Data) async throws -> Data
    private var queryable: (any ZenohQueryableHandle)?
    private let lock = NSLock()
    private var closed = false

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed && queryable != nil
    }

    init(
        name: String,
        keyExpr: String,
        handler: @escaping @Sendable (Data) async throws -> Data
    ) {
        self.name = name
        self.keyExpr = keyExpr
        self.handler = handler
    }

    func attachQueryable(_ q: any ZenohQueryableHandle) {
        lock.lock()
        queryable = q
        lock.unlock()
    }

    /// Called from a zenoh-pico-owned thread. Spawn a Task so the user
    /// handler runs in Swift concurrency, then `reply` / `replyError`.
    func handleQuery(_ query: any ZenohQueryHandle) {
        let userRequestCDR = query.payload
        let captured = handler
        Task {
            do {
                let userReplyCDR = try await captured(userRequestCDR)
                try? query.reply(payload: userReplyCDR, attachment: nil)
            } catch {
                try? query.replyError(message: error.localizedDescription)
            }
        }
    }

    public func close() throws {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let q = queryable
        queryable = nil
        lock.unlock()

        try? q?.close()
    }
}

// MARK: - Zenoh Transport Service Client

final class ZenohTransportServiceClientImpl: TransportClient, @unchecked Sendable {
    private let client: any ZenohClientProtocol
    private let codec: ZenohWireCodec
    private let gid: [UInt8]
    private let keyExpr: String
    public let name: String

    private let seqLock = NSLock()
    private var nextSeq: Int64 = 0

    private let lock = NSLock()
    private var closed = false

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
    }

    init(
        client: any ZenohClientProtocol,
        codec: ZenohWireCodec,
        gid: [UInt8],
        keyExpr: String,
        name: String
    ) {
        self.client = client
        self.codec = codec
        self.gid = gid
        self.keyExpr = keyExpr
        self.name = name
    }

    /// Wait until at least one Zenoh queryable is reachable on the service
    /// key expression. Polls via short-timeout `get`s and resolves on the
    /// first reply (success or error reply both count — both prove the
    /// queryable exists). Throws `connectionTimeout` if no reply arrives
    /// before `timeout` elapses.
    public func waitForService(timeout: Duration) async throws {
        lock.lock()
        let isClosed = closed
        lock.unlock()
        if isClosed {
            throw TransportError.sessionClosed
        }

        let probeTimeoutMs: UInt32 = 200
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            let remainingMs = ZenohTransportServiceClientImpl.durationToMillis(
                deadline - ContinuousClock.now
            )
            if remainingMs == 0 {
                break
            }
            let attemptMs = min(probeTimeoutMs, remainingMs)
            let reachable = await probeOnce(timeoutMs: attemptMs)
            if reachable {
                return
            }
        }
        throw TransportError.connectionTimeout(
            TimeInterval(
                Double(timeout.components.seconds)
                    + Double(timeout.components.attoseconds) / 1.0e18))
    }

    /// Issue a single discovery probe; resolve `true` on the first reply,
    /// `false` if `onFinish` fires without one.
    private func probeOnce(timeoutMs: UInt32) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let resumed = ConcurrencyOnceFlag()
            do {
                try client.get(
                    keyExpr: keyExpr,
                    payload: nil,
                    attachment: nil,
                    timeoutMs: timeoutMs,
                    handler: { _ in
                        if resumed.set() {
                            cont.resume(returning: true)
                        }
                    },
                    onFinish: {
                        if resumed.set() {
                            cont.resume(returning: false)
                        }
                    }
                )
            } catch {
                if resumed.set() {
                    cont.resume(returning: false)
                }
            }
        }
    }

    public func call(requestCDR: Data, timeout: Duration) async throws -> Data {
        lock.lock()
        if closed {
            lock.unlock()
            throw TransportError.sessionClosed
        }
        lock.unlock()

        let seq: Int64 = {
            seqLock.lock()
            defer { seqLock.unlock() }
            nextSeq += 1
            return nextSeq
        }()

        let attachment = codec.buildAttachment(
            seq: seq,
            tsNsec: Int64(Date().timeIntervalSince1970 * 1_000_000_000),
            gid: gid
        )

        let timeoutMs = Self.durationToMillis(timeout)
        let state = CallState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, Error>) in
                state.set(continuation: continuation, timeout: timeout)

                do {
                    try client.get(
                        keyExpr: keyExpr,
                        payload: requestCDR,
                        attachment: attachment,
                        timeoutMs: timeoutMs,
                        handler: { result in
                            switch result {
                            case .success(let sample):
                                state.deliverReply(payload: sample.payload, isError: false)
                            case .failure(let err):
                                let msg: String
                                if case .queryReplyError(let m) = err {
                                    msg = m
                                } else {
                                    msg = err.localizedDescription ?? "Zenoh get error"
                                }
                                state.deliverReply(payload: Data(msg.utf8), isError: true)
                            }
                        },
                        onFinish: {
                            state.finish()
                        }
                    )
                } catch {
                    state.fail(error)
                }
            }
        } onCancel: {
            state.cancel()
        }
    }

    public func close() throws {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        lock.unlock()
    }

    private static func durationToMillis(_ duration: Duration) -> UInt32 {
        let comps = duration.components
        let seconds = max(0, Int64(comps.seconds))
        let attoseconds = Int64(comps.attoseconds)
        // 1 ms == 10^15 attoseconds
        let ms = seconds.multipliedReportingOverflow(by: 1_000)
        if ms.overflow {
            return UInt32.max
        }
        let total = ms.partialValue + attoseconds / 1_000_000_000_000_000
        if total < 0 { return 0 }
        if total > Int64(UInt32.max) { return UInt32.max }
        return UInt32(total)
    }
}

/// One-shot flag — `set()` returns true exactly once, false on every later
/// call. Used to guard CheckedContinuation.resume against being invoked
/// twice when reply / finish / cancel race.
private final class ConcurrencyOnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func set() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

/// Internal state holder for a single in-flight `call`. Coordinates the
/// reply / finish / cancel paths under a single lock so the continuation
/// is only resumed once.
private final class CallState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var timeout: Duration = .seconds(0)
    private var resolved = false
    private var receivedReply: (payload: Data, isError: Bool)?

    func set(continuation: CheckedContinuation<Data, Error>, timeout: Duration) {
        lock.lock()
        self.continuation = continuation
        self.timeout = timeout
        lock.unlock()
    }

    /// Called from the get handler. We store the first reply but defer the
    /// actual continuation resume until `onFinish` fires — this matches the
    /// shape `rmw_zenoh_cpp` uses (one reply per service get) and keeps the
    /// resume-once invariant straightforward.
    func deliverReply(payload: Data, isError: Bool) {
        lock.lock()
        if receivedReply == nil {
            receivedReply = (payload, isError)
        }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        if resolved {
            lock.unlock()
            return
        }
        resolved = true
        let cont = continuation
        continuation = nil
        let reply = receivedReply
        let dur = timeout
        lock.unlock()

        guard let cont = cont else { return }
        if let reply = reply {
            if reply.isError {
                let msg = String(decoding: reply.payload, as: UTF8.self)
                cont.resume(throwing: TransportError.serviceHandlerFailed(msg))
            } else {
                cont.resume(returning: reply.payload)
            }
        } else {
            cont.resume(throwing: TransportError.requestTimeout(dur))
        }
    }

    func fail(_ error: Error) {
        lock.lock()
        if resolved {
            lock.unlock()
            return
        }
        resolved = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }

    func cancel() {
        lock.lock()
        if resolved {
            lock.unlock()
            return
        }
        resolved = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: TransportError.requestCancelled)
    }
}
