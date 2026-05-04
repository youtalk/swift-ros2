// Generated source: invokes the `swift-ros2-gen` executable on the
// host target's msg/ directory and emits one Swift file per .msg
// input under the plugin's per-target work directory.
//
// Naming rule mirrored from SwiftROS2Gen.Pipeline / SwiftEmitter
// (Phase 2+): the per-package directory is PascalCase(package); the
// per-type filename is the bare PascalCase type name, with a trailing
// `Msg` only when the type collides with a Swift stdlib name (Bool,
// String, Int*, UInt*, Float*, Double, plus Empty kept by ROS
// convention). If `Sources/SwiftROS2Gen/Emitter/SwiftEmitter.swift`
// changes the collision set or drops the `Msg` rule, update
// `swiftStructName(typeName:)` below in lockstep.
//
// API note: the package declares `swift-tools-version: 5.9`, so the
// plugin uses the `Path`-based PackagePlugin API. The `URL`-based
// accessors (`Target.directoryURL`, `PluginContext.pluginWorkDirectoryURL`)
// require swift-tools-version 6.0+ and are not available here. The
// deprecation warnings on `Path` are tolerable for the same reason.

import Foundation
import PackagePlugin

@main
struct SwiftROS2GenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let targetDir = target.directory
        let msgDir = targetDir.appending(subpath: "msg")
        let msgInputs = Self.idlFiles(in: msgDir, extension: "msg")

        // .srv / .action files exist but the plugin does not yet handle
        // their five-wrapper output naming. Surface them as a warning so
        // users are not silently surprised. Multi-output IDL goes through
        // the CLI directly (see CLAUDE.md "Using the build plugin").
        let unsupported =
            Self.idlFiles(in: targetDir.appending(subpath: "srv"), extension: "srv")
            + Self.idlFiles(in: targetDir.appending(subpath: "action"), extension: "action")
        if !unsupported.isEmpty {
            Diagnostics.warning(
                "SwiftROS2GenPlugin: ignoring \(unsupported.count) .srv/.action file(s) under "
                    + "\(target.name); these IDL kinds need the swift-ros2-gen CLI directly. "
                    + "See CLAUDE.md."
            )
        }

        guard !msgInputs.isEmpty else { return [] }

        let outputDir = context.pluginWorkDirectory.appending(subpath: "Generated")
        let outputs = msgInputs.map {
            Self.outputFile(for: $0, packageName: target.name, outputRoot: outputDir)
        }
        let toolPath = try context.tool(named: "swift-ros2-gen").path
        let inputSpec = "\(target.name)=\(targetDir.string)@jazzy"

        return [
            .buildCommand(
                displayName: "swift-ros2-gen \(target.name)",
                executable: toolPath,
                arguments: [
                    "--input", inputSpec,
                    "--output", outputDir.string,
                    // Generated files compile inside the consuming target, not
                    // inside SwiftROS2Messages, so they need an explicit
                    // `import SwiftROS2Messages` to resolve `ROS2Message` /
                    // `ROS2MessageTypeInfo`. The CLI's `--extra-import` flag
                    // appends one `import` line per repetition.
                    "--extra-import", "SwiftROS2Messages",
                ],
                inputFiles: msgInputs,
                outputFiles: outputs
            )
        ]
    }

    /// Lists files with the given extension directly inside `dir`, returning
    /// `[]` when the directory does not exist. The plugin does not recurse.
    static func idlFiles(in dir: Path, extension ext: String) -> [Path] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.string, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        let url = URL(fileURLWithPath: dir.string, isDirectory: true)
        let contents =
            (try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return
            contents
            .filter { $0.pathExtension == ext }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { Path($0.path) }
    }

    /// Static counterpart of `SwiftROS2Gen.Pipeline.generate(for:)`'s relativePath
    /// computation: `<PascalPackage>/<SwiftStructName>.swift`.
    static func outputFile(for input: Path, packageName: String, outputRoot: Path) -> Path {
        let typeName = input.stem
        let pascalPackage = pascal(packageName)
        let structName = swiftStructName(typeName: typeName)
        let fileName = "\(structName).swift"
        return outputRoot.appending(subpath: pascalPackage).appending(subpath: fileName)
    }

    /// Mirror of `SwiftROS2Gen.SwiftEmitter.swiftStructName(typeName:)`:
    /// append `Msg` only for stdlib-collision names; otherwise the bare
    /// PascalCase type name is the struct + filename.
    static func swiftStructName(typeName: String) -> String {
        collisionTypeNames.contains(typeName) ? typeName + "Msg" : typeName
    }

    /// Must match `SwiftEmitter.collisionTypeNames` exactly.
    static let collisionTypeNames: Set<String> = [
        "Bool", "String",
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Float", "Float32", "Float64", "Double",
        "Empty",
    ]

    /// snake_case → PascalCase, matching `Pipeline.pascal`.
    static func pascal(_ snake: String) -> String {
        snake.split(separator: "_").map {
            $0.prefix(1).uppercased() + $0.dropFirst().lowercased()
        }.joined()
    }
}
