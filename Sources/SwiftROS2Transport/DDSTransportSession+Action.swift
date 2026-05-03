// DDSTransportSession+Action.swift
// Action Server / Client implementation for the DDS transport.
//
// rmw_cyclonedds_cpp materializes a single ROS 2 action under <ns>/<name>/_action/
// as 3 service pairs (send_goal, cancel_goal, get_result) plus 2 topics
// (feedback, status). Reuses the existing rq/rr/rt primitives — no new C-bridge.

import Foundation
import SwiftROS2Wire

extension DDSTransportSession {
    public func createActionServer(
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

        lock.lock()
        guard isOpen else {
            lock.unlock()
            throw TransportError.notConnected
        }
        lock.unlock()

        let codec = DDSWireCodec()
        let names = codec.actionTopicNames(
            namespace: extractNamespace(from: name),
            actionName: extractTopicName(from: name),
            actionTypeName: actionTypeName
        )

        let cfg = bridgeQoS(from: qos)
        // status topic: transient_local depth 1 (matches rclcpp).
        let statusQoS = bridgeQoS(
            from: TransportQoS(
                reliability: qos.reliability,
                durability: .transientLocal,
                history: .keepLast(1)
            ))

        // Reply writers for the three services.
        let sendGoalReplyWriter = try client.createRawWriter(
            topicName: names.sendGoalReplyTopic,
            typeName: names.sendGoalReplyTypeName,
            qos: cfg,
            userData: codec.userDataString(typeHash: roleTypeHashes.sendGoalResponse)
        )
        let cancelGoalReplyWriter = try client.createRawWriter(
            topicName: names.cancelGoalReplyTopic,
            typeName: names.cancelGoalReplyTypeName,
            qos: cfg,
            userData: codec.userDataString(typeHash: roleTypeHashes.cancelGoalResponse)
        )
        let getResultReplyWriter = try client.createRawWriter(
            topicName: names.getResultReplyTopic,
            typeName: names.getResultReplyTypeName,
            qos: cfg,
            userData: codec.userDataString(typeHash: roleTypeHashes.getResultResponse)
        )
        let feedbackWriter = try client.createRawWriter(
            topicName: names.feedbackTopic,
            typeName: names.feedbackTypeName,
            qos: cfg,
            userData: codec.userDataString(typeHash: roleTypeHashes.feedbackMessage)
        )
        let statusWriter = try client.createRawWriter(
            topicName: names.statusTopic,
            typeName: names.statusTypeName,
            qos: statusQoS,
            userData: codec.userDataString(typeHash: roleTypeHashes.statusArray)
        )

        let server = DDSTransportActionServerImpl(
            client: client,
            name: name,
            names: names,
            handlers: handlers,
            sendGoalReplyWriter: sendGoalReplyWriter,
            cancelGoalReplyWriter: cancelGoalReplyWriter,
            getResultReplyWriter: getResultReplyWriter,
            feedbackWriter: feedbackWriter,
            statusWriter: statusWriter
        )

        // Request readers for the three services.
        do {
            let sendGoalReader = try client.createRawReader(
                topicName: names.sendGoalRequestTopic,
                typeName: names.sendGoalRequestTypeName,
                qos: cfg,
                userData: codec.userDataString(typeHash: roleTypeHashes.sendGoalRequest),
                handler: { [weak server] data, _ in
                    server?.handleSendGoal(data: data)
                }
            )
            let cancelGoalReader = try client.createRawReader(
                topicName: names.cancelGoalRequestTopic,
                typeName: names.cancelGoalRequestTypeName,
                qos: cfg,
                userData: codec.userDataString(typeHash: roleTypeHashes.cancelGoalRequest),
                handler: { [weak server] data, _ in
                    server?.handleCancelGoal(data: data)
                }
            )
            let getResultReader = try client.createRawReader(
                topicName: names.getResultRequestTopic,
                typeName: names.getResultRequestTypeName,
                qos: cfg,
                userData: codec.userDataString(typeHash: roleTypeHashes.getResultRequest),
                handler: { [weak server] data, _ in
                    server?.handleGetResult(data: data)
                }
            )
            server.attachReaders(
                sendGoal: sendGoalReader,
                cancelGoal: cancelGoalReader,
                getResult: getResultReader
            )
        } catch {
            client.destroyWriter(sendGoalReplyWriter)
            client.destroyWriter(cancelGoalReplyWriter)
            client.destroyWriter(getResultReplyWriter)
            client.destroyWriter(feedbackWriter)
            client.destroyWriter(statusWriter)
            if let e = error as? DDSError {
                throw TransportError.subscriberCreationFailed(e.errorDescription ?? "\(e)")
            }
            throw error
        }

        appendActionServer(server)
        return server
    }

