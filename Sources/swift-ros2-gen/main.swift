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

    @Option(
        name: .long,
        help:
            "Output directory root (per-package subdirectories are created underneath). Required for emit mode; ignored when --verify-hashes is set."
    )
    var output: String = ""

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

    @Option(
        name: .long,
        help: """
            Compare each generated type's RIHS01 hash against the oracle running inside the named Docker image \
            (e.g. 'osrf/ros:jazzy-desktop'). Implies --dry-run; exits non-zero on mismatch.
            """
    )
    var verifyHashes: String?

    @Option(
        name: .long,
        help: """
            Comma-separated distro allow-list for --verify-hashes (default: all distros derived from --input \
            except 'humble', which has no rosidl type-hash JSON). Each distro must match the tag the Docker image \
            is pulled from (e.g. 'jazzy,kilted,rolling').
            """
    )
    var distros: String?

    @Flag(
        name: .long,
        help: """
            On hash-mismatch, dump the canonical oracle JSON plus a summary of the expected vs. observed RIHS01 \
            under /tmp/swift-ros2-gen-diagnose/. Useful for finding the IR-builder or RIHS01 implementation drift.
            """
    )
    var diagnose: Bool = false

    @Option(
        name: .long,
        help: """
            Comma-separated deny-list of types to exclude from --verify-hashes (e.g. 'Char' to skip a known \
            generator drift). Applied after --types.
            """
    )
    var excludeTypes: String?

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
        if let image = verifyHashes {
            try runVerifyMode(image: image)
            return
        }
        try runEmitMode()
    }

    func runEmitMode() throws {
        guard !output.isEmpty else {
            throw ValidationError("--output is required in emit mode (omit only with --verify-hashes)")
        }
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

    func runVerifyMode(image: String) throws {
        let allowedDistros: Set<String>? = distros.map {
            Set($0.split(separator: ",").map(String.init))
        }
        let allowList: Set<String>? = types.map {
            Set($0.split(separator: ",").map(String.init))
        }
        var runs: [Pipeline.PackageRun] = []
        for raw in input {
            let pkg = try parseInput(raw)
            // Skip inputs whose distro is excluded by the allow-list. We
            // still parse every other distro since cross-package nested
            // references (e.g. sensor_msgs/Imu -> std_msgs/Header) must
            // resolve in `Pipeline.buildVerifyPlan`'s registry.
            if let allowed = allowedDistros, !allowed.contains(pkg.distro) { continue }
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
        let denyList: Set<String> =
            excludeTypes.map {
                Set($0.split(separator: ",").map(String.init))
            } ?? []
        let rawPlan: [VerifyPlanEntry]
        do {
            rawPlan = try Pipeline.buildVerifyPlan(runs, distros: allowedDistros)
        } catch let err as GeneratorError {
            FileHandle.standardError.write(Data("error: \(err)\n".utf8))
            throw ExitCode.failure
        }
        // Apply the deny-list. We compare against both the contained
        // `typeName` and the `topLevelTypeName` so excluding a service /
        // action stem (e.g. `Fibonacci`) drops every sub-type derived
        // from that file.
        let plan: [VerifyPlanEntry] =
            denyList.isEmpty
            ? rawPlan
            : rawPlan.filter {
                !denyList.contains($0.typeName)
                    && !denyList.contains($0.topLevelTypeName)
            }
        // An empty plan means the input filters (--input paths, --types,
        // --distros, --exclude-types) selected zero IRs. That is almost
        // always a misconfiguration — e.g. a typo'd vendor path on a
        // case-sensitive Linux runner that resolves to nothing — which
        // would otherwise be reported as `mismatches=0 missing=0` and pass
        // silently. Surface it as a hard error so CI catches the typo.
        if plan.isEmpty {
            FileHandle.standardError.write(
                Data(
                    "error: --verify-hashes selected 0 types — check --input paths, --types, --distros, --exclude-types\n"
                        .utf8))
            throw ExitCode.failure
        }
        let verifier = HashVerifier(
            oracle: OracleClient(dockerImage: image),
            diagnose: diagnose
        )
        let report: HashVerifier.Report
        do {
            report = try verifier.verifyAll(plan)
        } catch let err as OracleClient.OracleError {
            FileHandle.standardError.write(Data("hash-oracle: \(err)\n".utf8))
            throw ExitCode.failure
        }
        FileHandle.standardOutput.write(Data(report.summary.utf8))
        if !report.mismatches.isEmpty || !report.missingFromOracle.isEmpty {
            throw ExitCode.failure
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
