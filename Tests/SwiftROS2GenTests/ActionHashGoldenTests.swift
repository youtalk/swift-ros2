import Testing

@testable import SwiftROS2Gen

@Suite("RIHS01 action hashes — Phase 6 golden")
struct ActionHashGoldenTests {

    /// Build the minimal extra registry needed to resolve the wrapper-level
    /// nested references (UUID and Time). Mirrors the fixture pattern in
    /// `HashGoldenPhase3Tests.actionRegistry()`.
    private static func extraRegistry() -> [String: MessageIR] {
        let uuid = MessageIR(
            package: "unique_identifier_msgs", typeName: "UUID",
            fields: [
                FieldIR(
                    ros2Name: "uuid", swiftName: "uuid",
                    type: .array(element: .primitive(.uint8), length: 16))
            ]
        )
        let time = MessageIR(
            package: "builtin_interfaces", typeName: "Time",
            fields: [
                FieldIR(ros2Name: "sec", swiftName: "sec", type: .primitive(.int32)),
                FieldIR(ros2Name: "nanosec", swiftName: "nanosec", type: .primitive(.uint32)),
            ]
        )
        return [
            uuid.rosTypeName: uuid,
            time.rosTypeName: time,
        ]
    }

    @Test("Fibonacci action — 8 hashes match upstream rosidl JSON descriptions")
    func fibonacciHashes() throws {
        let idl = try Parser.parseAction(
            source: "int32 order\n---\nint32[] sequence\n---\nint32[] sequence\n",
            file: "Fibonacci.action",
            package: "example_interfaces",
            typeName: "Fibonacci"
        )
        var ir = IRBuilder.build(jazzy: idl)
        IRBuilder.populateActionHashes(
            &ir, distro: "jazzy", extraRegistry: Self.extraRegistry())
        let h = try #require(ir.perDistroHashes["jazzy"])

        // Pinned against `osrf/ros:jazzy-desktop` `ros2 interface show`
        // type_hashes for `example_interfaces/action/Fibonacci`.
        #expect(
            h.goalHash
                == "RIHS01_226cb437e4355dcd3e914f930382a3b0cc1da81545bd319ed554e95a03255f51")
        #expect(
            h.resultHash
                == "RIHS01_fea81394f25aa4502217953f1a021fb750e79c10bbd43f13dd94632da6569649")
        #expect(
            h.feedbackHash
                == "RIHS01_2b12e37361da6f408d4c85bc24a18de64333f29082f2ca34b5ee33dc4c8b42a9")
        #expect(
            h.sendGoalRequestHash
                == "RIHS01_3d088942b413247db536576f0286768c6be8fcd5d0c9a5d544f359fba090a238")
        #expect(
            h.sendGoalResponseHash
                == "RIHS01_d8c07bb3d5b766fe4b43159c9a5222af5214e2fcc29229b991d826166c512be1")
        #expect(
            h.getResultRequestHash
                == "RIHS01_c8a4f5e7d13b81286ee1043e2ecd084281cecf1ff06aaa799464f5f15479f003")
        #expect(
            h.getResultResponseHash
                == "RIHS01_6021dc98ab9b4bbe395e48aa4de81ee5f68eb570f88358affcc648146668b24f")
        #expect(
            h.feedbackMessageHash
                == "RIHS01_c1de71afd52e49a89c53d8262366884185bc0a02f78ce051c4e46b0a7fe59bb2")
        // No action-level (`<pkg>/action/<Type>`) hash is exposed: rosidl
        // computes it from a six-field record that references additional
        // service-shaped wrappers (`Fibonacci_SendGoal`, `Fibonacci_GetResult`,
        // their `_Event` siblings, and `service_msgs/msg/ServiceEventInfo`)
        // that this generator does not emit. See ``IRBuilder/populateActionHashes``.
    }
}
