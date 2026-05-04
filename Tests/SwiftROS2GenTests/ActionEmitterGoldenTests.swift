import Foundation
import Testing

@testable import SwiftROS2Gen

@Suite("SwiftEmitter for ActionIR")
struct ActionEmitterGoldenTests {

    /// UUID + Time IRs sufficient for resolving the wrapper-level nested
    /// references when computing wrapper hashes. Mirrors the fixture pattern
    /// in ``ActionHashGoldenTests``.
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

    @Test("Fibonacci.swift matches the Phase-6 golden byte-for-byte")
    func fibonacciGolden() throws {
        let idl = try Parser.parseAction(
            source: "int32 order\n---\nint32[] sequence\n---\nint32[] sequence\n",
            file: "Fibonacci.action",
            package: "example_interfaces",
            typeName: "Fibonacci"
        )
        var ir = IRBuilder.build(jazzy: idl)
        IRBuilder.populateActionHashes(
            &ir, distro: "jazzy", extraRegistry: Self.extraRegistry())
        let emitted = SwiftEmitter.emit(
            ir,
            sourceLabel: "example_interfaces/action/Fibonacci.action",
            nestedNameOverrides: [
                "unique_identifier_msgs/msg/UUID": "UniqueIdentifierUUID"
            ]
        )

        let goldenURL = try #require(
            Bundle.module.url(
                forResource: "Fibonacci",
                withExtension: "swift",
                subdirectory: "Golden/Action"
            )
        )
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
        #expect(emitted == golden)
    }
}
