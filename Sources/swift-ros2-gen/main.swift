import ArgumentParser
import Foundation
import SwiftROS2Gen

@main
struct SwiftROS2GenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-ros2-gen",
        abstract: "Generate Swift ROS2Message conformances from ROS 2 IDL"
    )

    @Option(
        name: .long,
        help:
            "<package_name>=<directory>@<distro>. Repeatable. Phase 4 supports multi-distro inputs: pass two or more entries with the same package name and different distros (e.g. @humble + @jazzy) to produce a single distro-conditional Swift file per type."
    )
    var input: [String] = []

    @Option(name: .long, help: "Output directory root (per-package subdirectories are created underneath).")
    var output: String

    @Option(
        name: .long,
        help:
            "Comma-separated allow-list of types to emit. When omitted, every supported type in the package is emitted."
    )
    var types: String?

    @Flag(name: .long, help: "Print what would be written; do not touch the filesystem.")
    var dryRun: Bool = false

    @Option(
        name: .long,
        help:
            "Repeatable. Additional `import <Module>` statement(s) to inject into every emitted Swift file. Used by SwiftROS2GenPlugin so generated files compiled outside the SwiftROS2Messages module can resolve `ROS2Message` / `ROS2MessageTypeInfo`."
    )
    var extraImport: [String] = []

    func validate() throws {
        // Reject untrusted whitespace / quotes / newlines in --extra-import
        // before the value is spliced into emitted Swift `import` lines.
        // ``ModuleIdentifier`` enforces the same rule the Pipeline boundary
        // re-validates, but surfacing it here lets ArgumentParser print the
        // CLI usage banner instead of an opaque GeneratorError.
        for value in extraImport where !ModuleIdentifier.isValid(value) {
            throw ValidationError(
                "invalid --extra-import '\(value)' — expected a Swift module identifier (e.g. 'SwiftROS2Messages' or 'My.Nested.Module')"
            )
        }
    }

    func run() throws {
        let outputRoot = URL(fileURLWithPath: output, isDirectory: true)
        let allowList: Set<String>? = types.map {
            Set($0.split(separator: ",").map(String.init))
        }
        var runs: [Pipeline.PackageRun] = []
        for raw in input {
            let pkg = try parseInput(raw)
            // Phase 4: every distro is consumed. When the same package name
            // appears twice (e.g. once @humble and once @jazzy), the
            // pipeline merges them into a single distro-conditional IR.
            runs.append(
                .init(
                    input: PackageInput(
                        name: pkg.packageName,
                        directory: pkg.directory,
                        distro: pkg.distro
                    ),
                    typesAllowList: allowList
                ))
        }
        let files: [GeneratedFile]
        do {
            files = try Pipeline.generateMulti(runs, extraImports: extraImport)
        } catch let err as GeneratorError {
            FileHandle.standardError.write(Data("error: \(err)\n".utf8))
            throw ExitCode.failure
        }
        for file in files {
            let absolute = outputRoot.appendingPathComponent(file.relativePath)
            if dryRun {
                FileHandle.standardOutput.write(
                    Data("WRITE \(absolute.path) (\(file.contents.utf8.count) bytes)\n".utf8))
            } else {
                try FileManager.default.createDirectory(
                    at: absolute.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try file.contents.write(to: absolute, atomically: true, encoding: .utf8)
            }
        }
    }

    struct ParsedInput {
        let packageName: String
        let directory: URL
        let distro: String
    }

    func parseInput(_ raw: String) throws -> ParsedInput {
        // Format: <package>=<path>@<distro>
        let eqParts = raw.split(separator: "=", maxSplits: 1).map(String.init)
        guard eqParts.count == 2 else {
            throw ValidationError("malformed --input '\(raw)' (expected '<package>=<path>@<distro>')")
        }
        let atParts = eqParts[1].split(separator: "@", maxSplits: 1).map(String.init)
        guard atParts.count == 2 else {
            throw ValidationError("malformed --input '\(raw)' (missing '@<distro>')")
        }
        return ParsedInput(
            packageName: eqParts[0],
            directory: URL(fileURLWithPath: atParts[0], isDirectory: true),
            distro: atParts[1]
        )
    }
}