    public func createActionClient(
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
        lock.lock()
        guard isOpen else {
            lock.unlock()
            throw TransportError.notConnected
        }
        lock.unlock()

        let codec = DDSWireCodec()
        let names = codec.actionTopicNames(
            namespace: extractNamespace(from: name),
            actionName: extractTopicName(from: name),
            actionTypeName: actionTypeName
        )
        let cfg = bridgeQoS(from: qos)
        let statusQoS = bridgeQoS(
            from: TransportQoS(
                reliability: qos.reliability,
                durability: .transientLocal,
                history: .keepLast(1)
            ))

        let sendGoalWriter = try client.createRawWriter(
            topicName: names.sendGoalRequestTopic,
            typeName: names.sendGoalRequestTypeName,
            qos: cfg,
            userData: codec.userDataString(typeHash: roleTypeHashes.sendGoalRequest)
        )
        let cancelGoalWriter = try client.createRawWriter(
            topicName: names.cancelGoalRequestTopic,
            typeName: names.cancelGoalRequestTypeName,
            qos: cfg,
            userData: codec.userDataString(typeHash: roleTypeHashes.cancelGoalRequest)
        )
        let getResultWriter = try client.createRawWriter(
            topicName: names.getResultRequestTopic,
            typeName: names.getResultRequestTypeName,
            qos: cfg,
            userData: codec.userDataString(typeHash: roleTypeHashes.getResultRequest)
        )

        let writerGuid = GIDManager().getOrCreateGid()
        let cli = DDSTransportActionClientImpl(
            client: client,
            name: name,
            names: names,
            writerGuid: writerGuid,
            sendGoalWriter: sendGoalWriter,
            cancelGoalWriter: cancelGoalWriter,
            getResultWriter: getResultWriter
        )

        do {
            let sendGoalReplyReader = try client.createRawReader(
                topicName: names.sendGoalReplyTopic,
                typeName: names.sendGoalReplyTypeName,
                qos: cfg,
                userData: codec.userDataString(typeHash: roleTypeHashes.sendGoalResponse),
                handler: { [weak cli] data, _ in
                    cli?.handleSendGoalReply(data: data)
                }
            )
            let cancelGoalReplyReader = try client.createRawReader(
                topicName: names.cancelGoalReplyTopic,
                typeName: names.cancelGoalReplyTypeName,
                qos: cfg,
                userData: codec.userDataString(typeHash: roleTypeHashes.cancelGoalResponse),
                handler: { [weak cli] data, _ in
                    cli?.handleCancelGoalReply(data: data)
                }
            )
            let getResultReplyReader = try client.createRawReader(
                topicName: names.getResultReplyTopic,
                typeName: names.getResultReplyTypeName,
                qos: cfg,
                userData: codec.userDataString(typeHash: roleTypeHashes.getResultResponse),
                handler: { [weak cli] data, _ in
                    cli?.handleGetResultReply(data: data)
                }
            )
            let feedbackReader = try client.createRawReader(
                topicName: names.feedbackTopic,
                typeName: names.feedbackTypeName,
                qos: cfg,
                userData: codec.userDataString(typeHash: roleTypeHashes.feedbackMessage),
                handler: { [weak cli] data, _ in
                    cli?.handleFeedbackSample(data: data)
                }
            )
            let statusReader = try client.createRawReader(
                topicName: names.statusTopic,
                typeName: names.statusTypeName,
                qos: statusQoS,
                userData: codec.userDataString(typeHash: roleTypeHashes.statusArray),
                handler: { [weak cli] data, _ in
                    cli?.handleStatusSample(data: data)
                }
            )
            cli.attachReaders(
                sendGoalReply: sendGoalReplyReader,
                cancelGoalReply: cancelGoalReplyReader,
                getResultReply: getResultReplyReader,
                feedback: feedbackReader,
                status: statusReader
            )
        } catch {
            client.destroyWriter(sendGoalWriter)
            client.destroyWriter(cancelGoalWriter)
            client.destroyWriter(getResultWriter)
            if let e = error as? DDSError {
                throw TransportError.subscriberCreationFailed(e.errorDescription ?? "\(e)")
            }
            throw error
        }

        appendActionClient(cli)
        return cli
    }

