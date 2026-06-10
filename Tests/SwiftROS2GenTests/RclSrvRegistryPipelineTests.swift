import Foundation
import Testing

@testable import SwiftROS2Gen

/// End-to-end coverage for the M7 additions to
/// ``Pipeline/generateRclMarshalling(_:srvTypes:registryOnlyTypes:)``: the
/// generated service typesupport registry (`crcl_srv_registry.c` + header)
/// and the registry-only message entries in `crcl_marshal_registry.c`.
/// Exercises real vendor IDL with the same input + type sets as
/// `Scripts/regen-rcl-marshalling.sh`.
@Suite("Pipeline.generateRclMarshalling — M7 service registry + registry-only entries")
struct RclSrvRegistryPipelineTests {
    /// Repo root derived from this source file's path.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RclSrvRegistryPipelineTests.swift
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

    /// The full §20.3 service set, as the regen script passes it.
    private static let srvTypes: [String] = [
        "rcl_interfaces/srv/DescribeParameters",
        "rcl_interfaces/srv/GetParameterTypes",
        "rcl_interfaces/srv/GetParameters",
        "rcl_interfaces/srv/ListParameters",
        "rcl_interfaces/srv/SetParameters",
        "rcl_interfaces/srv/SetParametersAtomically",
        "std_srvs/srv/Empty",
        "std_srvs/srv/SetBool",
        "std_srvs/srv/Trigger",
        "example_interfaces/srv/AddTwoInts",
        "sensor_msgs/srv/SetCameraInfo",
        "action_msgs/srv/CancelGoal",
    ]

    private static let registryOnlyTypes: [String] = ["rcl_interfaces/msg/ParameterEvent"]

    /// The regen script's `--input` set (message allow-list narrowed to `Imu`
    /// to keep the marshalled emit set small — the service / registry-only
    /// paths under test are independent of it).
    private func m7Runs() -> [Pipeline.PackageRun] {
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
        try Pipeline.generateRclMarshalling(
            m7Runs(), srvTypes: Self.srvTypes, registryOnlyTypes: Self.registryOnlyTypes)
    }

    @Test("emits the srv registry C file + generated header alongside the message set")
    func emitsSrvRegistryFiles() throws {
        let paths = Set(try generate().map(\.relativePath))
        #expect(paths.contains("c/Generated/crcl_srv_registry.c"))
        #expect(paths.contains("c/include/Generated/crcl_srv_registry.h"))
        // The message-marshalling set is unchanged by the service additions.
        #expect(paths.contains("c/Generated/crcl_marshal_imu.c"))
        #expect(paths.contains("c/Generated/crcl_marshal_registry.c"))
        #expect(paths.contains("c/include/crcl_marshal.h"))
    }

    @Test("srv registry contains all 12 §20.3 entries, keyed pkg/srv/Type")
    func srvRegistryContainsAllEntries() throws {
        let files = try generate()
        let registry = try #require(
            files.first { $0.relativePath == "c/Generated/crcl_srv_registry.c" })
        for srvType in Self.srvTypes {
            #expect(registry.contents.contains(".name = \"\(srvType)\","))
        }
        let header = try #require(
            files.first { $0.relativePath == "c/include/Generated/crcl_srv_registry.h" })
        #expect(header.contents.contains("#define CRCL_SRV_REGISTRY_ENTRY_COUNT 12"))
    }

    @Test("registry-only type resolves in the message registry without marshal functions")
    func registryOnlyTypeHasNoMarshalFunctions() throws {
        let files = try generate()
        let registry = try #require(
            files.first { $0.relativePath == "c/Generated/crcl_marshal_registry.c" })
        #expect(registry.contents.contains("strcmp(name, \"rcl_interfaces/msg/ParameterEvent\")"))
        #expect(
            registry.contents.contains(
                "ROSIDL_GET_MSG_TYPE_SUPPORT(rcl_interfaces, msg, ParameterEvent)"))
        #expect(registry.contents.contains("#include <rcl_interfaces/msg/parameter_event.h>"))
        // Nothing else is emitted for it: no per-type marshal file, and no
        // crcl_publish_ / crcl_serialize_ symbols anywhere in the output.
        let paths = Set(files.map(\.relativePath))
        #expect(!paths.contains("c/Generated/crcl_marshal_parameter_event.c"))
        #expect(!paths.contains("c/include/Generated/crcl_marshal_parameter_event.h"))
        for file in files {
            #expect(!file.contents.contains("crcl_publish_parameter_event"))
            #expect(!file.contents.contains("crcl_serialize_parameter_event"))
        }
    }

    @Test("re-running yields byte-identical contents (deterministic)")
    func deterministic() throws {
        let first = try generate()
        let second = try generate()
        #expect(first == second)
    }

    @Test("throws on an unknown --rcl-srv-types entry")
    func throwsOnUnknownSrvType() throws {
        #expect(throws: GeneratorError.self) {
            _ = try Pipeline.generateRclMarshalling(
                m7Runs(), srvTypes: ["std_srvs/srv/Bogus"],
                registryOnlyTypes: Self.registryOnlyTypes)
        }
    }

    @Test("throws on an unknown --rcl-registry-only-types entry")
    func throwsOnUnknownRegistryOnlyType() throws {
        #expect(throws: GeneratorError.self) {
            _ = try Pipeline.generateRclMarshalling(
                m7Runs(), srvTypes: Self.srvTypes,
                registryOnlyTypes: ["rcl_interfaces/msg/Bogus"])
        }
    }

    @Test("omits the srv registry files when no service types are requested")
    func omitsSrvRegistryWhenEmpty() throws {
        let files = try Pipeline.generateRclMarshalling(m7Runs())
        let paths = Set(files.map(\.relativePath))
        #expect(!paths.contains("c/Generated/crcl_srv_registry.c"))
        #expect(!paths.contains("c/include/Generated/crcl_srv_registry.h"))
    }
}
