import Foundation

/// Identifies a ROS 2 package directory that the generator should process.
public struct PackageInput: Sendable {
    public let name: String  // "std_msgs"
    public let directory: URL  // vendor/common_interfaces-jazzy/std_msgs

    public init(name: String, directory: URL) {
        self.name = name
        self.directory = directory
    }
}

/// Errors that the ``Pipeline`` surfaces when generation cannot proceed.
public enum GeneratorError: Error, CustomStringConvertible {
    case packageDirectoryMissing(URL)
    case parse(ParseError)
    case unresolvedNestedType(package: String, typeName: String)

    public var description: String {
        switch self {
        case .packageDirectoryMissing(let url):
            return "package directory missing: \(url.path)"
        case .parse(let error):
            return error.description
        case .unresolvedNestedType(let pkg, let type):
            return
                "unresolved nested type '\(pkg)/\(type)' — pass a --input for '\(pkg)' on the same CLI invocation"
        }
    }
}

/// A single Swift source file produced by the generator.
public struct GeneratedFile: Equatable, Sendable {
    public let relativePath: String  // "StdMsgs/BoolMsg.swift"
    public let contents: String

    public init(relativePath: String, contents: String) {
        self.relativePath = relativePath
        self.contents = contents
    }
}

/// Orchestrates parsing, IR building, hashing, and emission for a ROS 2 package.
public enum Pipeline {
    /// Process a single jazzy-distro package and return generated files.
    /// Phase 1: only primitive-typed messages are accepted; everything else
    /// surfaces as a `GeneratorError.parse(...)`.
    ///
    /// - Parameters:
    ///   - input: Package name and directory containing the `msg/` subdirectory.
    ///   - typesAllowList: When non-nil, only `.msg` files whose stem (e.g. `"Bool"`)
    ///     appear in this set are processed. Files outside the allow-list are silently
    ///     skipped before reaching the parser, keeping Phase 1 functional against real
    ///     vendor directories that contain unsupported message types.
    public static func generate(
        for input: PackageInput,
        typesAllowList: Set<String>? = nil
    ) throws -> [GeneratedFile] {
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
            // Apply allow-list at parse boundary: skip files not in the allow-list.
            if let allowList = typesAllowList, !allowList.contains(typeName) {
                continue
            }
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let parent = input.directory.deletingLastPathComponent().lastPathComponent
            let label = "\(parent)/\(input.name)/msg/\(typeName).msg"
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

extension Pipeline {
    public struct PackageRun: Sendable {
        public let input: PackageInput
        public let typesAllowList: Set<String>?

        public init(input: PackageInput, typesAllowList: Set<String>? = nil) {
            self.input = input
            self.typesAllowList = typesAllowList
        }
    }

    /// Multi-package generation. All inputs are parsed first, then the resulting IRs
    /// are aggregated into a registry. Hashing and emission run after the registry is
    /// complete so cross-package references (e.g. `std_msgs/Header → builtin_interfaces/Time`)
    /// resolve regardless of the order packages appear in `runs`.
    public static func generateMulti(_ runs: [PackageRun]) throws -> [GeneratedFile] {
        var unresolvedIRs: [(run: PackageRun, ir: MessageIR, sourceLabel: String)] = []
        for run in runs {
            let parsed = try parsePackage(run: run)
            for entry in parsed {
                unresolvedIRs.append((run: run, ir: entry.ir, sourceLabel: entry.sourceLabel))
            }
        }
        var registry: [String: MessageIR] = [:]
        for entry in unresolvedIRs {
            registry[entry.ir.rosTypeName] = entry.ir
        }
        try validateAllReferencesResolved(registry: registry)
        var results: [GeneratedFile] = []
        for entry in unresolvedIRs {
            let hash = RIHS01.hash(entry.ir, registry: registry)
            let hashed = MessageIR(
                package: entry.ir.package,
                typeName: entry.ir.typeName,
                fields: entry.ir.fields,
                perDistroHashes: ["jazzy": hash]
            )
            let swift = SwiftEmitter.emit(hashed, sourceLabel: entry.sourceLabel)
            let pascalPackage = pascal(entry.ir.package)
            let structName = SwiftEmitter.swiftStructName(typeName: entry.ir.typeName)
            results.append(
                GeneratedFile(
                    relativePath: "\(pascalPackage)/\(structName).swift",
                    contents: swift
                ))
        }
        return results
    }

    private struct ParsedEntry {
        let ir: MessageIR
        let sourceLabel: String
    }

    private static func parsePackage(run: PackageRun) throws -> [ParsedEntry] {
        let msgDir = run.input.directory.appendingPathComponent("msg", isDirectory: true)
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
        var parsed: [ParsedEntry] = []
        for fileURL in msgFiles {
            let typeName = fileURL.deletingPathExtension().lastPathComponent
            if let allow = run.typesAllowList, !allow.contains(typeName) { continue }
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let parent = run.input.directory.deletingLastPathComponent().lastPathComponent
            let label = "\(parent)/\(run.input.name)/msg/\(typeName).msg"
            do {
                let idl = try Parser.parseMessage(
                    source: contents,
                    file: label,
                    package: run.input.name,
                    typeName: typeName
                )
                let ir = IRBuilder.build(jazzy: idl)
                parsed.append(ParsedEntry(ir: ir, sourceLabel: label))
            } catch let err as ParseError {
                throw GeneratorError.parse(err)
            }
        }
        return parsed
    }

    private static func validateAllReferencesResolved(registry: [String: MessageIR]) throws {
        for (_, ir) in registry {
            for field in ir.fields {
                guard case .nested(let pkg, let type) = field.type else { continue }
                let key = "\(pkg)/msg/\(type)"
                if registry[key] == nil {
                    throw GeneratorError.unresolvedNestedType(package: pkg, typeName: type)
                }
            }
        }
    }
}