    func appendActionServer(_ server: DDSTransportActionServerImpl) {
        lock.lock()
        actionServers.append(server)
        lock.unlock()
    }

    func takeAllActionServers() -> [DDSTransportActionServerImpl] {
        lock.lock()
        let out = actionServers
        actionServers.removeAll()
        lock.unlock()
        return out
    }

    func appendActionClient(_ cli: DDSTransportActionClientImpl) {
        lock.lock()
        actionClients.append(cli)
        lock.unlock()
    }

    func takeAllActionClients() -> [DDSTransportActionClientImpl] {
        lock.lock()
        let out = actionClients
        actionClients.removeAll()
        lock.unlock()
        return out
    }

    // namespace / topic helpers — local to the DDS action / service paths.
    func extractNamespace(from name: String) -> String {
        let stripped = name.hasPrefix("/") ? String(name.dropFirst()) : name
        guard let lastSlash = stripped.lastIndex(of: "/") else { return "" }
        return "/" + stripped[..<lastSlash]
    }

    func extractTopicName(from name: String) -> String {
        let stripped = name.hasPrefix("/") ? String(name.dropFirst()) : name
        guard let lastSlash = stripped.lastIndex(of: "/") else { return stripped }
        return String(stripped[stripped.index(after: lastSlash)...])
    }
}

// MARK: - DDS Transport Action Server

final class DDSTransportActionServerImpl: TransportActionServer, @unchecked Sendable {
    let client: any DDSClientProtocol
    let name: String
    let names: DDSWireCodec.ActionTopicNames
    let handlers: TransportActionServerHandlers

    private var sendGoalReplyWriter: (any DDSWriterHandle)?
    private var cancelGoalReplyWriter: (any DDSWriterHandle)?
    private var getResultReplyWriter: (any DDSWriterHandle)?
    private var feedbackWriter: (any DDSWriterHandle)?
    private var statusWriter: (any DDSWriterHandle)?

    private var sendGoalReader: (any DDSReaderHandle)?
    private var cancelGoalReader: (any DDSReaderHandle)?
    private var getResultReader: (any DDSReaderHandle)?

    private let lock = NSLock()
    private var closed = false

    init(
        client: any DDSClientProtocol,
        name: String,
        names: DDSWireCodec.ActionTopicNames,
        handlers: TransportActionServerHandlers,
        sendGoalReplyWriter: any DDSWriterHandle,
        cancelGoalReplyWriter: any DDSWriterHandle,
        getResultReplyWriter: any DDSWriterHandle,
        feedbackWriter: any DDSWriterHandle,
        statusWriter: any DDSWriterHandle
    ) {
        self.client = client
        self.name = name
        self.names = names
        self.handlers = handlers
        self.sendGoalReplyWriter = sendGoalReplyWriter
        self.cancelGoalReplyWriter = cancelGoalReplyWriter
        self.getResultReplyWriter = getResultReplyWriter
        self.feedbackWriter = feedbackWriter
        self.statusWriter = statusWriter
    }

    func attachReaders(
        sendGoal: any DDSReaderHandle,
        cancelGoal: any DDSReaderHandle,
        getResult: any DDSReaderHandle
    ) {
        lock.lock()
        sendGoalReader = sendGoal
        cancelGoalReader = cancelGoal
        getResultReader = getResult
        lock.unlock()
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        if closed { return false }
        return (sendGoalReplyWriter?.isActive ?? false)
            && (sendGoalReader?.isActive ?? false)
    }

