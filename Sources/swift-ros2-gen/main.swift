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
            "<package_name>=<directory>@<distro>. Repeatable. Phase 1 only consumes the @jazzy entry per package."
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

    func run() throws {
        let outputRoot = URL(fileURLWithPath: output, isDirectory: true)
        let allowList: Set<String>? = types.map {
            Set($0.split(separator: ",").map(String.init))
        }
        for raw in input {
            let pkg = try parseInput(raw)
            // Phase 1 ignores entries that are not @jazzy.
            guard pkg.distro == "jazzy" else { continue }
            do {
                let files = try Pipeline.generate(
                    for: PackageInput(name: pkg.packageName, directory: pkg.directory),
                    typesAllowList: allowList
                )
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
            } catch let err as GeneratorError {
                FileHandle.standardError.write(Data("error in \(pkg.packageName): \(err)\n".utf8))
                throw ExitCode.failure
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
