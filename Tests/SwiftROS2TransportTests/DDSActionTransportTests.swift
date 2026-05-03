// DDSActionTransportTests.swift
// End-to-end action flows over the DDS transport via MockDDSClient.

import Foundation
import XCTest

@testable import SwiftROS2Transport

final class DDSActionTransportTests: XCTestCase {
    func testCloseWalksActionServersAndClients() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let handlers = TransportActionServerHandlers(
            onSendGoal: { _, _ in (true, 0, 0) },
            onCancelGoal: { _ in Data() },
            onGetResult: { _ in GetResultAck(status: 4, resultCDR: Data()) }
        )

        let server = try session.createActionServer(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default,
            handlers: handlers
        )
        let client = try session.createActionClient(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default
        )
        XCTAssertTrue(server.isActive)
        XCTAssertTrue(client.isActive)

        try session.close()

        XCTAssertFalse(server.isActive)
        XCTAssertFalse(client.isActive)
    }

    func testServerOnSendGoalAcceptsAndPublishesStatus() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let acceptedExpect = expectation(description: "onSendGoal called")
        let handlers = TransportActionServerHandlers(
            onSendGoal: { goalId, _ in
                XCTAssertEqual(goalId.count, 16)
                acceptedExpect.fulfill()
                return (true, 100, 200)
            },
            onCancelGoal: { _ in Data() },
            onGetResult: { _ in GetResultAck(status: 4, resultCDR: Data()) }
        )

        let serverProto = try session.createActionServer(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default,
            handlers: handlers
        )
        let server = serverProto as! DDSTransportActionServerImpl

        // Drive a request through the mock send_goal request reader.
        let goalId = [UInt8](repeating: 0xAA, count: 16)
        let inboundFrame = ActionFrameDecoder.encodeSendGoalRequest(
            goalId: goalId,
            goalCDR: Data([0x11, 0x22])
        )
        let prefixed = SampleIdentityPrefix.encode(
            requestId: RMWRequestId(
                writerGuid: [UInt8](repeating: 0xCC, count: 16), sequenceNumber: 1),
            userCDR: inboundFrame
        )
        mock.deliverRequestSample(topic: server.sendGoalRequestTopic, data: prefixed)

        await fulfillment(of: [acceptedExpect], timeout: 1)

        // Reply was written to the matching reply topic. The reply may land
        // slightly after the handler returns (Task.detached scheduling), so
        // poll briefly for it.
        try await waitForWrite(mock: mock, topic: server.sendGoalReplyTopic, timeout: 1.0)
        let writes = mock.writesByTopic[server.sendGoalReplyTopic] ?? []
        XCTAssertEqual(writes.count, 1)
        let (_, decodedReply) = try SampleIdentityPrefix.decode(wirePayload: writes[0])
        let resp = try ActionFrameDecoder.decodeSendGoalResponse(from: decodedReply)
        XCTAssertTrue(resp.accepted)
        XCTAssertEqual(resp.stampSec, 100)
        XCTAssertEqual(resp.stampNanosec, 200)
    }

    func testServerCancelGoalRoutesToHandler() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let cancelExpect = expectation(description: "onCancelGoal called")
        // The cancel-response CDR must include its 4-byte encapsulation header
        // so `SampleIdentityPrefix.encode` can strip it before prefixing.
        let cancelResponseCDR = Data([0x00, 0x01, 0x00, 0x00, 0xCC, 0xDD])
        let handlers = TransportActionServerHandlers(
            onSendGoal: { _, _ in (false, 0, 0) },
            onCancelGoal: { req in
                XCTAssertFalse(req.isEmpty)
                cancelExpect.fulfill()
                return cancelResponseCDR
            },
            onGetResult: { _ in GetResultAck(status: 4, resultCDR: Data()) }
        )

        let serverProto = try session.createActionServer(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default,
            handlers: handlers
        )
        let server = serverProto as! DDSTransportActionServerImpl

        let prefixed = SampleIdentityPrefix.encode(
            requestId: RMWRequestId(
                writerGuid: [UInt8](repeating: 0xCC, count: 16), sequenceNumber: 2),
            userCDR: Data([0x00, 0x01, 0x00, 0x00, 0x42])  // arbitrary cancel payload
        )
        mock.deliverRequestSample(topic: server.cancelGoalRequestTopic, data: prefixed)
        await fulfillment(of: [cancelExpect], timeout: 1)

        try await waitForWrite(mock: mock, topic: server.cancelGoalReplyTopic, timeout: 1.0)
        let writes = mock.writesByTopic[server.cancelGoalReplyTopic] ?? []
        XCTAssertEqual(writes.count, 1)
        let (_, decoded) = try SampleIdentityPrefix.decode(wirePayload: writes[0])
        XCTAssertEqual(decoded, cancelResponseCDR)
    }

    func testServerPublishFeedbackEmitsToFeedbackTopic() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let serverProto = try session.createActionServer(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default,
            handlers: TransportActionServerHandlers(
                onSendGoal: { _, _ in (true, 0, 0) },
                onCancelGoal: { _ in Data() },
                onGetResult: { _ in GetResultAck(status: 4, resultCDR: Data()) }
            )
        )
        let server = serverProto as! DDSTransportActionServerImpl
        let goalId = [UInt8](repeating: 0xAA, count: 16)
        try server.publishFeedback(goalId: goalId, feedbackCDR: Data([0x77]))

        let writes = mock.writesByTopic[server.feedbackTopic] ?? []
        XCTAssertEqual(writes.count, 1)
        let (parsedId, parsedFB) = try ActionFrameDecoder.decodeFeedbackMessage(from: writes[0])
        XCTAssertEqual(parsedId, goalId)
        XCTAssertEqual(parsedFB, Data([0x77]))
    }

    func testServerPublishStatusArrayEmitsToStatusTopic() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let serverProto = try session.createActionServer(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default,
            handlers: TransportActionServerHandlers(
                onSendGoal: { _, _ in (true, 0, 0) },
                onCancelGoal: { _ in Data() },
                onGetResult: { _ in GetResultAck(status: 4, resultCDR: Data()) }
            )
        )
        let server = serverProto as! DDSTransportActionServerImpl
        let goalId = [UInt8](repeating: 0xBB, count: 16)
        try server.publishStatus(entries: [
            (uuid: goalId, stampSec: 1, stampNanosec: 2, status: 4)
        ])
        let writes = mock.writesByTopic[server.statusTopic] ?? []
        XCTAssertEqual(writes.count, 1)
        let parsed = try ActionFrameDecoder.decodeStatusArray(from: writes[0])
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].status, 4)
    }

    func testClientSendGoalAcceptedYieldsFeedback() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let clientProto = try session.createActionClient(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default
        )
        let client = clientProto as! DDSTransportActionClientImpl

        let goalId = [UInt8](repeating: 0xAA, count: 16)
        let goalCDR = Data([0x33, 0x44])

        // Pre-stage the mock to reply success on send_goal request.
        mock.serviceReplyHandler = { requestTopic, prefixedRequestCDR in
            guard requestTopic.hasSuffix("send_goalRequest") else { return nil }
            guard let (rid, _) = try? SampleIdentityPrefix.decode(wirePayload: prefixedRequestCDR)
            else { return nil }
            let response = ActionFrameDecoder.encodeSendGoalResponse(
                accepted: true, stampSec: 99, stampNanosec: 0
            )
            return SampleIdentityPrefix.encode(requestId: rid, userCDR: response)
        }

        let ack = try await client.sendGoal(
            goalId: goalId,
            goalCDR: goalCDR,
            acceptanceTimeout: .seconds(2)
        )
        XCTAssertTrue(ack.accepted)
        XCTAssertEqual(ack.stampSec, 99)

        // Drive a feedback sample for that goal.
        let fbFrame = ActionFrameDecoder.encodeFeedbackMessage(
            goalId: goalId, feedbackCDR: Data([0x77])
        )
        mock.deliverSubscriberSample(topic: client.feedbackTopic, data: fbFrame)

        var receivedFB: Data?
        for await frame in ack.feedback {
            receivedFB = frame
            break
        }
        XCTAssertEqual(receivedFB, Data([0x77]))
    }

    func testClientSendGoalRejectedSurfacesAcceptedFalse() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let client = try session.createActionClient(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default
        )
        mock.serviceReplyHandler = { topic, prefixed in
            guard topic.hasSuffix("send_goalRequest") else { return nil }
            guard let (rid, _) = try? SampleIdentityPrefix.decode(wirePayload: prefixed) else {
                return nil
            }
            let response = ActionFrameDecoder.encodeSendGoalResponse(
                accepted: false, stampSec: 0, stampNanosec: 0)
            return SampleIdentityPrefix.encode(requestId: rid, userCDR: response)
        }

        let ack = try await client.sendGoal(
            goalId: [UInt8](repeating: 0xAA, count: 16),
            goalCDR: Data(),
            acceptanceTimeout: .seconds(2)
        )
        XCTAssertFalse(ack.accepted)
    }

    func testClientGetResultBlocksUntilReply() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let client = try session.createActionClient(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default
        )
        mock.serviceReplyHandler = { topic, prefixed in
            guard topic.hasSuffix("get_resultRequest") else { return nil }
            guard let (rid, _) = try? SampleIdentityPrefix.decode(wirePayload: prefixed) else {
                return nil
            }
            let response = ActionFrameDecoder.encodeGetResultResponse(
                status: 4, resultCDR: Data([0xAA, 0xBB])
            )
            return SampleIdentityPrefix.encode(requestId: rid, userCDR: response)
        }

        let ack = try await client.getResult(
            goalId: [UInt8](repeating: 0xAA, count: 16),
            timeout: .seconds(2)
        )
        XCTAssertEqual(ack.status, 4)
        XCTAssertEqual(ack.resultCDR, Data([0xAA, 0xBB]))
    }

    func testClientStatusFiltersByGoalId() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let clientProto = try session.createActionClient(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default
        )
        let client = clientProto as! DDSTransportActionClientImpl
        let myGoal = [UInt8](repeating: 0xAA, count: 16)
        let otherGoal = [UInt8](repeating: 0xBB, count: 16)

        mock.serviceReplyHandler = { topic, prefixed in
            guard topic.hasSuffix("send_goalRequest") else { return nil }
            guard let (rid, _) = try? SampleIdentityPrefix.decode(wirePayload: prefixed) else {
                return nil
            }
            let response = ActionFrameDecoder.encodeSendGoalResponse(
                accepted: true, stampSec: 0, stampNanosec: 0)
            return SampleIdentityPrefix.encode(requestId: rid, userCDR: response)
        }
        let ack = try await client.sendGoal(
            goalId: myGoal,
            goalCDR: Data(),
            acceptanceTimeout: .seconds(2)
        )
        XCTAssertTrue(ack.accepted)

        // Push a status array containing both my goal and another goal.
        let frame = ActionFrameDecoder.encodeStatusArray(entries: [
            (uuid: otherGoal, stampSec: 0, stampNanosec: 0, status: 2),
            (uuid: myGoal, stampSec: 0, stampNanosec: 0, status: 1),
            (uuid: myGoal, stampSec: 0, stampNanosec: 0, status: 4),
        ])
        mock.deliverSubscriberSample(topic: client.statusTopic, data: frame)

        var seen: [Int8] = []
        for await update in ack.status {
            seen.append(update.status)
        }
        // Other-goal status filtered out; mine arrive in order; terminal closes the stream.
        XCTAssertEqual(seen, [1, 4])
    }

    // MARK: - Helpers

    private func defaultHashes() -> ActionRoleTypeHashes {
        return ActionRoleTypeHashes(
            sendGoalRequest: nil, sendGoalResponse: nil,
            cancelGoalRequest: nil, cancelGoalResponse: nil,
            getResultRequest: nil, getResultResponse: nil,
            feedbackMessage: nil, statusArray: nil
        )
    }

    /// Poll the mock until at least one write has landed on `topic` or the
    /// timeout elapses. Detached server tasks may write the reply slightly
    /// after the handler returns, so a tiny poll is necessary.
    private func waitForWrite(
        mock: MockDDSClient, topic: String, timeout: TimeInterval
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let entries = mock.writesByTopic[topic], !entries.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testClientWaitForActionServerThrowsWhenNoMatch() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        // Default mock never reports a publication match → must time out.
        let client = try session.createActionClient(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default
        )
        do {
            try await client.waitForActionServer(timeout: .milliseconds(300))
            XCTFail("expected actionServerUnavailable")
        } catch let e as TransportError {
            if case .actionServerUnavailable = e { return }
            XCTFail("got \(e) instead of actionServerUnavailable")
        }
    }

    func testClientWaitForActionServerSucceedsWhenAllWritersMatch() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let client = try session.createActionClient(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default
        )
        // Mark every request-side writer's topic as matched so the new
        // all-3-writers wait condition resolves on the first poll.
        let cli = client as! DDSTransportActionClientImpl
        mock.markPublicationsMatched(topic: cli.names.sendGoalRequestTopic)
        mock.markPublicationsMatched(topic: cli.names.cancelGoalRequestTopic)
        mock.markPublicationsMatched(topic: cli.names.getResultRequestTopic)

        try await client.waitForActionServer(timeout: .seconds(2))  // no throw expected
    }

    func testClientCancelGoalRoundTrip() async throws {
        let mock = MockDDSClient()
        let session = DDSTransportSession(client: mock)
        try await session.open(config: .ddsMulticast(domainId: 0))
        defer { try? session.close() }

        let client = try session.createActionClient(
            name: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHashes: defaultHashes(),
            qos: .default
        )
        let goalId = [UInt8](repeating: 0xAA, count: 16)

        // Server replies returnCode=0 with one canceling goal entry.
        mock.serviceReplyHandler = { topic, prefixed in
            guard topic.hasSuffix("cancel_goalRequest") else { return nil }
            let (rid, _) =
                (try? SampleIdentityPrefix.decode(wirePayload: prefixed))
                ?? (RMWRequestId(writerGuid: [], sequenceNumber: 0), Data())
            // [header (4) | code (1) | pad (3) | count (u32) | { uuid[16] | sec | nsec }]
            var resp = Data([0x00, 0x01, 0x00, 0x00])
            resp.append(0)  // returnCode = 0
            resp.append(contentsOf: [0, 0, 0])
            var count = UInt32(1).littleEndian
            withUnsafeBytes(of: &count) { resp.append(contentsOf: $0) }
            resp.append(contentsOf: goalId)
            var sec = Int32(7).littleEndian
            var nsec = UInt32(11).littleEndian
            withUnsafeBytes(of: &sec) { resp.append(contentsOf: $0) }
            withUnsafeBytes(of: &nsec) { resp.append(contentsOf: $0) }
            return SampleIdentityPrefix.encode(requestId: rid, userCDR: resp)
        }

        let ack = try await client.cancelGoal(
            goalId: goalId,
            beforeStampSec: nil,
            beforeStampNanosec: nil,
            timeout: .seconds(2)
        )
        XCTAssertEqual(ack.returnCode, 0)
        XCTAssertEqual(ack.goalsCanceling.count, 1)
        XCTAssertEqual(ack.goalsCanceling[0].uuid, goalId)
        XCTAssertEqual(ack.goalsCanceling[0].stampSec, 7)
        XCTAssertEqual(ack.goalsCanceling[0].stampNanosec, 11)

        // Confirm the request that went out on the wire carried the goal id.
        let cancelTopic = (client as! DDSTransportActionClientImpl).names.cancelGoalRequestTopic
        let writes = mock.writesByTopic[cancelTopic] ?? []
        XCTAssertEqual(writes.count, 1)
        let (_, reqCDR) = try SampleIdentityPrefix.decode(wirePayload: writes[0])
        // Request frame: [header (4) | uuid[16] | sec | nsec]
        XCTAssertEqual(reqCDR.count, 4 + 16 + 4 + 4)
        XCTAssertEqual(
            Array(reqCDR[(reqCDR.startIndex + 4)..<(reqCDR.startIndex + 20)]), goalId)
    }
}