    // Test-helper accessors for the topic strings — used by the unit tests.
    var sendGoalRequestTopic: String { names.sendGoalRequestTopic }
    var sendGoalReplyTopic: String { names.sendGoalReplyTopic }
    var cancelGoalRequestTopic: String { names.cancelGoalRequestTopic }
    var cancelGoalReplyTopic: String { names.cancelGoalReplyTopic }
    var getResultRequestTopic: String { names.getResultRequestTopic }
    var getResultReplyTopic: String { names.getResultReplyTopic }
    var feedbackTopic: String { names.feedbackTopic }
    var statusTopic: String { names.statusTopic }

    func handleSendGoal(data: Data) {
        let parsedId: RMWRequestId
        let userCDR: Data
        do {
            (parsedId, userCDR) = try SampleIdentityPrefix.decode(wirePayload: data)
        } catch {
            return
        }
        let handlers = self.handlers
        let writer = replyWriterSnapshot(\.sendGoalReplyWriter)
        let client = self.client
        Task.detached(priority: .userInitiated) { [parsedId, userCDR, handlers, writer, client] in
            do {
                let (goalId, goalCDR) = try ActionFrameDecoder.decodeSendGoalRequest(from: userCDR)
                let (accepted, sec, nsec) = try await handlers.onSendGoal(goalId, goalCDR)
                let response = ActionFrameDecoder.encodeSendGoalResponse(
                    accepted: accepted, stampSec: sec, stampNanosec: nsec
                )
                let wire = SampleIdentityPrefix.encode(requestId: parsedId, userCDR: response)
                if let w = writer {
                    try? client.writeRawCDR(writer: w, data: wire, timestamp: 0)
                }
            } catch {
                _ = error
            }
        }
    }

    func handleCancelGoal(data: Data) {
        let parsedId: RMWRequestId
        let userCDR: Data
        do {
            (parsedId, userCDR) = try SampleIdentityPrefix.decode(wirePayload: data)
        } catch {
            return
        }
        let handlers = self.handlers
        let writer = replyWriterSnapshot(\.cancelGoalReplyWriter)
        let client = self.client
        Task.detached(priority: .userInitiated) { [parsedId, userCDR, handlers, writer, client] in
            do {
                let response = try await handlers.onCancelGoal(userCDR)
                let wire = SampleIdentityPrefix.encode(requestId: parsedId, userCDR: response)
                if let w = writer {
                    try? client.writeRawCDR(writer: w, data: wire, timestamp: 0)
                }
            } catch {
                _ = error
            }
        }
    }

    func handleGetResult(data: Data) {
        let parsedId: RMWRequestId
        let userCDR: Data
        do {
            (parsedId, userCDR) = try SampleIdentityPrefix.decode(wirePayload: data)
        } catch {
            return
        }
        let handlers = self.handlers
        let writer = replyWriterSnapshot(\.getResultReplyWriter)
        let client = self.client
        Task.detached(priority: .userInitiated) { [parsedId, userCDR, handlers, writer, client] in
            do {
                let goalId = try ActionFrameDecoder.decodeGetResultRequest(from: userCDR)
                let ack = try await handlers.onGetResult(goalId)
                let response = ActionFrameDecoder.encodeGetResultResponse(
                    status: ack.status, resultCDR: ack.resultCDR
                )
                let wire = SampleIdentityPrefix.encode(requestId: parsedId, userCDR: response)
                if let w = writer {
                    try? client.writeRawCDR(writer: w, data: wire, timestamp: 0)
                }
            } catch {
                _ = error
            }
        }
    }

    /// Server-side: publish a feedback frame for a specific goal.
    func publishFeedback(goalId: [UInt8], feedbackCDR: Data) throws {
        lock.lock()
        let writer = closed ? nil : feedbackWriter
        lock.unlock()
        guard let writer = writer else { throw TransportError.publisherClosed }
        let frame = ActionFrameDecoder.encodeFeedbackMessage(
            goalId: goalId, feedbackCDR: feedbackCDR
        )
        try client.writeRawCDR(writer: writer, data: frame, timestamp: 0)
    }

