// TransportActionStubTests.swift
// Phase 3: verify the new TransportError cases compile and carry the expected payload.

import Foundation
import XCTest

@testable import SwiftROS2Transport

final class TransportActionStubTests: XCTestCase {
    func testActionErrorDescriptions() {
        XCTAssertEqual(
            TransportError.goalRejected.errorDescription,
            "Action goal was rejected by the server"
        )
        XCTAssertEqual(
            TransportError.goalUnknown.errorDescription,
            "Action goal id is unknown to the server"
        )
        XCTAssertEqual(
            TransportError.actionServerUnavailable.errorDescription,
            "Action server is not reachable"
        )
    }

    func testActionErrorIsRecoverable() {
        // Non-recoverable: server made a definitive decision.
        XCTAssertFalse(TransportError.goalRejected.isRecoverable)
        XCTAssertFalse(TransportError.goalUnknown.isRecoverable)
        // Recoverable: discovery may succeed later.
        XCTAssertTrue(TransportError.actionServerUnavailable.isRecoverable)
    }

    // MARK: - Ack struct shape

    func testSendGoalAckHoldsAcceptedFlagAndStreams() {
        var feedbackCont: AsyncStream<Data>.Continuation!
        let feedback = AsyncStream<Data> { feedbackCont = $0 }
        var statusCont: AsyncStream<ActionStatusUpdate>.Continuation!
        let status = AsyncStream<ActionStatusUpdate> { statusCont = $0 }

        let ack = SendGoalAck(
            accepted: true,
            stampSec: 100,
            stampNanosec: 200,
            feedback: feedback,
            status: status
        )
        XCTAssertTrue(ack.accepted)
        XCTAssertEqual(ack.stampSec, 100)
        XCTAssertEqual(ack.stampNanosec, 200)

        // Streams are usable.
        feedbackCont.yield(Data([0x42]))
        feedbackCont.finish()
        statusCont.yield(ActionStatusUpdate(status: 1))
        statusCont.finish()

        Task {
            for await fb in ack.feedback { XCTAssertEqual(fb, Data([0x42])) }
            for await st in ack.status { XCTAssertEqual(st.status, 1) }
        }
    }

    func testGetResultAckCarriesStatusAndCDR() {
        let ack = GetResultAck(status: 4, resultCDR: Data([0x00, 0x01, 0x02]))
        XCTAssertEqual(ack.status, 4)
        XCTAssertEqual(ack.resultCDR, Data([0x00, 0x01, 0x02]))
    }

    func testCancelGoalAckCarriesReturnCodeAndList() {
        let goal0 = (uuid: Array<UInt8>(repeating: 0xAB, count: 16), stampSec: Int32(1), stampNanosec: UInt32(2))
        let ack = CancelGoalAck(returnCode: 0, goalsCanceling: [goal0])
        XCTAssertEqual(ack.returnCode, 0)
        XCTAssertEqual(ack.goalsCanceling.count, 1)
        XCTAssertEqual(ack.goalsCanceling[0].uuid.count, 16)
    }
}
