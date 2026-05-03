import Foundation
import XCTest

@testable import SwiftROS2CDR
@testable import SwiftROS2Messages

/// Test goal type used by the wrapper round-trips.
private struct TestGoal: CDRCodable, Sendable, Equatable {
    var order: Int32
    func encode(to encoder: CDREncoder) throws { encoder.writeInt32(order) }
    init(from decoder: CDRDecoder) throws { self.order = try decoder.readInt32() }
    init(order: Int32) { self.order = order }
}

private struct TestResult: CDRCodable, Sendable, Equatable {
    var sequence: [Int32]
    func encode(to encoder: CDREncoder) throws { encoder.writeInt32Sequence(sequence) }
    init(from decoder: CDRDecoder) throws {
        let n = try decoder.readUInt32()
        var out: [Int32] = []
        for _ in 0..<n { out.append(try decoder.readInt32()) }
        self.sequence = out
    }
    init(sequence: [Int32]) { self.sequence = sequence }
}

private struct TestFeedback: CDRCodable, Sendable, Equatable {
    var partialSequence: [Int32]
    func encode(to encoder: CDREncoder) throws { encoder.writeInt32Sequence(partialSequence) }
    init(from decoder: CDRDecoder) throws {
        let n = try decoder.readUInt32()
        var out: [Int32] = []
        for _ in 0..<n { out.append(try decoder.readInt32()) }
        self.partialSequence = out
    }
    init(partialSequence: [Int32]) { self.partialSequence = partialSequence }
}

final class ActionWrappersCDRTests: XCTestCase {

    private func uuid(_ b: UInt8) -> UniqueIdentifierUUID {
        UniqueIdentifierUUID(uuid: Array(repeating: b, count: 16))
    }

    func testSendGoalRequestRoundTrip() throws {
        let original = ActionSendGoalRequest(goalId: uuid(0xAA), goal: TestGoal(order: 7))
        let enc = CDREncoder()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try ActionSendGoalRequest<TestGoal>(from: dec)
        XCTAssertEqual(decoded.goalId.uuid, original.goalId.uuid)
        XCTAssertEqual(decoded.goal.order, 7)
    }

    func testSendGoalResponseRoundTrip() throws {
        let original = ActionSendGoalResponse(
            accepted: true,
            stamp: BuiltinInterfacesTime(sec: 11, nanosec: 22)
        )
        let enc = CDREncoder()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try ActionSendGoalResponse(from: dec)
        XCTAssertEqual(decoded.accepted, true)
        XCTAssertEqual(decoded.stamp.sec, 11)
    }

    func testGetResultRequestRoundTrip() throws {
        let original = ActionGetResultRequest(goalId: uuid(0xBB))
        let enc = CDREncoder()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try ActionGetResultRequest(from: dec)
        XCTAssertEqual(decoded.goalId.uuid, original.goalId.uuid)
    }

    func testGetResultResponseRoundTrip() throws {
        let original = ActionGetResultResponse(
            status: GoalStatusCode.succeeded.rawValue,
            result: TestResult(sequence: [0, 1, 1, 2, 3])
        )
        let enc = CDREncoder()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try ActionGetResultResponse<TestResult>(from: dec)
        XCTAssertEqual(decoded.status, GoalStatusCode.succeeded.rawValue)
        XCTAssertEqual(decoded.result.sequence, [0, 1, 1, 2, 3])
    }

    func testFeedbackMessageRoundTrip() throws {
        let original = ActionFeedbackMessage(
            goalId: uuid(0xCC),
            feedback: TestFeedback(partialSequence: [0, 1, 1])
        )
        let enc = CDREncoder()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try ActionFeedbackMessage<TestFeedback>(from: dec)
        XCTAssertEqual(decoded.goalId.uuid, original.goalId.uuid)
        XCTAssertEqual(decoded.feedback.partialSequence, [0, 1, 1])
    }
}