    /// Server-side: publish a full status array (one entry per active goal).
    func publishStatus(entries: [ActionFrameDecoder.StatusEntry]) throws {
        lock.lock()
        let writer = closed ? nil : statusWriter
        lock.unlock()
        guard let writer = writer else { throw TransportError.publisherClosed }
        let frame = ActionFrameDecoder.encodeStatusArray(entries: entries)
        try client.writeRawCDR(writer: writer, data: frame, timestamp: 0)
    }

    private func replyWriterSnapshot(
        _ keyPath: ReferenceWritableKeyPath<DDSTransportActionServerImpl, (any DDSWriterHandle)?>
    ) -> (any DDSWriterHandle)? {
        lock.lock()
        defer { lock.unlock() }
        return closed ? nil : self[keyPath: keyPath]
    }

    func close() throws {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let writers: [any DDSWriterHandle] = [
            sendGoalReplyWriter, cancelGoalReplyWriter, getResultReplyWriter,
            feedbackWriter, statusWriter,
        ].compactMap { $0 }
        let readers: [any DDSReaderHandle] = [
            sendGoalReader, cancelGoalReader, getResultReader,
        ].compactMap { $0 }
        sendGoalReplyWriter = nil
        cancelGoalReplyWriter = nil
        getResultReplyWriter = nil
        feedbackWriter = nil
        statusWriter = nil
        sendGoalReader = nil
        cancelGoalReader = nil
        getResultReader = nil
        lock.unlock()

        for r in readers {
            client.destroyReader(r)
        }
        for w in writers {
            client.destroyWriter(w)
        }
    }
}

// MARK: - DDS Transport Action Client

final class DDSTransportActionClientImpl: TransportActionClient, @unchecked Sendable {
    private let client: any DDSClientProtocol
    let name: String
    let names: DDSWireCodec.ActionTopicNames
    private let writerGuid: [UInt8]

    private var sendGoalWriter: (any DDSWriterHandle)?
    private var cancelGoalWriter: (any DDSWriterHandle)?
    private var getResultWriter: (any DDSWriterHandle)?
    private var sendGoalReplyReader: (any DDSReaderHandle)?
    private var cancelGoalReplyReader: (any DDSReaderHandle)?
    private var getResultReplyReader: (any DDSReaderHandle)?
    private var feedbackReader: (any DDSReaderHandle)?
    private var statusReader: (any DDSReaderHandle)?

    private let lock = NSLock()
    private var closed = false

    private let seqLock = NSLock()
    private var nextSeq: Int64 = 0

    private let sendGoalPending = ClientPendingTable()
    private let cancelGoalPending = ClientPendingTable()
    private let getResultPending = ClientPendingTable()

    /// Shared per-goal stream / continuation tracker.
    let pending = ActionPendingTable()

