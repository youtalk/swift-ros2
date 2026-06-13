import ArgumentParser
import Foundation
import ParityMatrix

@main
struct ParityTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parity-tool",
        abstract: "Validate and render the swift-ros2 parity matrix.",
        subcommands: [Validate.self, Render.self]
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
}
