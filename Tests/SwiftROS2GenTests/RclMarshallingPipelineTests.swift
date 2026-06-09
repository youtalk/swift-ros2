import Foundation
import Testing

@testable import SwiftROS2Gen

/// End-to-end coverage for ``Pipeline/generateRclMarshalling(_:)`` — the native-RCL
/// marshalling entry point that produces the C source / header, the Swift
/// unpacker, the typesupport registry, and the aggregator header from real
/// vendor IDL.
@Suite("Pipeline.generateRclMarshalling — native-RCL emit set")
struct RclMarshallingPipelineTests {
    /// Repo root derived from this source file's path.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RclMarshallingPipelineTests.swift
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

    /// The same `--input` set the CLI passes for `--types Imu`: sensor_msgs plus
    /// every nested dependency (std_msgs/Header, geometry_msgs, builtin_interfaces).
    /// The CLI applies the *same* `--types` allow-list to every input, so each
    /// run carries `["Imu"]`; the nested packages contribute their IRs only to
    /// the flattening registry, never to the emit set.
    private func imuRuns() -> [Pipeline.PackageRun] {
        let allow: Set<String> = ["Imu"]
        return [
            .init(
                input: PackageInput(
                    name: "sensor_msgs",
                    directory: Self.vendor("common_interfaces-jazzy/sensor_msgs")),
                typesAllowList: allow),
            .init(
                input: PackageInput(
                    name: "std_msgs",
                    directory: Self.vendor("common_interfaces-jazzy/std_msgs")),
                typesAllowList: allow),
            .init(
                input: PackageInput(
                    name: "geometry_msgs",
                    directory: Self.vendor("common_interfaces-jazzy/geometry_msgs")),
                typesAllowList: allow),
            .init(
                input: PackageInput(
                    name: "builtin_interfaces",
                    directory: Self.vendor("rcl_interfaces-jazzy/builtin_interfaces")),
                typesAllowList: allow),
        ]
    }

    @Test("emits the expected file set for --types Imu")
    func emitsImuFileSet() throws {
        let files = try Pipeline.generateRclMarshalling(imuRuns())
        let paths = Set(files.map(\.relativePath))
        #expect(
            paths
                == Set([
                    "c/Generated/crcl_marshal_imu.c",
                    "c/include/Generated/crcl_marshal_imu.h",
                    "swift/Imu+RclMarshal.swift",
                    "c/Generated/crcl_marshal_registry.c",
                    "c/include/crcl_marshal.h",
                ]))
    }

    @Test("registry resolves sensor_msgs/msg/Imu to crcl_typesupport_imu")
    func registryResolvesImu() throws {
        let files = try Pipeline.generateRclMarshalling(imuRuns())
        let registry = try #require(
            files.first { $0.relativePath == "c/Generated/crcl_marshal_registry.c" })
        #expect(registry.contents.contains("strcmp(name, \"sensor_msgs/msg/Imu\")"))
        #expect(registry.contents.contains("crcl_typesupport_imu()"))
    }

    @Test("aggregator header includes the per-type header and declares the resolver")
    func aggregatorHeader() throws {
        let files = try Pipeline.generateRclMarshalling(imuRuns())
        let agg = try #require(files.first { $0.relativePath == "c/include/crcl_marshal.h" })
        #expect(agg.contents.contains("#include \"Generated/crcl_marshal_imu.h\""))
        #expect(
            agg.contents.contains(
                "const rosidl_message_type_support_t *crcl_marshal_resolve_typesupport(const char *name);"))
    }

    @Test("re-running yields byte-identical contents (deterministic)")
    func deterministic() throws {
        let first = try Pipeline.generateRclMarshalling(imuRuns())
        let second = try Pipeline.generateRclMarshalling(imuRuns())
        #expect(first == second)
    }

    /// Same `--input` set, but the allow-list is a typo (`Imuu`) that resolves
    /// to no `<pkg>/msg/<Type>` registry key. A silent zero-file generation
    /// would let the regen-drift CI guard pass while the type is absent, so the
    /// generator must hard-fail instead.
    private func bogusTypeRuns() -> [Pipeline.PackageRun] {
        let allow: Set<String> = ["Imuu"]
        return [
            .init(
                input: PackageInput(
                    name: "sensor_msgs",
                    directory: Self.vendor("common_interfaces-jazzy/sensor_msgs")),
                typesAllowList: allow),
            .init(
                input: PackageInput(
                    name: "std_msgs",
                    directory: Self.vendor("common_interfaces-jazzy/std_msgs")),
                typesAllowList: allow),
            .init(
                input: PackageInput(
                    name: "geometry_msgs",
                    directory: Self.vendor("common_interfaces-jazzy/geometry_msgs")),
                typesAllowList: allow),
            .init(
                input: PackageInput(
                    name: "builtin_interfaces",
                    directory: Self.vendor("rcl_interfaces-jazzy/builtin_interfaces")),
                typesAllowList: allow),
        ]
    }

    @Test("throws on a bogus --types entry instead of silently emitting nothing")
    func throwsOnUnknownRequestedType() throws {
        #expect(throws: GeneratorError.self) {
            _ = try Pipeline.generateRclMarshalling(bogusTypeRuns())
        }
    }
}
