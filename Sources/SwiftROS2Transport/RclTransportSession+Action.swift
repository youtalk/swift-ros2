// RclTransportSession+Action.swift
// Action Server / Client implementation for the rcl transport (M8).
//
// Serialize-shim design (spec §20.6): the C bridge converts bytes to typed
// rosidl wrapper structs via rmw_deserialize / rmw_serialize and calls the
// typed rcl_action API. This layer stays byte-oriented and reuses the exact
// wire-path frame helpers (`ActionFrameDecoder`), so the public action API
// behaves identically on `.rcl` and on the wire transports. The one
// rcl-specific addition: rcl_action tracks accepted goals server-side (its
// status publisher and result-timeout expiry read that tracking), so this
// layer mirrors the umbrella's status snapshots into rcl's goal state
// machine via the seam's acceptGoal / updateGoalState / notifyGoalDone.

import Foundation

extension RclTransportSession {
    package func createActionServer(
        name: String,
        actionTypeName: String,
        roleTypeHashes: ActionRoleTypeHashes,
        qos: TransportQoS,
        handlers: TransportActionServerHandlers
    ) throws -> any TransportActionServer {
        guard !name.isEmpty else {
            throw TransportError.invalidConfiguration("Action name cannot be empty")
        }
        guard !actionTypeName.isEmpty else {
            throw TransportError.invalidConfiguration("Action type name cannot be empty")
        }
        // roleTypeHashes are unused on this backend: rcl derives hashes from
        // the typesupport handle (same note as subscriber / service).
        let node = try preflightServiceEntity()
        let server = RclTransportActionServer(client: client, name: name, handlers: handlers)
        let callbacks = RclActionServerCallbacks(
            onGoalRequest: { [weak server] data, requestId in
                server?.handleGoalRequest(data: data, requestId: requestId)
            },
            onCancelRequest: { [weak server] data, requestId in
                server?.handleCancelRequest(data: data, requestId: requestId)
            },
            onResultRequest: { [weak server] data, requestId in
                server?.handleResultRequest(data: data, requestId: requestId)
            }
        )
        let handle = try client.createActionServer(
            node: node, actionTypeName: actionTypeName, actionName: name, qos: qos,
            callbacks: callbacks)
        server.attachHandle(handle)
        try appendActionServer(server)
        return server
    }

    package func createActionClient(
        name: String,
        actionTypeName: String,
        roleTypeHashes: ActionRoleTypeHashes,
        qos: TransportQoS
    ) throws -> any TransportActionClient {
        guard !name.isEmpty else {
            throw TransportError.invalidConfiguration("Action name cannot be empty")
        }
        guard !actionTypeName.isEmpty else {
            throw TransportError.invalidConfiguration("Action type name cannot be empty")
        }
        let node = try preflightServiceEntity()
        let actionClient = RclTransportActionClient(client: client, name: name)
        let callbacks = RclActionClientCallbacks(
            onGoalResponse: { [weak actionClient] sequenceNumber, data in
                actionClient?.handleGoalResponse(sequenceNumber: sequenceNumber, data: data)
            },
            onCancelResponse: { [weak actionClient] sequenceNumber, data in
                actionClient?.handleCancelResponse(sequenceNumber: sequenceNumber, data: data)
            },
            onResultResponse: { [weak actionClient] sequenceNumber, data in
                actionClient?.handleResultResponse(sequenceNumber: sequenceNumber, data: data)
            },
            onFeedback: { [weak actionClient] data in
                actionClient?.handleFeedback(data: data)
            },
            onStatus: { [weak actionClient] records in
                actionClient?.handleStatus(records: records)
            }
        )
        let handle = try client.createActionClient(
            node: node, actionTypeName: actionTypeName, actionName: name, qos: qos,
            callbacks: callbacks)
        actionClient.attachHandle(handle)
        try appendActionClient(actionClient)
        return actionClient
    }
}

// MARK: - RCL Transport Action Server

