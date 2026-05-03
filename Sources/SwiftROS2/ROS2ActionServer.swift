// ROS2ActionServer.swift
// Typed server wrapper around TransportActionServer.

import Foundation
import SwiftROS2CDR
import SwiftROS2Messages
import SwiftROS2Transport

/// Typed action server for a specific `ROS2Action`.
public final class ROS2ActionServer<H: ActionServerHandler>: @unchecked Sendable,
    ActionServerCloseable
{
    private let transport: any TransportActionServer
    private let handler: H
    private let isLegacySchema: Bool

    public var name: String { transport.name }
    public var isActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !closed && transport.isActive
    }

    // Per-goal state — tracked so cancel + status array publication can find it.
    private final class GoalEntry {
        let handle: ActionGoalHandle<H.Action>
        var task: Task<Void, Never>?
        var status: ActionGoalStatus
        var resultCache: GetResultAck?
        var resultWaiters: [CheckedContinuation<GetResultAck, Error>]
        var fbCont: AsyncStream<H.Action.Feedback>.Continuation
        var stCont: AsyncStream<ActionGoalStatus>.Continuation

        init(
            handle: ActionGoalHandle<H.Action>,
            status: ActionGoalStatus,
            fbCont: AsyncStream<H.Action.Feedback>.Continuation,
            stCont: AsyncStream<ActionGoalStatus>.Continuation
        ) {
            self.handle = handle
            self.status = status
            self.resultWaiters = []
            self.fbCont = fbCont
            self.stCont = stCont
        }
    }

    private let stateLock = NSLock()
    private var goals: [Data: GoalEntry] = [:]  // key: 16-byte goal_id
    private var closed = false

    init(transport: any TransportActionServer, handler: H, isLegacySchema: Bool) {
        self.transport = transport
        self.handler = handler
        self.isLegacySchema = isLegacySchema
    }

    /// Cancel the server; closes the underlying transport handle and cancels every running goal.
    public func cancel() {
        try? closeActionServer()
    }

    func closeActionServer() throws {
        stateLock.lock()
        guard !closed else {
            stateLock.unlock()
            return
        }
        closed = true
        let snapshot = Array(goals.values)
        goals.removeAll()
        stateLock.unlock()
        for entry in snapshot {
            entry.task?.cancel()
            for w in entry.resultWaiters {
                w.resume(throwing: ActionError.serverClosed)
            }
            entry.fbCont.finish()
            entry.stCont.finish()
        }
        try? transport.close()
    }

    // MARK: - Internal — handler bag the umbrella plugs into the transport

    static func makeHandlers(
        for server: @escaping @Sendable () -> ROS2ActionServer<H>?
    ) -> TransportActionServerHandlers {
        return TransportActionServerHandlers(
            onSendGoal: { goalId, goalCDR in
                guard let s = server() else { return (false, 0, 0) }
                return await s.handleSendGoal(goalId: goalId, goalCDR: goalCDR)
            },
            onCancelGoal: { reqCDR in
                guard let s = server() else {
                    return Self.encodeCancelGoalResponse(returnCode: 1, entries: [])
                }
                return await s.handleCancelGoal(requestCDR: reqCDR)
            },
            onGetResult: { goalId in
                guard let s = server() else {
                    return GetResultAck(
                        status: ActionGoalStatus.unknown.rawValue, resultCDR: Data()
                    )
                }
                return try await s.handleGetResult(goalId: goalId)
            }
        )
    }

    private func handleSendGoal(goalId: [UInt8], goalCDR: Data) async -> (
        Bool, Int32, UInt32
    ) {
        let typedGoal: H.Action.Goal
        do {
            let dec = try CDRDecoder(
                data: ROS2ActionClient<H.Action>.prependHeaderIfMissing(goalCDR),
                isLegacySchema: isLegacySchema
            )
            typedGoal = try H.Action.Goal(from: dec)
        } catch {
            return (false, 0, 0)
        }
        let resp = await handler.handleGoal(typedGoal)
        guard resp == .accept else { return (false, 0, 0) }

        // Build the server-side handle.
        let now = Date()
        let secs = now.timeIntervalSince1970
        let stamp = BuiltinInterfacesTime(
            sec: Int32(secs),
            nanosec: UInt32(secs.truncatingRemainder(dividingBy: 1) * 1_000_000_000)
        )
        var fbCont: AsyncStream<H.Action.Feedback>.Continuation!
        let fbStream = AsyncStream<H.Action.Feedback> { fbCont = $0 }
        var stCont: AsyncStream<ActionGoalStatus>.Continuation!
        let stStream = AsyncStream<ActionGoalStatus> { stCont = $0 }
        let goalUUID = Self.uuidFromBytes(goalId)
        let key = Data(goalId)
        let unused: @Sendable () async throws -> ActionResult<H.Action.Result> = {
            throw ActionError.wrongSide
        }
        let handle = ActionGoalHandle<H.Action>(
            side: .server,
            goalId: goalUUID,
            acceptedAt: stamp,
            feedbackStream: fbStream,
            statusStream: stStream,
            resultProvider: unused
        )
        // Wire publishFeedback through the transport's feedback writer.
        let transportRef = transport
        let goalIdCopy = goalId
        handle._attachPublishFeedback { cdr in
            guard let serverImpl = transportRef as? PublishesActionFeedback else { return }
            try serverImpl.publishFeedback(goalId: goalIdCopy, feedbackCDR: cdr)
        }

        let entry = GoalEntry(
            handle: handle,
            status: .accepted,
            fbCont: fbCont!,
            stCont: stCont!
        )

        let task: Task<Void, Never> = Task { [weak self, weak entry] in
            guard let self else { return }
            entry?.stCont.yield(.executing)
            self.transitionStatus(.executing, for: key)
            do {
                let result = try await self.handler.execute(handle)
                let encoder = CDREncoder(isLegacySchema: self.isLegacySchema)
                try result.encode(to: encoder)
                self.cacheResult(
                    GetResultAck(
                        status: ActionGoalStatus.succeeded.rawValue,
                        resultCDR: encoder.getData()
                    ), for: key)
                self.transitionStatus(.succeeded, for: key)
                entry?.stCont.yield(.succeeded)
            } catch is CancellationError {
                self.cacheResult(
                    GetResultAck(
                        status: ActionGoalStatus.canceled.rawValue, resultCDR: Data()
                    ), for: key)
                self.transitionStatus(.canceled, for: key)
                entry?.stCont.yield(.canceled)
            } catch {
                self.cacheResult(
                    GetResultAck(
                        status: ActionGoalStatus.aborted.rawValue, resultCDR: Data()
                    ), for: key)
                self.transitionStatus(.aborted, for: key)
                entry?.stCont.yield(.aborted)
            }
            entry?.fbCont.finish()
            entry?.stCont.finish()
        }
        entry.task = task

        stateLock.lock()
        goals[key] = entry
        stateLock.unlock()

        // Eagerly publish the accepted status so a watching client sees it immediately.
        publishStatusSnapshot()

        return (true, stamp.sec, stamp.nanosec)
    }

    private func handleCancelGoal(requestCDR: Data) async -> Data {
        // CancelGoal_Request CDR: header (4) + uuid[16] + sec(4) + nsec(4).
        guard requestCDR.count >= 4 + 16 + 8 else {
            return Self.encodeCancelGoalResponse(returnCode: 1, entries: [])
        }
        let id = Array(
            requestCDR[(requestCDR.startIndex + 4)..<(requestCDR.startIndex + 4 + 16)])
        let key = Data(id)
        stateLock.lock()
        let entry = goals[key]
        stateLock.unlock()
        guard let entry = entry else {
            return Self.encodeCancelGoalResponse(returnCode: 2, entries: [])
        }
        let resp = await handler.handleCancel(entry.handle)
        switch resp {
        case .accept:
            await entry.handle._setCancelRequested(true)
            entry.task?.cancel()
            return Self.encodeCancelGoalResponse(
                returnCode: 0,
                entries: [
                    (
                        uuid: id, stampSec: entry.handle.acceptedAt.sec,
                        stampNanosec: entry.handle.acceptedAt.nanosec
                    )
                ]
            )
        case .reject:
            return Self.encodeCancelGoalResponse(returnCode: 1, entries: [])
        }
    }

    private func handleGetResult(goalId: [UInt8]) async throws -> GetResultAck {
        let key = Data(goalId)
        stateLock.lock()
        if let cached = goals[key]?.resultCache {
            stateLock.unlock()
            return cached
        }
        stateLock.unlock()

        return try await withCheckedThrowingContinuation { cont in
            stateLock.lock()
            if let entry = goals[key] {
                if let cached = entry.resultCache {
                    stateLock.unlock()
                    cont.resume(returning: cached)
                    return
                }
                entry.resultWaiters.append(cont)
                stateLock.unlock()
            } else {
                stateLock.unlock()
                cont.resume(
                    throwing: ActionError.mapping(
                        TransportError.unsupportedFeature("unknown goal_id")))
            }
        }
    }

    private func cacheResult(_ ack: GetResultAck, for key: Data) {
        stateLock.lock()
        guard let entry = goals[key] else {
            stateLock.unlock()
            return
        }
        entry.resultCache = ack
        let waiters = entry.resultWaiters
        entry.resultWaiters = []
        stateLock.unlock()
        for w in waiters {
            w.resume(returning: ack)
        }
    }

    private func transitionStatus(_ s: ActionGoalStatus, for key: Data) {
        stateLock.lock()
        if let entry = goals[key] {
            entry.status = s
        }
        stateLock.unlock()
        publishStatusSnapshot()
    }

    private func publishStatusSnapshot() {
        stateLock.lock()
        let snapshot: [ActionStatusEntry] = goals.map { (key, entry) in
            ActionStatusEntry(
                uuid: Array(key),
                stampSec: entry.handle.acceptedAt.sec,
                stampNanosec: entry.handle.acceptedAt.nanosec,
                status: entry.status.rawValue
            )
        }
        stateLock.unlock()
        guard let serverImpl = transport as? PublishesActionFeedback else { return }
        try? serverImpl.publishStatus(entries: snapshot)
    }

    private static func encodeCancelGoalResponse(
        returnCode: Int8,
        entries: [(uuid: [UInt8], stampSec: Int32, stampNanosec: UInt32)]
    ) -> Data {
        var out = Data([0x00, 0x01, 0x00, 0x00])
        out.append(UInt8(bitPattern: returnCode))
        out.append(contentsOf: [0, 0, 0])
        var count = UInt32(entries.count).littleEndian
        withUnsafeBytes(of: &count) { out.append(contentsOf: $0) }
        for e in entries {
            out.append(contentsOf: e.uuid)
            var s = e.stampSec.littleEndian
            var n = e.stampNanosec.littleEndian
            withUnsafeBytes(of: &s) { out.append(contentsOf: $0) }
            withUnsafeBytes(of: &n) { out.append(contentsOf: $0) }
        }
        return out
    }

    static func uuidFromBytes(_ b: [UInt8]) -> Foundation.UUID {
        precondition(b.count == 16)
        return Foundation.UUID(
            uuid: (
                b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
            ))
    }
}

/// Internal protocol for type-erased action-server cleanup.
protocol ActionServerCloseable {
    func closeActionServer() throws
}
