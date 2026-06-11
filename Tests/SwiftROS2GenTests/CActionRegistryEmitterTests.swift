import Testing

@testable import SwiftROS2Gen

@Suite("CActionRegistryEmitter — generated RCL action typesupport registry")
struct CActionRegistryEmitterTests {
    private let actions: [CActionRegistryEmitter.ActionRef] = [
        .init(package: "example_interfaces", typeName: "Fibonacci"),
        .init(package: "action_tutorials_interfaces", typeName: "Fibonacci"),
    ]

    @Test("emits the per-action typesupport + wrapper-role create/destroy surface")
    func emitsWrapperSurface() throws {
        let c = CActionRegistryEmitter.emit(actions)
        // rosidl umbrella include (snake_case file name).
        #expect(c.contains("#include <example_interfaces/action/fibonacci.h>"))
        #expect(c.contains("#include <action_tutorials_interfaces/action/fibonacci.h>"))
        // Action typesupport via the documented two-argument macro.
        #expect(c.contains("ROSIDL_GET_ACTION_TYPE_SUPPORT(example_interfaces, Fibonacci)"))
        // The five wrapper-role MESSAGE typesupports — note the `action` subfolder.
        #expect(
            c.contains(
                "ROSIDL_GET_MSG_TYPE_SUPPORT(example_interfaces, action, Fibonacci_SendGoal_Request)"))
        #expect(
            c.contains(
                "ROSIDL_GET_MSG_TYPE_SUPPORT(example_interfaces, action, Fibonacci_SendGoal_Response)"))
        #expect(
            c.contains(
                "ROSIDL_GET_MSG_TYPE_SUPPORT(example_interfaces, action, Fibonacci_GetResult_Request)"))
        #expect(
            c.contains(
                "ROSIDL_GET_MSG_TYPE_SUPPORT(example_interfaces, action, Fibonacci_GetResult_Response)"))
        #expect(
            c.contains(
                "ROSIDL_GET_MSG_TYPE_SUPPORT(example_interfaces, action, Fibonacci_FeedbackMessage)"))
        // rosidl __create / __destroy wrappers with the typed cast.
        #expect(c.contains("return example_interfaces__action__Fibonacci_SendGoal_Request__create();"))
        #expect(
            c.contains(
                "example_interfaces__action__Fibonacci_SendGoal_Request__destroy((example_interfaces__action__Fibonacci_SendGoal_Request *)message);"
            ))
        #expect(c.contains("return example_interfaces__action__Fibonacci_FeedbackMessage__create();"))
        #expect(
            c.contains(
                "example_interfaces__action__Fibonacci_FeedbackMessage__destroy((example_interfaces__action__Fibonacci_FeedbackMessage *)message);"
            ))
        // All five wrapper roles are wired into the entry table.
        #expect(c.contains(".send_goal_request_typesupport ="))
        #expect(c.contains(".send_goal_response_typesupport ="))
        #expect(c.contains(".get_result_request_typesupport ="))
        #expect(c.contains(".get_result_response_typesupport ="))
        #expect(c.contains(".feedback_message_typesupport ="))
        // Lookup over the canonical "pkg/action/Type" key.
        #expect(c.contains(".name = \"example_interfaces/action/Fibonacci\","))
        #expect(
            c.contains(
                "const crcl_action_entry_t *crcl_action_registry_lookup(const char *action_type_name)"))
        // Table size is pinned to the generated header's count macro.
        #expect(c.contains("_Static_assert("))
        #expect(c.contains("CRCL_ACTION_REGISTRY_ENTRY_COUNT"))
    }

    @Test("emits the count + key list header")
    func emitsHeader() throws {
        let h = CActionRegistryEmitter.emitHeader(actions)
        #expect(h.contains("#define CRCL_ACTION_REGISTRY_ENTRY_COUNT 2"))
        #expect(h.contains("//   action_tutorials_interfaces/action/Fibonacci"))
        #expect(h.contains("//   example_interfaces/action/Fibonacci"))
    }

    @Test("entries are sorted by canonical name regardless of input order")
    func sortsDeterministically() throws {
        let reversed = CActionRegistryEmitter.emit(actions.reversed())
        #expect(reversed == CActionRegistryEmitter.emit(actions))
        let tutorials = try #require(
            reversed.range(of: ".name = \"action_tutorials_interfaces/action/Fibonacci\""))
        let example = try #require(
            reversed.range(of: ".name = \"example_interfaces/action/Fibonacci\""))
        #expect(tutorials.lowerBound < example.lowerBound)
    }

    @Test("same-named actions in different packages get distinct wrapper symbols")
    func disambiguatesByPackage() throws {
        let c = CActionRegistryEmitter.emit(actions)
        #expect(c.contains("action_ts_example_interfaces__fibonacci"))
        #expect(c.contains("action_ts_action_tutorials_interfaces__fibonacci"))
    }

    // MARK: - GetResult splice guard

    private let slide = CActionRegistryEmitter.ActionRef(
        package: "test_interfaces", typeName: "Slide")

    private func result(_ fieldTypes: [FieldType]) -> MessageIR {
        MessageIR(
            package: "test_interfaces",
            typeName: "Slide_Result",
            kind: .action,
            fields: fieldTypes.enumerated().map { index, type in
                FieldIR(ros2Name: "field\(index)", swiftName: "field\(index)", type: type)
            }
        )
    }

    private func violation(
        _ fieldTypes: [FieldType], registry: [String: MessageIR] = [:]
    ) -> String? {
        CActionRegistryEmitter.resultSpliceViolation(
            action: slide, result: result(fieldTypes), registry: registry)
    }

    @Test("rejects a Result whose first field is 8-byte aligned")
    func rejectsEightByteAlignedFirstField() throws {
        for primitive in [PrimitiveType.float64, .int64, .uint64] {
            let message = try #require(violation([.primitive(primitive)]))
            #expect(message.contains("8-byte aligned"))
            #expect(message.contains("test_interfaces/action/Slide"))
            #expect(message.contains("offset 4"))
        }
        // Only the FIRST field matters — an 8-byte field later is fine.
        #expect(violation([.primitive(.int32), .primitive(.float64)]) == nil)
    }

    @Test("accepts Results whose first wire bytes are 4-byte aligned or smaller")
    func acceptsFourByteOrSmallerFirstField() throws {
        for primitive in [
            PrimitiveType.bool, .byte, .char, .int8, .uint8, .int16, .uint16,
            .int32, .uint32, .string, .wstring,
        ] {
            #expect(violation([.primitive(primitive)]) == nil)
        }
        // Sequences / bounded strings serialize a u32 count / length first —
        // even a sequence of float64 starts 4-byte aligned (Fibonacci shape).
        #expect(violation([.sequence(element: .primitive(.float64), upperBound: nil)]) == nil)
        #expect(violation([.boundedString(isWide: false, upperBound: 8)]) == nil)
        // An empty Result is a 1-byte rosidl dummy.
        #expect(violation([]) == nil)
    }

    @Test("fixed arrays inherit their element's alignment")
    func arraysInheritElementAlignment() throws {
        #expect(violation([.array(element: .primitive(.float64), length: 3)]) != nil)
        #expect(violation([.array(element: .primitive(.int32), length: 3)]) == nil)
    }

    @Test("nested first fields resolve through the registry")
    func nestedFirstFieldsResolveThroughRegistry() throws {
        let pose = MessageIR(
            package: "test_interfaces", typeName: "Pose", kind: .msg,
            fields: [
                FieldIR(ros2Name: "x", swiftName: "x", type: .primitive(.float64))
            ])
        let flag = MessageIR(
            package: "test_interfaces", typeName: "Flag", kind: .msg,
            fields: [
                FieldIR(ros2Name: "value", swiftName: "value", type: .primitive(.bool))
            ])
        let registry = [
            "test_interfaces/msg/Pose": pose,
            "test_interfaces/msg/Flag": flag,
        ]
        let nestedPose: FieldType = .nested(package: "test_interfaces", typeName: "Pose")
        let nestedFlag: FieldType = .nested(package: "test_interfaces", typeName: "Flag")
        #expect(violation([nestedPose], registry: registry) != nil)
        #expect(violation([nestedFlag], registry: registry) == nil)
        // Conservative: an unresolvable nested reference is rejected too.
        let message = try #require(violation([nestedPose]))
        #expect(message.contains("cannot be resolved"))
    }
}
