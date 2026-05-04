import Foundation
import Testing

/// Copy of `SwiftROS2GenPlugin.outputFileURL(for:packageName:outputRoot:)`,
/// `SwiftROS2GenPlugin.swiftStructName(typeName:)`, and
/// `SwiftROS2GenPlugin.pascal(_:)`. SwiftPM does not expose plugin
/// module sources to test targets, so the helper is duplicated here.
/// If the plugin's naming rule changes, both copies must change in
/// lockstep.
private enum PluginNaming {
    static let collisionTypeNames: Set<String> = [
        "Bool", "String",
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Float", "Float32", "Float64", "Double",
        "Empty",
    ]

    static func swiftStructName(typeName: String) -> String {
        collisionTypeNames.contains(typeName) ? typeName + "Msg" : typeName
    }

    static func outputFileURL(for input: URL, packageName: String, outputRoot: URL) -> URL {
        let typeName = input.deletingPathExtension().lastPathComponent
        let pascalPackage = pascal(packageName)
        let structName = swiftStructName(typeName: typeName)
        let fileName = "\(structName).swift"
        return outputRoot.appending(path: pascalPackage).appending(path: fileName)
    }

    static func pascal(_ snake: String) -> String {
        snake.split(separator: "_").map {
            $0.prefix(1).uppercased() + $0.dropFirst().lowercased()
        }.joined()
    }
}

@Suite("SwiftROS2GenPlugin naming")
struct PluginNamingTests {
    @Test("snake_case package becomes PascalCase directory")
    func pascalCasesSnakePackages() {
        #expect(PluginNaming.pascal("std_msgs") == "StdMsgs")
        #expect(PluginNaming.pascal("sensor_msgs") == "SensorMsgs")
        #expect(PluginNaming.pascal("nav2_msgs") == "Nav2Msgs")
        #expect(PluginNaming.pascal("simple") == "Simple")
    }

    @Test("collision type names get the Msg suffix")
    func collisionNamesGetMsgSuffix() {
        #expect(PluginNaming.swiftStructName(typeName: "Bool") == "BoolMsg")
        #expect(PluginNaming.swiftStructName(typeName: "String") == "StringMsg")
        #expect(PluginNaming.swiftStructName(typeName: "Int32") == "Int32Msg")
        #expect(PluginNaming.swiftStructName(typeName: "Float64") == "Float64Msg")
        #expect(PluginNaming.swiftStructName(typeName: "Empty") == "EmptyMsg")
    }

    @Test("non-collision type names emit bare PascalCase")
    func nonCollisionNamesAreBare() {
        #expect(PluginNaming.swiftStructName(typeName: "Header") == "Header")
        #expect(PluginNaming.swiftStructName(typeName: "Imu") == "Imu")
        #expect(PluginNaming.swiftStructName(typeName: "BatteryState") == "BatteryState")
    }

    @Test("output file URL appends Msg suffix only for collision names")
    func outputPathStructure() {
        let outputRoot = URL(fileURLWithPath: "/tmp/wd/Generated", isDirectory: true)
        let collidingInput = URL(fileURLWithPath: "/some/where/msg/Bool.msg")
        let collidingURL = PluginNaming.outputFileURL(
            for: collidingInput, packageName: "std_msgs", outputRoot: outputRoot)
        #expect(collidingURL.path == "/tmp/wd/Generated/StdMsgs/BoolMsg.swift")

        let bareInput = URL(fileURLWithPath: "/some/where/msg/Imu.msg")
        let bareURL = PluginNaming.outputFileURL(
            for: bareInput, packageName: "sensor_msgs", outputRoot: outputRoot)
        #expect(bareURL.path == "/tmp/wd/Generated/SensorMsgs/Imu.swift")
    }

    @Test("multiple inputs each get one output, names mirror Pipeline.swift")
    func multipleInputs() {
        let outputRoot = URL(fileURLWithPath: "/wd", isDirectory: true)
        let inputs = ["Bool", "Empty", "Float64", "Int32", "String"].map {
            URL(fileURLWithPath: "/x/msg/\($0).msg")
        }
        let outputs = inputs.map {
            PluginNaming.outputFileURL(
                for: $0, packageName: "std_msgs", outputRoot: outputRoot
            ).lastPathComponent
        }
        #expect(
            outputs == [
                "BoolMsg.swift", "EmptyMsg.swift", "Float64Msg.swift", "Int32Msg.swift",
                "StringMsg.swift",
            ])
    }
}
