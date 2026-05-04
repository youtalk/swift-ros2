import Testing

@testable import SwiftROS2Gen

@Suite("Parser.parseAction")
struct ActionParserTests {
    @Test("parses Fibonacci three-block action")
    func parsesFibonacci() throws {
        let source = """
            int32 order
            ---
            int32[] sequence
            ---
            int32[] sequence
            """
        let action = try Parser.parseAction(
            source: source,
            file: "Fibonacci.action",
            package: "example_interfaces",
            typeName: "Fibonacci"
        )
        #expect(action.package == "example_interfaces")
        #expect(action.typeName == "Fibonacci")
        #expect(action.goal.typeName == "Fibonacci_Goal")
        #expect(action.result.typeName == "Fibonacci_Result")
        #expect(action.feedback.typeName == "Fibonacci_Feedback")
        #expect(action.goal.fields.count == 1)
        #expect(action.goal.fields[0].name == "order")
        #expect(action.result.fields.count == 1)
        #expect(action.result.fields[0].name == "sequence")
        #expect(action.feedback.fields.count == 1)
        #expect(action.feedback.fields[0].name == "sequence")
    }

    @Test("accepts empty Goal / empty Result / empty Feedback blocks")
    func acceptsEmptyBlocks() throws {
        // All three empty: the `---\n---` separator-only form.
        let source = "---\n---"
        let action = try Parser.parseAction(
            source: source, file: "Empty.action",
            package: "p", typeName: "Empty"
        )
        #expect(action.goal.fields.isEmpty)
        #expect(action.result.fields.isEmpty)
        #expect(action.feedback.fields.isEmpty)
    }

    @Test("ignores '---' inside comments")
    func tolerantToCommentSeparators() throws {
        let source = """
            # leading --- comment must not split
            int32 order
            ---
            int32[] sequence
            ---
            int32[] sequence
            """
        let action = try Parser.parseAction(
            source: source, file: "Fibonacci.action",
            package: "example_interfaces", typeName: "Fibonacci"
        )
        #expect(action.goal.fields.count == 1)
    }

    @Test("rejects single separator")
    func rejectsSingleSeparator() {
        let source = "int32 order\n---\nint32[] result"
        #expect(throws: ParseError.self) {
            _ = try Parser.parseAction(
                source: source, file: "Bad.action",
                package: "p", typeName: "Bad"
            )
        }
    }

    @Test("rejects more than two separators")
    func rejectsExtraSeparator() {
        let source = "int32 a\n---\nint32 b\n---\nint32 c\n---\nint32 d"
        #expect(throws: ParseError.self) {
            _ = try Parser.parseAction(
                source: source, file: "Bad.action",
                package: "p", typeName: "Bad"
            )
        }
    }
}
