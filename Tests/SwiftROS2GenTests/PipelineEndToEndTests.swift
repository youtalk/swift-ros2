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
