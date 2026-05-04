import Foundation
import Testing

@testable import SwiftROS2Gen

@Suite("Pipeline.generateMulti multi-distro smoke")
struct PipelineMultiDistroSmokeTests {
    @Test("emits one distro-conditional file when two distros disagree")
    func emitsConditionalFile() throws {
        // Build two synthetic vendor directories under tmp, one per distro,
        // both containing a `Foo.msg`. The Jazzy version adds a field.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "swift-ros2-gen-pipeline-test-\(UUID().uuidString)",
                isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let humbleDir = tmp.appendingPathComponent("humble/demo_msgs/msg")
        let jazzyDir = tmp.appendingPathComponent("jazzy/demo_msgs/msg")
        try FileManager.default.createDirectory(
            at: humbleDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: jazzyDir, withIntermediateDirectories: true)
        try "int32 a\n".write(
            to: humbleDir.appendingPathComponent("Foo.msg"),
            atomically: true, encoding: .utf8)
        try "int32 a\nint32 b\n".write(
            to: jazzyDir.appendingPathComponent("Foo.msg"),
            atomically: true, encoding: .utf8)

        let runs = [
            Pipeline.PackageRun(
                input: PackageInput(
                    name: "demo_msgs",
                    directory: humbleDir.deletingLastPathComponent(),
                    distro: "humble"
                )),
            Pipeline.PackageRun(
                input: PackageInput(
                    name: "demo_msgs",
                    directory: jazzyDir.deletingLastPathComponent(),
                    distro: "jazzy"
                )),
        ]
        let files = try Pipeline.generateMulti(runs)
        #expect(files.count == 1)
        #expect(files[0].relativePath == "DemoMsgs/Foo.swift")
        let body = files[0].contents
        // The conditional emitter triggers on per-distro field divergence.
        #expect(body.contains("typeInfo(for distro: ROS2Distro)"))
        #expect(body.contains("if !encoder.isLegacySchema"))
        #expect(body.contains("if decoder.isLegacySchema"))
    }
}

@Suite("Pipeline multi-distro end-to-end on vendor sensor_msgs")
struct PipelineMultiDistroEndToEndTests {
    @Test("emits byte-identical files to those checked into Generated/SensorMsgs")
    func emitsByteIdenticalFiles() throws {
        // The repo root is two levels above this test source file's parent
        // (Tests/SwiftROS2GenTests/<file>.swift -> Tests/<file>.swift -> repo).
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot =
            thisFile
            .deletingLastPathComponent()  // PipelineMultiDistroTests.swift
            .deletingLastPathComponent()  // SwiftROS2GenTests
            .deletingLastPathComponent()  // Tests
        let humbleSensors =
            repoRoot
            .appendingPathComponent("vendor")
            .appendingPathComponent("common_interfaces-humble")
            .appendingPathComponent("sensor_msgs")
        let jazzySensors =
            repoRoot
            .appendingPathComponent("vendor")
            .appendingPathComponent("common_interfaces-jazzy")
            .appendingPathComponent("sensor_msgs")
        let stdMsgs =
            repoRoot
            .appendingPathComponent("vendor")
            .appendingPathComponent("common_interfaces-jazzy")
            .appendingPathComponent("std_msgs")
        let geometryMsgs =
            repoRoot
            .appendingPathComponent("vendor")
            .appendingPathComponent("common_interfaces-jazzy")
            .appendingPathComponent("geometry_msgs")
        let builtinInterfaces =
            repoRoot
            .appendingPathComponent("vendor")
            .appendingPathComponent("rcl_interfaces-jazzy")
            .appendingPathComponent("builtin_interfaces")
        // Skip when any required submodule is missing — the test only runs
        // in environments that have initialized every dependency submodule.
        for url in [humbleSensors, jazzySensors, stdMsgs, geometryMsgs, builtinInterfaces] {
            let msgDir = url.appendingPathComponent("msg")
            guard FileManager.default.fileExists(atPath: msgDir.path) else {
                // Use #expect(true) instead of skip — this keeps the suite
                // green on CI shapes that do not init the rcl_interfaces
                // submodule (the lint-only image).
                return
            }
        }

        let runs: [Pipeline.PackageRun] = [
            .init(
                input: PackageInput(
                    name: "sensor_msgs", directory: humbleSensors, distro: "humble")),
            .init(
                input: PackageInput(
                    name: "sensor_msgs", directory: jazzySensors, distro: "jazzy")),
            .init(input: PackageInput(name: "std_msgs", directory: stdMsgs)),
            .init(input: PackageInput(name: "geometry_msgs", directory: geometryMsgs)),
            .init(
                input: PackageInput(
                    name: "builtin_interfaces", directory: builtinInterfaces)),
        ]
        let files = try Pipeline.generateMulti(runs)
        let generatedRoot =
            repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("SwiftROS2Messages")
            .appendingPathComponent("Generated")
        // Limit to the 15 sensor_msgs types this phase committed.
        let typesUnderTest: Set<String> = [
            "BatteryState", "CameraInfo", "CompressedImage", "FluidPressure",
            "Illuminance", "Image", "Imu", "Joy", "MagneticField", "NavSatFix",
            "PointCloud2", "PointField", "Range", "RegionOfInterest", "Temperature",
        ]
        var matched = 0
        for file in files where file.relativePath.hasPrefix("SensorMsgs/") {
            let onDiskName = file.relativePath.split(separator: "/").last.map(String.init)!
            let stem = (onDiskName as NSString).deletingPathExtension
            guard typesUnderTest.contains(stem) else { continue }
            let onDiskURL = generatedRoot.appendingPathComponent(file.relativePath)
            let onDisk = try String(contentsOf: onDiskURL, encoding: .utf8)
            #expect(file.contents == onDisk, "drift in \(file.relativePath)")
            matched += 1
        }
        #expect(matched == typesUnderTest.count, "expected \(typesUnderTest.count) matches, got \(matched)")
    }
}
