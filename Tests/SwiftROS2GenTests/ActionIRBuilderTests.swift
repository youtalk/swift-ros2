import Testing

@testable import SwiftROS2Gen

@Suite("IRBuilder.build(jazzy: IDLAction)")
struct ActionIRBuilderTests {

    private func fibonacciIDL() throws -> IDLAction {
        try Parser.parseAction(
            source: "int32 order\n---\nint32[] sequence\n---\nint32[] sequence\n",
            file: "Fibonacci.action",
            package: "example_interfaces",
            typeName: "Fibonacci"
        )
    }

    @Test("builds Goal/Result/Feedback IRs with kind .action")
    func userDefinedIRsCarryActionKind() throws {
        let ir = IRBuilder.build(jazzy: try fibonacciIDL())
        #expect(ir.goal.kind == .action)
        #expect(ir.result.kind == .action)
        #expect(ir.feedback.kind == .action)
        #expect(ir.goal.typeName == "Fibonacci_Goal")
        #expect(ir.result.typeName == "Fibonacci_Result")
        #expect(ir.feedback.typeName == "Fibonacci_Feedback")
    }

    @Test("synthesizes all 5 wrapper IRs with kind .action")
    func synthesizesWrappers() throws {
        let ir = IRBuilder.build(jazzy: try fibonacciIDL())
        #expect(ir.sendGoalRequest.typeName == "Fibonacci_SendGoal_Request")
        #expect(ir.sendGoalResponse.typeName == "Fibonacci_SendGoal_Response")
        #expect(ir.getResultRequest.typeName == "Fibonacci_GetResult_Request")
        #expect(ir.getResultResponse.typeName == "Fibonacci_GetResult_Response")
        #expect(ir.feedbackMessage.typeName == "Fibonacci_FeedbackMessage")
        #expect(ir.sendGoalRequest.kind == .action)
        #expect(ir.sendGoalResponse.kind == .action)
        #expect(ir.getResultRequest.kind == .action)
        #expect(ir.getResultResponse.kind == .action)
        #expect(ir.feedbackMessage.kind == .action)
    }

    @Test("SendGoal_Request = goal_id (UUID) + nested goal (action/_Goal)")
    func sendGoalRequestShape() throws {
        let ir = IRBuilder.build(jazzy: try fibonacciIDL())
        let fields = ir.sendGoalRequest.fields
        #expect(fields.count == 2)
        #expect(fields[0].ros2Name == "goal_id")
        if case .nested(let pkg, let name) = fields[0].type {
            #expect(pkg == "unique_identifier_msgs")
            #expect(name == "UUID")
        } else {
            Issue.record("goal_id field is not a nested UUID")
        }
        #expect(fields[1].ros2Name == "goal")
        if case .nested(let pkg, let name) = fields[1].type {
            #expect(pkg == "example_interfaces")
            #expect(name == "Fibonacci_Goal")
        } else {
            Issue.record("goal field is not a nested Fibonacci_Goal")
        }
    }

    @Test("SendGoal_Response = bool accepted + builtin_interfaces/Time stamp")
    func sendGoalResponseShape() throws {
        let ir = IRBuilder.build(jazzy: try fibonacciIDL())
        let fields = ir.sendGoalResponse.fields
        #expect(fields.count == 2)
        #expect(fields[0].ros2Name == "accepted")
        #expect(fields[0].type == .primitive(.bool))
        #expect(fields[1].ros2Name == "stamp")
        if case .nested(let pkg, let name) = fields[1].type {
            #expect(pkg == "builtin_interfaces")
            #expect(name == "Time")
        } else {
            Issue.record("stamp field is not a nested Time")
        }
    }

    @Test("GetResult_Request = goal_id only")
    func getResultRequestShape() throws {
        let ir = IRBuilder.build(jazzy: try fibonacciIDL())
        #expect(ir.getResultRequest.fields.count == 1)
        #expect(ir.getResultRequest.fields[0].ros2Name == "goal_id")
    }

    @Test("GetResult_Response = int8 status + nested result")
    func getResultResponseShape() throws {
        let ir = IRBuilder.build(jazzy: try fibonacciIDL())
        let fields = ir.getResultResponse.fields
        #expect(fields.count == 2)
        #expect(fields[0].ros2Name == "status")
        #expect(fields[0].type == .primitive(.int8))
        #expect(fields[1].ros2Name == "result")
        if case .nested(let pkg, let name) = fields[1].type {
            #expect(pkg == "example_interfaces")
            #expect(name == "Fibonacci_Result")
        } else {
            Issue.record("result field is not a nested Fibonacci_Result")
        }
    }

    @Test("FeedbackMessage = goal_id + nested feedback")
    func feedbackMessageShape() throws {
        let ir = IRBuilder.build(jazzy: try fibonacciIDL())
        let fields = ir.feedbackMessage.fields
        #expect(fields.count == 2)
        #expect(fields[0].ros2Name == "goal_id")
        #expect(fields[1].ros2Name == "feedback")
        if case .nested(let pkg, let name) = fields[1].type {
            #expect(pkg == "example_interfaces")
            #expect(name == "Fibonacci_Feedback")
        } else {
            Issue.record("feedback field is not a nested Fibonacci_Feedback")
        }
    }
}
