import Foundation

public struct PackageInput: Sendable {
    public let name: String  // "std_msgs"
    public let directory: URL  // Vendor/common_interfaces-jazzy/std_msgs

    public init(name: String, directory: URL) {
        self.name = name
        self.directory = directory
    }
}

public enum GeneratorError: Error, CustomStringConvertible {
    case packageDirectoryMissing(URL)
    case parse(ParseError)

    public var description: String {
        switch self {
        case .packageDirectoryMissing(let url):
            return "package directory missing: \(url.path)"
        case .parse(let error):
            return error.description
        }
    }
}

public struct GeneratedFile: Equatable, Sendable {
    public let relativePath: String  // "StdMsgs/BoolMsg.swift"
    public let contents: String

    public init(relativePath: String, contents: String) {
        self.relativePath = relativePath
        self.contents = contents
    }
}

public enum Pipeline {
    /// Process a single jazzy-distro package and return generated files.
    /// Phase 1: only primitive-typed messages are accepted; everything else
    /// surfaces as a `GeneratorError.parse(...)`.
    public static func generate(for input: PackageInput) throws -> [GeneratedFile] {
        let msgDir = input.directory.appendingPathComponent("msg", isDirectory: true)
        var isDir: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: msgDir.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            throw GeneratorError.packageDirectoryMissing(msgDir)
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: msgDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let msgFiles =
            entries
            .filter { $0.pathExtension == "msg" }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        var results: [GeneratedFile] = []
        for fileURL in msgFiles {
            let typeName = fileURL.deletingPathExtension().lastPathComponent
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let label = "common_interfaces-jazzy/\(input.name)/msg/\(typeName).msg"
            do {
                let idl = try Parser.parseMessage(
                    source: contents,
                    file: label,
                    package: input.name,
                    typeName: typeName
                )
                let ir0 = IRBuilder.build(jazzy: idl)
                let hash = RIHS01.hash(ir0)
                let ir = MessageIR(
                    package: ir0.package,
                    typeName: ir0.typeName,
                    fields: ir0.fields,
                    perDistroHashes: ["jazzy": hash]
                )
                let swift = SwiftEmitter.emit(ir, sourceLabel: label)
                let pascalPackage = pascal(input.name)
                let structName = SwiftEmitter.swiftStructName(typeName: typeName)
                results.append(
                    GeneratedFile(
                        relativePath: "\(pascalPackage)/\(structName).swift",
                        contents: swift
                    ))
            } catch let err as ParseError {
                throw GeneratorError.parse(err)
            }
        }
        return results
    }

    static func pascal(_ snake: String) -> String {
        snake.split(separator: "_").map {
            $0.prefix(1).uppercased() + $0.dropFirst().lowercased()
        }.joined()
    }
}
