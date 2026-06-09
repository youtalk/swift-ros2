import Foundation

@testable import SwiftROS2Gen

/// Shared test fixture: a fully-resolved `[rosTypeName: MessageIR]` registry
/// covering the five native-RCL M3b target message types plus every nested
/// dependency they reach. Built from the jazzy vendor IDL submodules so the
/// flattener / C-emitter tests recurse into real field layouts rather than
/// hand-mocked IRs.
enum TestIR {
    /// Repo root, derived from this source file's path
    /// (`Tests/SwiftROS2GenTests/TestIR.swift` -> repo root three levels up).
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TestIR.swift
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

    /// Registry keyed by `<pkg>/msg/<Type>` containing `sensor_msgs/{Imu, Joy,
    /// PointCloud2, PointField, BatteryState, CompressedImage}` and the nested
    /// `std_msgs/Header`, `geometry_msgs/{Quaternion, Vector3}`, and
    /// `builtin_interfaces/Time` they depend on.
    static func sensorMsgsRegistry() throws -> [String: MessageIR] {
        let runs: [Pipeline.PackageRun] = [
            .init(
                input: PackageInput(
                    name: "sensor_msgs",
                    directory: vendor("common_interfaces-jazzy/sensor_msgs")
                ),
                typesAllowList: [
                    "Imu", "Joy", "PointCloud2", "PointField", "BatteryState", "CompressedImage",
                ]
            ),
            .init(
                input: PackageInput(
                    name: "std_msgs",
                    directory: vendor("common_interfaces-jazzy/std_msgs")
                ),
                typesAllowList: ["Header"]
            ),
            .init(
                input: PackageInput(
                    name: "geometry_msgs",
                    directory: vendor("common_interfaces-jazzy/geometry_msgs")
                ),
                typesAllowList: ["Quaternion", "Vector3"]
            ),
            .init(
                input: PackageInput(
                    name: "builtin_interfaces",
                    directory: vendor("rcl_interfaces-jazzy/builtin_interfaces")
                ),
                typesAllowList: ["Time"]
            ),
        ]
        return try Pipeline.buildMessageRegistry(runs)
    }
}
