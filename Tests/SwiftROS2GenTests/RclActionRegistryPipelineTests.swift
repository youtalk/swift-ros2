import Foundation
import Testing

@testable import SwiftROS2Gen

/// End-to-end coverage for the M8a additions to
/// ``Pipeline/generateRclMarshalling(_:srvTypes:actionTypes:registryOnlyTypes:)``:
/// the generated action typesupport registry (`crcl_action_registry.c` +
/// header). Exercises real vendor IDL with the same input + type sets as
/// `Scripts/regen-rcl-marshalling.sh`.
@Suite("Pipeline.generateRclMarshalling — M8 action registry")
struct RclActionRegistryPipelineTests {
    /// Repo root derived from this source file's path.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RclActionRegistryPipelineTests.swift
            .deletingLastPathComponent()  // SwiftROS2GenTests
            .deletingLastPathComponent()  // Tests
    }

    private static func vendor(_ relative: String) -> URL {
        var url = repoRoot.appendingPathComponent("vendor")
        for segment in relative.split(separator: "/") {
            url = url.appendingPathComponent(String(segment))
        }
        return url
    }

    /// The M8 action set, as the regen script passes it.
    private static let actionTypes: [String] = ["example_interfaces/action/Fibonacci"]

    /// The regen script's `--input` set (message allow-list narrowed to `Imu`
    /// to keep the marshalled emit set small — the action registry path under
    /// test is independent of it).
    private func m8Runs() -> [Pipeline.PackageRun] {
        let allow: Set<String> = ["Imu"]
        let inputs: [(name: String, path: String)] = [
            ("sensor_msgs", "common_interfaces-jazzy/sensor_msgs"),
            ("std_msgs", "common_interfaces-jazzy/std_msgs"),
            ("geometry_msgs", "common_interfaces-jazzy/geometry_msgs"),
            ("builtin_interfaces", "rcl_interfaces-jazzy/builtin_interfaces"),
            ("rcl_interfaces", "rcl_interfaces-jazzy/rcl_interfaces"),
            ("std_srvs", "common_interfaces-jazzy/std_srvs"),
            ("example_interfaces", "example_interfaces-jazzy"),
            ("action_msgs", "rcl_interfaces-jazzy/action_msgs"),
            ("unique_identifier_msgs", "unique_identifier_msgs"),
        ]
        return inputs.map {
            .init(
                input: PackageInput(name: $0.name, directory: Self.vendor($0.path)),
                typesAllowList: allow)
        }
    }

    private func generate() throws -> [GeneratedFile] {
        try Pipeline.generateRclMarshalling(m8Runs(), actionTypes: Self.actionTypes)
    }

    @Test("emits the action registry C file + generated header alongside the message set")
    func emitsActionRegistryFiles() throws {
        let paths = Set(try generate().map(\.relativePath))
        #expect(paths.contains("c/Generated/crcl_action_registry.c"))
        #expect(paths.contains("c/include/Generated/crcl_action_registry.h"))
        // The message-marshalling set is unchanged by the action additions.
        #expect(paths.contains("c/Generated/crcl_marshal_imu.c"))
        #expect(paths.contains("c/Generated/crcl_marshal_registry.c"))
        #expect(paths.contains("c/include/crcl_marshal.h"))
    }

    @Test("action registry entry is keyed pkg/action/Type with all 5 wrapper roles")
    func actionRegistryEntryIsComplete() throws {
        let files = try generate()
        let registry = try #require(
            files.first { $0.relativePath == "c/Generated/crcl_action_registry.c" })
        #expect(registry.contents.contains(".name = \"example_interfaces/action/Fibonacci\","))
        #expect(
            registry.contents.contains(
                "ROSIDL_GET_ACTION_TYPE_SUPPORT(example_interfaces, Fibonacci)"))
        for role in [
            "SendGoal_Request", "SendGoal_Response",
            "GetResult_Request", "GetResult_Response",
            "FeedbackMessage",
        ] {
            #expect(
                registry.contents.contains(
                    "ROSIDL_GET_MSG_TYPE_SUPPORT(example_interfaces, action, Fibonacci_\(role))"))
            #expect(
                registry.contents.contains(
                    "example_interfaces__action__Fibonacci_\(role)__create();"))
        }
        let header = try #require(
            files.first { $0.relativePath == "c/include/Generated/crcl_action_registry.h" })
        #expect(header.contents.contains("#define CRCL_ACTION_REGISTRY_ENTRY_COUNT 1"))
        #expect(header.contents.contains("//   example_interfaces/action/Fibonacci"))
    }

    @Test("re-running yields byte-identical contents (deterministic)")
    func deterministic() throws {
        let first = try generate()
        let second = try generate()
        #expect(first == second)
    }

    @Test("throws on an unknown --rcl-action-types entry")
    func throwsOnUnknownActionType() throws {
        #expect(throws: GeneratorError.self) {
            _ = try Pipeline.generateRclMarshalling(
                m8Runs(), actionTypes: ["example_interfaces/action/Bogus"])
        }
    }

    @Test("omits the action registry files when no action types are requested")
    func omitsActionRegistryWhenEmpty() throws {
        let files = try Pipeline.generateRclMarshalling(m8Runs())
        let paths = Set(files.map(\.relativePath))
        #expect(!paths.contains("c/Generated/crcl_action_registry.c"))
        #expect(!paths.contains("c/include/Generated/crcl_action_registry.h"))
    }

    @Test("rejects an action whose Result starts with an 8-byte-aligned field (splice guard)")
    func rejectsEightByteAlignedResultFirstField() throws {
        // The byte seam splices the Result body at fixed CDR offset 4 after
        // [header|status|pad3]; a Result whose first field is float64 /
        // int64 / uint64 would be silently corrupted, so registry generation
        // must hard-fail for it.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("swift-ros2-splice-guard-\(UUID().uuidString)", isDirectory: true)
        let packageDir = tmp.appendingPathComponent("bad_interfaces", isDirectory: true)
        let actionDir = packageDir.appendingPathComponent("action", isDirectory: true)
        try FileManager.default.createDirectory(at: actionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let action = """
            int32 target
            ---
            float64 final_position
            ---
            int32 progress
            """
        try action.write(
            to: actionDir.appendingPathComponent("Slide.action"), atomically: true,
            encoding: .utf8)
        let badRun = Pipeline.PackageRun(
            input: PackageInput(name: "bad_interfaces", directory: packageDir))
        do {
            _ = try Pipeline.generateRclMarshalling(
                m8Runs() + [badRun],
                actionTypes: Self.actionTypes + ["bad_interfaces/action/Slide"])
            Issue.record("expected the GetResult splice guard to throw")
        } catch let error as GeneratorError {
            let description = "\(error)"
            #expect(description.contains("bad_interfaces/action/Slide"))
            #expect(description.contains("8-byte aligned"))
        }
    }
}