    var feedbackTopic: String { names.feedbackTopic }
    var statusTopic: String { names.statusTopic }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
    }

    init(
        client: any DDSClientProtocol,
        name: String,
        names: DDSWireCodec.ActionTopicNames,
        writerGuid: [UInt8],
        sendGoalWriter: any DDSWriterHandle,
        cancelGoalWriter: any DDSWriterHandle,
        getResultWriter: any DDSWriterHandle
    ) {
        self.client = client
        self.name = name
        self.names = names
        self.writerGuid = writerGuid
        self.sendGoalWriter = sendGoalWriter
        self.cancelGoalWriter = cancelGoalWriter
        self.getResultWriter = getResultWriter
    }

    func attachReaders(
        sendGoalReply: any DDSReaderHandle,
        cancelGoalReply: any DDSReaderHandle,
        getResultReply: any DDSReaderHandle,
        feedback: any DDSReaderHandle,
        status: any DDSReaderHandle
    ) {
        lock.lock()
        sendGoalReplyReader = sendGoalReply
        cancelGoalReplyReader = cancelGoalReply
        getResultReplyReader = getResultReply
        feedbackReader = feedback
        statusReader = status
        lock.unlock()
    }

    func waitForActionServer(timeout: Duration) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            lock.lock()
            let writer = closed ? nil : sendGoalWriter
            lock.unlock()
            if let w = writer, client.isPublicationMatched(writer: w) {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            try Task.checkCancellation()
        }
        throw TransportError.actionServerUnavailable
    }

    func sendGoal(
        goalId: [UInt8],
        goalCDR: Data,
        acceptanceTimeout: Duration
    ) async throws -> SendGoalAck {
        precondition(goalId.count == 16, "goalId must be 16 bytes")

        // Pre-register the per-goal feedback / status streams before we issue
        // the request — the server may publish a status update the instant it
        // accepts, and we'd lose it otherwise.
        var fbCont: AsyncStream<Data>.Continuation!
        let feedback = AsyncStream<Data> { fbCont = $0 }
        var stCont: AsyncStream<ActionStatusUpdate>.Continuation!
        let status = AsyncStream<ActionStatusUpdate> { stCont = $0 }
        await pending.registerStreams(goalId: goalId, feedback: fbCont, status: stCont)

        lock.lock()
        let writer = closed ? nil : sendGoalWriter
        lock.unlock()
        guard let writer = writer else { throw TransportError.sessionClosed }

        let frame = ActionFrameDecoder.encodeSendGoalRequest(goalId: goalId, goalCDR: goalCDR)
        let seq = nextSequence()
        let id = RMWRequestId(writerGuid: writerGuid, sequenceNumber: seq)
        let wire = SampleIdentityPrefix.encode(requestId: id, userCDR: frame)

        let replyCDR = try await callWithTimeout(
            pending: sendGoalPending,
            seq: seq,
            timeout: acceptanceTimeout
        ) {
            try self.client.writeRawCDR(writer: writer, data: wire, timestamp: 0)
        }
        let resp = try ActionFrameDecoder.decodeSendGoalResponse(from: replyCDR)
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

    func getResult(goalId: [UInt8], timeout: Duration) async throws -> GetResultAck {
        precondition(goalId.count == 16, "goalId must be 16 bytes")
        lock.lock()
        let writer = closed ? nil : getResultWriter
        lock.unlock()
        guard let writer = writer else { throw TransportError.sessionClosed }

        let frame = ActionFrameDecoder.encodeGetResultRequest(goalId: goalId)
        let seq = nextSequence()
        let id = RMWRequestId(writerGuid: writerGuid, sequenceNumber: seq)
        let wire = SampleIdentityPrefix.encode(requestId: id, userCDR: frame)

        let replyCDR = try await callWithTimeout(
            pending: getResultPending,
            seq: seq,
            timeout: timeout
        ) {
            try self.client.writeRawCDR(writer: writer, data: wire, timestamp: 0)
        }
        let (status, resultCDR) = try ActionFrameDecoder.decodeGetResultResponse(from: replyCDR)
        return GetResultAck(status: status, resultCDR: resultCDR)
    }

    func cancelGoal(
        goalId: [UInt8]?,
        beforeStampSec: Int32?,
        beforeStampNanosec: UInt32?,
        timeout: Duration
    ) async throws -> CancelGoalAck {
        lock.lock()
        let writer = closed ? nil : cancelGoalWriter
        lock.unlock()
        guard let writer = writer else { throw TransportError.sessionClosed }

        // Build CancelGoal_Request CDR by hand: action_msgs/srv/CancelGoal_Request
        // is `GoalInfo goal_info { uuid[16], builtin_interfaces/Time stamp }`.
        var frame = ActionFrameDecoder.cdrHeader
        let id = goalId ?? [UInt8](repeating: 0, count: 16)
        precondition(id.count == 16, "goalId must be 16 bytes")
        frame.append(contentsOf: id)
        var sec = (beforeStampSec ?? 0).littleEndian
        var nsec = (beforeStampNanosec ?? 0).littleEndian
        withUnsafeBytes(of: &sec) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: &nsec) { frame.append(contentsOf: $0) }

        let seq = nextSequence()
        let rid = RMWRequestId(writerGuid: writerGuid, sequenceNumber: seq)
        let wire = SampleIdentityPrefix.encode(requestId: rid, userCDR: frame)

        let replyCDR = try await callWithTimeout(
            pending: cancelGoalPending,
            seq: seq,
            timeout: timeout
        ) {
            try self.client.writeRawCDR(writer: writer, data: wire, timestamp: 0)
        }
        // CancelGoal_Response CDR: `int8 return_code; GoalInfo[] goals_canceling`.
        // Layout: [header (4) | code (1) | pad (3) | count (u32) | { uuid[16] | sec | nsec } * count ]
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

    func close() throws {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let writers: [any DDSWriterHandle] = [
            sendGoalWriter, cancelGoalWriter, getResultWriter,
        ].compactMap { $0 }
        let readers: [any DDSReaderHandle] = [
            sendGoalReplyReader, cancelGoalReplyReader, getResultReplyReader,
            feedbackReader, statusReader,
        ].compactMap { $0 }
        sendGoalWriter = nil
        cancelGoalWriter = nil
        getResultWriter = nil
        sendGoalReplyReader = nil
        cancelGoalReplyReader = nil
        getResultReplyReader = nil
        feedbackReader = nil
        statusReader = nil
        lock.unlock()

        Task { [pending] in
            await pending.failAll(TransportError.sessionClosed)
        }
        for r in readers {
            client.destroyReader(r)
        }
        for w in writers {
            client.destroyWriter(w)
        }
    }

    // MARK: Internal — reply / sample handlers

    func handleSendGoalReply(data: Data) {
        guard let (rid, body) = try? SampleIdentityPrefix.decode(wirePayload: data),
            rid.writerGuid == writerGuid
        else { return }
        Task { [sendGoalPending] in
            await sendGoalPending.resolve(seq: rid.sequenceNumber, with: .success(body))
        }
    }

    func handleCancelGoalReply(data: Data) {
        guard let (rid, body) = try? SampleIdentityPrefix.decode(wirePayload: data),
            rid.writerGuid == writerGuid
        else { return }
        Task { [cancelGoalPending] in
            await cancelGoalPending.resolve(seq: rid.sequenceNumber, with: .success(body))
        }
    }

    func handleGetResultReply(data: Data) {
        guard let (rid, body) = try? SampleIdentityPrefix.decode(wirePayload: data),
            rid.writerGuid == writerGuid
        else { return }
        Task { [getResultPending] in
            await getResultPending.resolve(seq: rid.sequenceNumber, with: .success(body))
        }
    }

    func handleFeedbackSample(data: Data) {
        guard let (goalId, fbCDR) = try? ActionFrameDecoder.decodeFeedbackMessage(from: data) else {
            return
        }
        Task { [pending] in
            await pending.yieldFeedback(goalId: goalId, cdr: fbCDR)
        }
    }

    func handleStatusSample(data: Data) {
        guard let entries = try? ActionFrameDecoder.decodeStatusArray(from: data) else { return }
        Task { [pending] in
            for e in entries {
                await pending.yieldStatus(goalId: e.uuid, status: e.status)
            }
        }
    }

    // MARK: Internal — helpers

    private func nextSequence() -> Int64 {
        seqLock.lock()
        defer { seqLock.unlock() }
        nextSeq += 1
        return nextSeq
    }

    private func callWithTimeout(
        pending table: ClientPendingTable,
        seq: Int64,
        timeout: Duration,
        send: @escaping () throws -> Void
    ) async throws -> Data {
        let timeoutTask = Task { [table] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            await table.resolve(seq: seq, with: .failure(TransportError.requestTimeout(timeout)))
        }
        return try await withTaskCancellationHandler {
            do {
                let body = try await table.insert(seq: seq) { _ in
                    do {
                        try send()
                    } catch {
                        Task { [table] in
                            await table.resolve(seq: seq, with: .failure(error))
                        }
                    }
                }
                timeoutTask.cancel()
                return body
            } catch {
                timeoutTask.cancel()
                throw error
            }
        } onCancel: {
            timeoutTask.cancel()
            Task { [table] in
                await table.cancel(seq: seq)
            }
        }
    }
}