final class RclTransportActionServer: TransportActionServer, @unchecked Sendable {
    private let client: any RclClientProtocol
    private var handle: (any RclActionServerHandle)?
    public let name: String
    private let handlers: TransportActionServerHandlers
    private let lock = NSLock()
    private var closed = false
    /// Last status mirrored into rcl's goal state machine, per 16-byte goal
    /// id. `nil` entry means the goal is not yet rcl-accepted. The map keeps
    /// terminal goals so repeated snapshots do not re-fire events (mirrors
    /// the umbrella's own goal map, which also retains finished goals).
    private var rclGoalStatus: [Data: Int8] = [:]

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        if closed { return false }
        return handle?.isActive ?? false
    }

    init(
        client: any RclClientProtocol,
        name: String,
        handlers: TransportActionServerHandlers
    ) {
        self.client = client
        self.name = name
        self.handlers = handlers
    }

    func attachHandle(_ handle: any RclActionServerHandle) {
        lock.lock()
        self.handle = handle
        lock.unlock()
    }

    private func handleSnapshot() -> (any RclActionServerHandle)? {
        lock.lock()
        defer { lock.unlock() }
        return closed ? nil : handle
    }

    /// Register the goal with rcl_action exactly once (the goal-response path
    /// and the status-publish path can race here). The C side is idempotent
    /// too; the Swift-side map just avoids redundant FFI hops.
    private func ensureAcceptedInRcl(goalId: [UInt8], stampSec: Int32, stampNanosec: UInt32) {
        let key = Data(goalId)
        lock.lock()
        let known = rclGoalStatus[key] != nil
        if !known { rclGoalStatus[key] = 1 }  // STATUS_ACCEPTED
        let h = closed ? nil : handle
        lock.unlock()
        guard !known, let h else { return }
        try? client.acceptGoal(h, goalId: goalId, stampSec: stampSec, stampNanosec: stampNanosec)
    }

    /// Called from the action server's wait thread. Decodes the SendGoal
    /// request frame, runs the async accept handler, registers an accepted
    /// goal with rcl (rcl requires accept-before-respond), and sends the
    /// SendGoal response. Handler throws mirror the wire path: best-effort
    /// drop, no reply.
    func handleGoalRequest(data: Data, requestId: [UInt8]) {
        let handlers = self.handlers
        Task.detached(priority: .userInitiated) { [weak self, handlers, data, requestId] in
            do {
                let (goalId, goalCDR) = try ActionFrameDecoder.decodeSendGoalRequest(from: data)
                let (accepted, sec, nsec) = try await handlers.onSendGoal(goalId, goalCDR)
                guard let self else { return }
                if accepted {
                    self.ensureAcceptedInRcl(goalId: goalId, stampSec: sec, stampNanosec: nsec)
                }
                let response = ActionFrameDecoder.encodeSendGoalResponse(
                    accepted: accepted, stampSec: sec, stampNanosec: nsec
                )
                // Snapshot the handle after the handler completes so a server
                // closed mid-handler drops the response instead of racing.
                guard let h = self.handleSnapshot() else { return }
                try? self.client.sendGoalResponse(h, requestId: requestId, data: response)
            } catch {
                // Mirror the wire path (DDSTransportSession+Action): drop.
                _ = error
            }
        }
    }

    /// Called from the action server's wait thread. The umbrella owns cancel
    /// semantics (candidate matching, per-goal cancel handler, response
    /// encoding) — this layer just shuttles bytes, exactly like the wire path.
    func handleCancelRequest(data: Data, requestId: [UInt8]) {
        let handlers = self.handlers
        Task.detached(priority: .userInitiated) { [weak self, handlers, data, requestId] in
            do {
                let response = try await handlers.onCancelGoal(data)
                guard let self, let h = self.handleSnapshot() else { return }
                try? self.client.sendCancelResponse(h, requestId: requestId, data: response)
            } catch {
                _ = error
            }
        }
    }

    /// Called from the action server's wait thread. Awaits the goal's
    /// terminal state via the umbrella handler and sends the GetResult
    /// response.
    func handleResultRequest(data: Data, requestId: [UInt8]) {
        let handlers = self.handlers
        Task.detached(priority: .userInitiated) { [weak self, handlers, data, requestId] in
            do {
                let goalId = try ActionFrameDecoder.decodeGetResultRequest(from: data)
                let ack = try await handlers.onGetResult(goalId)
                let response = ActionFrameDecoder.encodeGetResultResponse(
                    status: ack.status, resultCDR: ack.resultCDR
                )
                guard let self, let h = self.handleSnapshot() else { return }
                try? self.client.sendResultResponse(h, requestId: requestId, data: response)
            } catch {
                _ = error
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
        let h = handle
        handle = nil
        rclGoalStatus.removeAll()
        lock.unlock()
        if let h {
            // Blocks until any in-flight wait-thread callback has returned.
            client.destroyActionServer(h)
        }
    }
}

extension RclTransportActionServer: PublishesActionFeedback {
    /// Server-side: publish a feedback frame for a specific goal. The frame
    /// layout is the wire path's FeedbackMessage (header + uuid + feedback);
    /// the C bridge rmw_deserializes it into the typed wrapper and publishes
    /// through rcl_action.
    func publishFeedback(goalId: [UInt8], feedbackCDR: Data) throws {
        guard let h = handleSnapshot() else { throw TransportError.publisherClosed }
        let frame = ActionFrameDecoder.encodeFeedbackMessage(
            goalId: goalId, feedbackCDR: feedbackCDR
        )
        try client.publishActionFeedback(h, data: frame)
    }

    /// Server-side: publish a status snapshot. On `.rcl` the status array on
    /// the wire comes from rcl_action's own goal tracking, so first mirror
    /// the umbrella's snapshot into rcl's goal state machine: accept goals
    /// rcl has not seen yet, then replay the per-goal state transitions that
    /// bridge the last mirrored status to the snapshot status. Goal-event
    /// sync failures are best-effort (`try?`) — the publish itself reports
    /// errors, matching the wire path's single throwing write.
    func publishStatus(entries: [ActionStatusEntry]) throws {
        guard let h = handleSnapshot() else { throw TransportError.publisherClosed }
        var anyNewlyTerminal = false
        for entry in entries {
            let key = Data(entry.uuid)
            lock.lock()
            let previous = rclGoalStatus[key]
            if previous == nil { rclGoalStatus[key] = 1 }  // STATUS_ACCEPTED
            lock.unlock()
            if previous == nil {
                try? client.acceptGoal(
                    h, goalId: entry.uuid, stampSec: entry.stampSec,
                    stampNanosec: entry.stampNanosec)
            }
            let from = previous ?? 1
            guard entry.status != from else { continue }
            for event in Self.goalEvents(from: from, to: entry.status) {
                try? client.updateGoalState(h, goalId: entry.uuid, event: event)
            }
            lock.lock()
            rclGoalStatus[key] = entry.status
            lock.unlock()
            if Self.isTerminal(entry.status) && !Self.isTerminal(from) {
                anyNewlyTerminal = true
            }
        }
        if anyNewlyTerminal {
            // Starts the result-timeout expiry clock for the terminal goals.
            try? client.notifyGoalDone(h)
        }
        try client.publishActionStatus(h)
    }

    private static func isTerminal(_ status: Int8) -> Bool {
        // STATUS_SUCCEEDED = 4, STATUS_CANCELED = 5, STATUS_ABORTED = 6.
        return status == 4 || status == 5 || status == 6
    }

    /// Event chain that drives rcl_action's goal state machine from `from`
    /// to `to` (GoalStatus values). Multi-hop chains cover snapshots that
    /// skip intermediate states (e.g. accepted straight to succeeded when
    /// the executing snapshot was never published).
    static func goalEvents(from: Int8, to: Int8) -> [RclGoalEvent] {
        switch (from, to) {
        case (1, 2): return [.execute]
        case (1, 3): return [.cancelGoal]
        case (1, 4): return [.execute, .succeed]
        case (1, 5): return [.cancelGoal, .canceled]
        case (1, 6): return [.execute, .abort]
        case (2, 3): return [.cancelGoal]
        case (2, 4): return [.succeed]
        case (2, 5): return [.cancelGoal, .canceled]
        case (2, 6): return [.abort]
        case (3, 4): return [.succeed]
        case (3, 5): return [.canceled]
        case (3, 6): return [.abort]
        default: return []
        }
    }
}

// MARK: - RCL Transport Action Client

final class RclTransportActionClient: TransportActionClient, @unchecked Sendable {
    private let client: any RclClientProtocol
    private var handle: (any RclActionClientHandle)?
    public let name: String
    private let lock = NSLock()
    private var closed = false

    // One correlation table per request role — rcl's sequence numbers are
    // per underlying service client, so the namespaces must not be merged.
    private let goalPending = RclPendingCallTable()
    private let cancelPending = RclPendingCallTable()
    private let resultPending = RclPendingCallTable()

    /// Shared per-goal stream / continuation tracker (same actor as the wire
    /// transports).
    let pending = ActionPendingTable()

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        if closed { return false }
        return handle?.isActive ?? false
    }

    init(client: any RclClientProtocol, name: String) {
        self.client = client
        self.name = name
    }

    func attachHandle(_ handle: any RclActionClientHandle) {
        lock.lock()
        self.handle = handle
        lock.unlock()
    }

    private func handleSnapshot() -> (any RclActionClientHandle)? {
        lock.lock()
        defer { lock.unlock() }
        return closed ? nil : handle
    }

    public func waitForActionServer(timeout: Duration) async throws {
        // rcl_action_server_is_available checks the full action surface
        // (all three services + both topics) — no per-writer matching dance
        // like the DDS wire path needs.
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if let h = handleSnapshot(), client.actionServerAvailable(h) {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            try Task.checkCancellation()
        }
        throw TransportError.actionServerUnavailable
    }

    public func sendGoal(
        goalId: [UInt8],
        goalCDR: Data,
        acceptanceTimeout: Duration
    ) async throws -> SendGoalAck {
        precondition(goalId.count == 16, "goalId must be 16 bytes")

        // Pre-register the per-goal feedback / status streams before we issue
        // the request — the server may publish a status update the instant it
        // accepts, and we'd lose it otherwise (wire-path semantics).
        var fbCont: AsyncStream<Data>.Continuation!
        let feedback = AsyncStream<Data> { fbCont = $0 }
        var stCont: AsyncStream<ActionStatusUpdate>.Continuation!
        let status = AsyncStream<ActionStatusUpdate> { stCont = $0 }
        await pending.registerStreams(goalId: goalId, feedback: fbCont, status: stCont)

        guard let h = handleSnapshot() else {
            // Roll back the streams we just registered — otherwise this goal
            // id sits in `pending` forever and any racing feedback / status
            // sample would be routed to a goal the caller never received a
            // handle for.
            await pending.cancel(goalId: goalId)
            throw TransportError.sessionClosed
        }

        let frame = ActionFrameDecoder.encodeSendGoalRequest(goalId: goalId, goalCDR: goalCDR)
        let rclClient = client

        let replyCDR: Data
        do {
            replyCDR = try await rclAwaitCorrelatedReply(
                table: goalPending, timeout: acceptanceTimeout
            ) {
                try rclClient.sendGoalRequest(h, data: frame)
            }
        } catch {
            // The request never completed (timeout / cancel / send failure /
            // close) — drop the pending entry to avoid the same misrouting
            // hazard as above.
            await pending.cancel(goalId: goalId)
            throw error
        }

        let resp: (accepted: Bool, stampSec: Int32, stampNanosec: UInt32)
        do {
            resp = try ActionFrameDecoder.decodeSendGoalResponse(from: replyCDR)
        } catch {
            await pending.cancel(goalId: goalId)
            throw error
        }
        if !resp.accepted {
            await pending.cancel(goalId: goalId)
        }
        return SendGoalAck(
            accepted: resp.accepted,
            stampSec: resp.stampSec,
            stampNanosec: resp.stampNanosec,
            feedback: feedback,
            status: status
        )
    }

    public func getResult(goalId: [UInt8], timeout: Duration) async throws -> GetResultAck {
        precondition(goalId.count == 16, "goalId must be 16 bytes")
        guard let h = handleSnapshot() else { throw TransportError.sessionClosed }

        let frame = ActionFrameDecoder.encodeGetResultRequest(goalId: goalId)
        let rclClient = client
        let replyCDR = try await rclAwaitCorrelatedReply(table: resultPending, timeout: timeout) {
            try rclClient.sendResultRequest(h, data: frame)
        }
        let (status, resultCDR) = try ActionFrameDecoder.decodeGetResultResponse(from: replyCDR)
        // Drain the per-goal entry from `pending` — the result has been
        // delivered and any future feedback / status samples for this goal
        // are stale (wire-path semantics).
        await pending.cancel(goalId: goalId)
        return GetResultAck(status: status, resultCDR: resultCDR)
    }

    public func cancelGoal(
        goalId: [UInt8]?,
        beforeStampSec: Int32?,
        beforeStampNanosec: UInt32?,
        timeout: Duration
    ) async throws -> CancelGoalAck {
        guard let h = handleSnapshot() else { throw TransportError.sessionClosed }

        // Build CancelGoal_Request CDR by hand: action_msgs/srv/CancelGoal_Request
        // is `GoalInfo goal_info { uuid[16], builtin_interfaces/Time stamp }`
        // (same construction as the DDS wire path).
        var frame = ActionFrameDecoder.cdrHeader
        let id = goalId ?? [UInt8](repeating: 0, count: 16)
        precondition(id.count == 16, "goalId must be 16 bytes")
        frame.append(contentsOf: id)
        var sec = (beforeStampSec ?? 0).littleEndian
        var nsec = (beforeStampNanosec ?? 0).littleEndian
        withUnsafeBytes(of: &sec) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: &nsec) { frame.append(contentsOf: $0) }

        let rclClient = client
        let replyCDR = try await rclAwaitCorrelatedReply(table: cancelPending, timeout: timeout) {
            try rclClient.sendCancelRequest(h, data: frame)
        }
        return try Self.decodeCancelGoalResponse(from: replyCDR)
    }

    /// CancelGoal_Response CDR: `int8 return_code; GoalInfo[] goals_canceling`.
    /// Layout: [header (4) | code (1) | pad (3) | count (u32) | { uuid[16] | sec | nsec } * count ]
    /// — same parse as the DDS wire path.
    static func decodeCancelGoalResponse(from replyCDR: Data) throws -> CancelGoalAck {
        guard replyCDR.count >= 4 + 1 + 3 + 4 else {
            throw ActionFrameDecoderError.payloadTooShort
        }
        let code = Int8(bitPattern: replyCDR[replyCDR.startIndex + 4])
        let count = replyCDR.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian
        }
        let needed = 4 + 1 + 3 + 4 + Int(count) * (16 + 4 + 4)
        guard replyCDR.count >= needed else { throw ActionFrameDecoderError.payloadTooShort }
        var out: [CancelGoalAck.GoalEntry] = []
        out.reserveCapacity(Int(count))
        var off = replyCDR.startIndex + 12
        for _ in 0..<Int(count) {
            let uuid = Array(replyCDR[off..<(off + 16)])
            off += 16
            let s = replyCDR.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: off - replyCDR.startIndex, as: Int32.self)
                    .littleEndian
            }
            off += 4
            let ns = replyCDR.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: off - replyCDR.startIndex, as: UInt32.self)
                    .littleEndian
            }
            off += 4
            out.append((uuid: uuid, stampSec: s, stampNanosec: ns))
        }
        return CancelGoalAck(returnCode: code, goalsCanceling: out)
    }

    public func close() throws {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let h = handle
        handle = nil
        lock.unlock()

        // Resume every parked request exactly once with sessionClosed, then
        // fail the per-goal streams / result continuations (actor hop).
        goalPending.failAll(TransportError.sessionClosed)
        cancelPending.failAll(TransportError.sessionClosed)
        resultPending.failAll(TransportError.sessionClosed)
        Task { [pending] in
            await pending.failAll(TransportError.sessionClosed)
        }

        if let h {
            // Blocks until any in-flight wait-thread callback has returned.
            client.destroyActionClient(h)
        }
    }

    // MARK: Internal — wait-thread callbacks

    /// All four resolve paths hop off the wait thread via a Task before
    /// touching the tables / actor, so `close()`'s destroy-join can never
    /// deadlock against a callback blocked on a lock (M7 contract).
    func handleGoalResponse(sequenceNumber: Int64, data: Data) {
        let table = goalPending
        Task { [table] in
            table.resolve(seq: sequenceNumber, with: .success(data))
        }
    }

    func handleCancelResponse(sequenceNumber: Int64, data: Data) {
        let table = cancelPending
        Task { [table] in
            table.resolve(seq: sequenceNumber, with: .success(data))
        }
    }

    func handleResultResponse(sequenceNumber: Int64, data: Data) {
        let table = resultPending
        Task { [table] in
            table.resolve(seq: sequenceNumber, with: .success(data))
        }
    }

    func handleFeedback(data: Data) {
        guard let (goalId, fbCDR) = try? ActionFrameDecoder.decodeFeedbackMessage(from: data)
        else { return }
        Task { [pending] in
            await pending.yieldFeedback(goalId: goalId, cdr: fbCDR)
        }
    }

    func handleStatus(records: [RclGoalStatusRecord]) {
        guard !records.isEmpty else { return }
        Task { [pending] in
            for record in records {
                await pending.yieldStatus(goalId: record.goalId, status: record.status)
            }
        }
    }
}
