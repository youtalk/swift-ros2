import Foundation
import Testing

@testable import SwiftROS2Gen

@Suite("Pipeline.generateMulti (action discovery)")
struct ActionPipelineEndToEndTests {

    @Test("emits exactly one FibonacciAction.swift from example_interfaces/action/")
    func emitsFibonacci() throws {
        let actionURL = try #require(
            Bundle.module.url(
                forResource: "Fibonacci",
                withExtension: "action",
                subdirectory: "Resources/IDL/example_interfaces/action"
            )
        )
        // The package directory is the parent of the `action/` directory the
        // resource lives in. Resources are flattened by SwiftPM, so the URL
        // reads `…/IDL/example_interfaces/action/Fibonacci.action`.
        let packageDir = actionURL
            .deletingLastPathComponent()  // …/example_interfaces/action
            .deletingLastPathComponent()  // …/example_interfaces

        // Pull cross-package nested deps (UUID, Time) from the existing vendor
        // submodules; the action wrappers cannot resolve `goal_id` / `stamp`
        // without them.
        let uuidURL = try #require(
            Bundle.module.url(
                forResource: "UUID",
                withExtension: "msg",
                subdirectory: "Resources/IDL/unique_identifier_msgs/msg"
            )
        )
        let uuidPkgDir = uuidURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let timeURL = try #require(
            Bundle.module.url(
                forResource: "Time",
                withExtension: "msg",
                subdirectory: "Resources/IDL/builtin_interfaces/msg"
            )
        )
        let timePkgDir = timeURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let files = try Pipeline.generateMulti([
            .init(
                input: PackageInput(name: "example_interfaces", directory: packageDir),
                typesAllowList: ["Fibonacci"]
            ),
            .init(
                input: PackageInput(
                    name: "unique_identifier_msgs", directory: uuidPkgDir),
                typesAllowList: ["UUID"]
            ),
            .init(
                input: PackageInput(name: "builtin_interfaces", directory: timePkgDir),
                typesAllowList: ["Time"]
            ),
        ])
        let action = try #require(
            files.first { $0.relativePath == "ExampleInterfaces/FibonacciAction.swift" }
        )
        #expect(
            action.contents.contains("public enum FibonacciAction: ROS2Action"))
        #expect(
            action.contents.contains("public struct Fibonacci_SendGoal_Request"))
        #expect(
            action.contents.contains("public struct Fibonacci_SendGoal_Response"))
        #expect(
            action.contents.contains("public struct Fibonacci_GetResult_Request"))
        #expect(
            action.contents.contains("public struct Fibonacci_GetResult_Response"))
        #expect(
            action.contents.contains("public struct Fibonacci_FeedbackMessage"))
    }
}
