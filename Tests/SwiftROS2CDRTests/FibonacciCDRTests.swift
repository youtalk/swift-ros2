import XCTest

@testable import SwiftROS2CDR
@testable import SwiftROS2Messages

final class FibonacciCDRTests: XCTestCase {

    func testGoalRoundTrip() throws {
        let original = FibonacciAction.Goal(order: 10)
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try FibonacciAction.Goal(from: dec)
        XCTAssertEqual(decoded.order, 10)
    }

    func testResultRoundTrip() throws {
        let original = FibonacciAction.Result(sequence: [0, 1, 1, 2, 3, 5, 8])
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try FibonacciAction.Result(from: dec)
        XCTAssertEqual(decoded.sequence, [0, 1, 1, 2, 3, 5, 8])
    }

    func testFeedbackRoundTrip() throws {
        let original = FibonacciAction.Feedback(partialSequence: [0, 1, 1])
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try FibonacciAction.Feedback(from: dec)
        XCTAssertEqual(decoded.partialSequence, [0, 1, 1])
    }

    func testTypeInfoShape() {
        let info = FibonacciAction.typeInfo
        XCTAssertEqual(info.actionName, "example_interfaces/action/Fibonacci")
        XCTAssertNotNil(info.goalTypeHash)
        XCTAssertNotNil(info.resultTypeHash)
        XCTAssertNotNil(info.feedbackTypeHash)
        XCTAssertNotNil(info.sendGoalRequestTypeHash)
        XCTAssertNotNil(info.sendGoalResponseTypeHash)
        XCTAssertNotNil(info.getResultRequestTypeHash)
        XCTAssertNotNil(info.getResultResponseTypeHash)
        XCTAssertNotNil(info.feedbackMessageTypeHash)
    }

    func testEndToEndWrapperRoundTrip() throws {
        // SendGoalRequest<Fibonacci.Goal> round-trips through CDR.
        // ActionSendGoalRequest writes the encapsulation header; Goal.encode does not.
        let goalId = UniqueIdentifierUUID(uuid: Array(repeating: 0xAB, count: 16))
        let original = ActionSendGoalRequest(goalId: goalId, goal: FibonacciAction.Goal(order: 5))
        let enc = CDREncoder()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try ActionSendGoalRequest<FibonacciAction.Goal>(from: dec)
        XCTAssertEqual(decoded.goal.order, 5)
        XCTAssertEqual(decoded.goalId.uuid, original.goalId.uuid)
    }
}
