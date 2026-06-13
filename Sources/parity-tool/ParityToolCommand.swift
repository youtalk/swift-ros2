import ArgumentParser
import Foundation
import ParityMatrix

@main
struct ParityTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parity-tool",
        abstract: "Validate and render the swift-ros2 parity matrix.",
        subcommands: [Validate.self, Render.self, Set.self, Canonicalize.self]
    )

    static func loadMatrix(_ path: String) throws -> ParityMatrix {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(ParityMatrix.self, from: data)
    }

    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Decode the matrix JSON and check structural invariants."
        )

        @Option(name: .long, help: "Path to parity-matrix.json")
        var input: String = "docs/parity-matrix.json"

        func run() throws {
            let matrix = try ParityTool.loadMatrix(input)
            try matrix.validate()
            FileHandle.standardOutput.write(
                Data("parity-tool validate OK: \(matrix.capabilities.count) capabilities\n".utf8)
            )
        }
    }

    struct Render: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Render docs/PARITY.md from the matrix JSON."
        )

        @Option(name: .long, help: "Path to parity-matrix.json")
        var input: String = "docs/parity-matrix.json"

        @Option(name: .long, help: "Output Markdown path")
        var output: String = "docs/PARITY.md"

        func run() throws {
            let matrix = try ParityTool.loadMatrix(input)
            try matrix.validate()
            let md = matrix.renderMarkdown()
            try md.write(toFile: output, atomically: true, encoding: .utf8)
            FileHandle.standardOutput.write(Data("parity-tool render OK -> \(output)\n".utf8))
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Record a verification-axis verdict for a capability, then re-render PARITY.md."
        )

        @Argument(help: "capability id, e.g. publish.typed.sensor_msgs/Imu")
        var capabilityId: String

        @Option(name: .long, help: "latency | soak | correctness | resource")
        var axis: String

        @Option(name: .long, help: "pass | fail | pending")
        var verdict: String

        @Option(name: .long, help: "free-form measured value (optional)")
        var value: String?

        @Option(name: .long, help: "Path to parity-matrix.json")
        var input: String = "docs/parity-matrix.json"

        @Option(name: .long, help: "Output Markdown path")
        var output: String = "docs/PARITY.md"

        func run() throws {
            guard let axisEnum = ParityMatrix.Axis(rawValue: axis) else {
                throw ValidationError("axis must be one of: latency, soak, correctness, resource")
            }
            guard let verdictEnum = AxisVerdict(rawValue: verdict) else {
                throw ValidationError("verdict must be one of: pass, fail, pending")
            }
            var matrix = try ParityTool.loadMatrix(input)
            try matrix.setAxis(
                capabilityId: capabilityId, axis: axisEnum, verdict: verdictEnum, value: value)
            try matrix.validate()
            // Atomic writes so an interrupted run never leaves a half-written file.
            // JSON is written first, then PARITY.md; if the second write fails the two
            // can drift — re-run `parity-tool render` to resync.
            try matrix.encodeCanonicalJSON().write(to: URL(fileURLWithPath: input), options: .atomic)
            try matrix.renderMarkdown().write(toFile: output, atomically: true, encoding: .utf8)
            FileHandle.standardOutput.write(
                Data("parity-tool set OK: \(capabilityId) [\(axis)] = \(verdict)\n".utf8))
        }
    }

    struct Canonicalize: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rewrite the matrix JSON in canonical form (idempotent)."
        )

        @Option(name: .long, help: "Path to parity-matrix.json")
        var input: String = "docs/parity-matrix.json"

        func run() throws {
            let matrix = try ParityTool.loadMatrix(input)
            try matrix.validate()
            try matrix.encodeCanonicalJSON().write(to: URL(fileURLWithPath: input), options: .atomic)
            FileHandle.standardOutput.write(
                Data("parity-tool canonicalize OK -> \(input)\n".utf8))
        }
    }
}
