import Foundation
import Testing

@testable import SwiftROS2Gen

@Suite("Pipeline end-to-end")
struct PipelineEndToEndTests {
    @Test("Phase 1: single primitive-only package")
    func generatesAllStdMsgsPrimitives() throws {
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "std_msgs_primitives", withExtension: nil, subdirectory: "Resources/IDL"))
        let files = try Pipeline.generate(
            for: PackageInput(name: "std_msgs", directory: fixtureURL))
        let names = Set(files.map(\.relativePath))
        #expect(
            names
                == Set([
                    "StdMsgs/BoolMsg.swift", "StdMsgs/EmptyMsg.swift",
                    "StdMsgs/Float64Msg.swift", "StdMsgs/Int32Msg.swift", "StdMsgs/StringMsg.swift",
                ]))
    }

    @Test("Phase 2: three-package run resolves cross-package references")
    func generatesGeometryPlusBuiltinPlusHeader() throws {
        let bi = try #require(
            Bundle.module.url(
                forResource: "builtin_interfaces", withExtension: nil, subdirectory: "Resources/IDL"))
        let gm = try #require(
            Bundle.module.url(
                forResource: "geometry_msgs", withExtension: nil, subdirectory: "Resources/IDL"))
        let sm = try #require(
            Bundle.module.url(
                forResource: "std_msgs_with_header", withExtension: nil, subdirectory: "Resources/IDL"))
        let files = try Pipeline.generateMulti([
            .init(
                input: PackageInput(name: "builtin_interfaces", directory: bi),
                typesAllowList: ["Time", "Duration"]),
            .init(
                input: PackageInput(name: "geometry_msgs", directory: gm),
                typesAllowList: [
                    "Vector3", "Quaternion", "Point", "Pose", "Twist",
                    "Transform", "TransformStamped", "PoseStamped", "TwistStamped",
                    "Vector3Stamped", "Wrench", "Accel",
                ]),
            .init(
                input: PackageInput(name: "std_msgs", directory: sm),
                typesAllowList: ["Header"]),
        ])
        let names = Set(files.map(\.relativePath))
        #expect(names.contains("BuiltinInterfaces/Time.swift"))
        #expect(names.contains("BuiltinInterfaces/Duration.swift"))
        #expect(names.contains("GeometryMsgs/Vector3.swift"))
        #expect(names.contains("GeometryMsgs/Pose.swift"))
        #expect(names.contains("GeometryMsgs/PoseStamped.swift"))
        #expect(names.contains("StdMsgs/Header.swift"))
    }

    @Test("typo'd --input directory throws GeneratorError.packageDirectoryMissing (single-package path)")
    func missingInputDirectoryThrowsSinglePackage() throws {
        // Construct a path that does not exist on disk so the pipeline must
        // surface it as a hard error rather than silently producing zero
        // files (the srv-only tolerance must not mask this).
        let bogus = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "swift-ros2-gen-missing-\(UUID().uuidString)", isDirectory: true)
        do {
            _ = try Pipeline.generateMulti([
                .init(input: PackageInput(name: "std_msgs", directory: bogus))
            ])
            Issue.record("expected GeneratorError.packageDirectoryMissing")
        } catch GeneratorError.packageDirectoryMissing(let url) {
            #expect(url == bogus)
        } catch {
            Issue.record("expected GeneratorError.packageDirectoryMissing, got \(error)")
        }
    }

    @Test(
        "typo'd --input directory for one distro throws GeneratorError.packageDirectoryMissing (multi-distro path)"
    )
    func missingInputDirectoryThrowsMultiDistro() throws {
        // Pair a real package directory (jazzy) with a typo'd humble path
        // for the same package name so generateMulti routes through the
        // multi-distro merge. The bad path must not be silently `continue`d.
        let jazzy = try #require(
            Bundle.module.url(
                forResource: "std_msgs_primitives",
                withExtension: nil,
                subdirectory: "Resources/IDL"))
        let bogusHumble = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "swift-ros2-gen-missing-\(UUID().uuidString)", isDirectory: true)
        do {
            _ = try Pipeline.generateMulti([
                .init(
                    input: PackageInput(
                        name: "std_msgs", directory: jazzy, distro: "jazzy")),
                .init(
                    input: PackageInput(
                        name: "std_msgs", directory: bogusHumble, distro: "humble")),
            ])
            Issue.record("expected GeneratorError.packageDirectoryMissing")
        } catch GeneratorError.packageDirectoryMissing(let url) {
            #expect(url == bogusHumble)
        } catch {
            Issue.record("expected GeneratorError.packageDirectoryMissing, got \(error)")
        }
    }

    @Test("unresolved cross-package reference throws GeneratorError.unresolvedNestedType")
    func unresolvedReferenceThrows() throws {
        let sm = try #require(
            Bundle.module.url(
                forResource: "std_msgs_with_header", withExtension: nil, subdirectory: "Resources/IDL"))
        do {
            _ = try Pipeline.generateMulti([
                .init(
                    input: PackageInput(name: "std_msgs", directory: sm),
                    typesAllowList: ["Header"])
            ])
            Issue.record("expected GeneratorError.unresolvedNestedType")
        } catch GeneratorError.unresolvedNestedType(let pkg, let type) {
            #expect(pkg == "builtin_interfaces")
            #expect(type == "Time")
        } catch {
            Issue.record("expected GeneratorError.unresolvedNestedType, got \(error)")
        }
    }
}
