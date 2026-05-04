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

/// Maps `<pkg>/msg/<TypeName>` → preferred Swift struct name. Lets the emitter use
/// historic names like `UniqueIdentifierUUID` (which the rest of the codebase
/// already imports) instead of the default collision-rule output.
public typealias SwiftNameOverrides = [String: String]

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
            let label = "\(input.name)/msg/\(typeName).msg"
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
                    kind: ir0.kind,
                    fields: ir0.fields,
                    constants: ir0.constants,
                    perDistroHashes: ["jazzy": hash]
                )
                let key = "\(ir.package)/msg/\(ir.typeName)"
                let nameOverride = Pipeline.defaultSwiftNameOverrides[key]
                let isNested = Pipeline.defaultNestedOnlyTypes.contains(key)
                let swift = SwiftEmitter.emit(
                    ir,
                    sourceLabel: label,
                    isNested: isNested,
                    structNameOverride: nameOverride,
                    nestedNameOverrides: Pipeline.defaultSwiftNameOverrides
                )
                let pascalPackage = pascal(input.name)
                let structName = nameOverride ?? SwiftEmitter.swiftStructName(typeName: typeName)
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
    /// Per-type Swift struct-name overrides applied during emission. Keyed by
    /// `<package>/msg/<TypeName>` (the ROS canonical name). Emitter callers receive
    /// this same map as `nestedNameOverrides` so cross-package references resolve to
    /// the override value instead of the default ``SwiftEmitter/swiftStructName(typeName:)``.
    public static let defaultSwiftNameOverrides: SwiftNameOverrides = [
        "unique_identifier_msgs/msg/UUID": "UniqueIdentifierUUID"
    ]

    /// `<package>/msg/<TypeName>` set of types that emit as nested-only (CDRCodable,
    /// no `typeInfo`). These types are embedded as fields inside other messages and
    /// are never advertised at the topic level.
    ///
    /// NOTE: Phase 2 already emitted `BuiltinInterfaces/Time`, `GeometryMsgs/*`,
    /// and `StdMsgs/Header` as full `ROS2Message` types. Marking them nested-only
    /// here would silently regenerate them with a different conformance the next
    /// time anyone runs the CLI against those packages, breaking every existing
    /// caller. Keep this set restricted to the Phase 3 newcomers.
    public static let defaultNestedOnlyTypes: Set<String> = [
        "unique_identifier_msgs/msg/UUID",
        "action_msgs/msg/GoalInfo",
        "action_msgs/msg/GoalStatus",
    ]

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
        var collectedServices: [ParsedService] = []
        for run in runs {
            let parsed = try parsePackage(run: run)
            for entry in parsed {
                unresolvedIRs.append((run: run, ir: entry.ir, sourceLabel: entry.sourceLabel))
            }
            let services = try parseServicesIn(run: run)
            for svc in services {
                let reqIR = IRBuilder.build(jazzy: svc.requestIDL, kind: .srv)
                let resIR = IRBuilder.build(jazzy: svc.responseIDL, kind: .srv)
                let label = "\(run.input.name)/srv/\(svc.typeName).srv"
                unresolvedIRs.append((run: run, ir: reqIR, sourceLabel: label))
                unresolvedIRs.append((run: run, ir: resIR, sourceLabel: label))
            }
            collectedServices.append(contentsOf: services)
        }
        var registry: [String: MessageIR] = [:]
        for entry in unresolvedIRs {
            registry[entry.ir.rosTypeName] = entry.ir
        }
        // Auto-generate Swift name overrides for service halves so the emitter
        // produces `CancelGoalRequest` / `CancelGoalResponse` rather than
        // `CancelGoal_Request` (which is valid Swift but matches neither
        // PascalCase nor the umbrella's typealias targets).
        var nameOverrides = Pipeline.defaultSwiftNameOverrides
        for svc in collectedServices {
            nameOverrides["\(svc.package)/srv/\(svc.typeName)_Request"] =
                "\(svc.typeName)Request"
            nameOverrides["\(svc.package)/srv/\(svc.typeName)_Response"] =
                "\(svc.typeName)Response"
        }
        try validateAllReferencesResolved(registry: registry)
        // Precompute hashes once so the per-half emit loop and the per-service
        // umbrella loop can both look them up by ROS type name.
        var hashByRosName: [String: String] = [:]
        for entry in unresolvedIRs {
            hashByRosName[entry.ir.rosTypeName] = RIHS01.hash(entry.ir, registry: registry)
        }
        var results: [GeneratedFile] = []
        for entry in unresolvedIRs {
            guard let hash = hashByRosName[entry.ir.rosTypeName] else {
                preconditionFailure(
                    "Pipeline: missing precomputed hash for \(entry.ir.rosTypeName)"
                )
            }
            let hashed = MessageIR(
                package: entry.ir.package,
                typeName: entry.ir.typeName,
                kind: entry.ir.kind,
                fields: entry.ir.fields,
                constants: entry.ir.constants,
                perDistroHashes: ["jazzy": hash]
            )
            let key = "\(entry.ir.package)/\(entry.ir.kind.rawValue)/\(entry.ir.typeName)"
            let nameOverride = nameOverrides[key]
            let isNested = Pipeline.defaultNestedOnlyTypes.contains(key)
            let swift = SwiftEmitter.emit(
                hashed,
                sourceLabel: entry.sourceLabel,
                isNested: isNested,
                structNameOverride: nameOverride,
                nestedNameOverrides: nameOverrides
            )
            let pascalPackage = pascal(entry.ir.package)
            let structName =
                nameOverride
                ?? SwiftEmitter.swiftStructName(typeName: entry.ir.typeName)
            results.append(
                GeneratedFile(
                    relativePath: "\(pascalPackage)/\(structName).swift",
                    contents: swift
                ))
        }
        // Phase 3: emit one umbrella enum per parsed `.srv` so callers can use
        // `<Service>Srv.Request` / `.Response` and read the canonical service-level
        // hashes from `typeInfo`. The umbrella reuses the per-half hashes that
        // already landed in the registry above.
        for svc in collectedServices {
            let reqKey = "\(svc.package)/srv/\(svc.typeName)_Request"
            let resKey = "\(svc.package)/srv/\(svc.typeName)_Response"
            let requestHash = hashByRosName[reqKey]
            let responseHash = hashByRosName[resKey]
            let requestStructName = nameOverrides[reqKey] ?? "\(svc.typeName)Request"
            let responseStructName = nameOverrides[resKey] ?? "\(svc.typeName)Response"
            let umbrellaName =
                Pipeline.defaultSwiftNameOverrides["\(svc.package)/srv/\(svc.typeName)"]
                ?? "\(svc.typeName)Srv"
            let umbrella = SwiftEmitter.emitServiceUmbrella(
                package: svc.package,
                serviceTypeName: svc.typeName,
                umbrellaName: umbrellaName,
                requestStructName: requestStructName,
                responseStructName: responseStructName,
                requestHash: requestHash,
                responseHash: responseHash,
                sourceLabel: "\(svc.package)/srv/\(svc.typeName).srv"
            )
            let pascalPackage = pascal(svc.package)
            results.append(
                GeneratedFile(
                    relativePath: "\(pascalPackage)/\(umbrellaName).swift",
                    contents: umbrella
                ))
        }
        return results
    }

    /// Lightweight carrier for an as-parsed `.srv`: keeps the two halves' raw IDLFiles
    /// so the umbrella emitter can recompute hashes if the post-hashing registry
    /// lookup miscarries. The request / response halves themselves are emitted via
    /// the regular message emission path; this struct only describes the umbrella.
    public struct ParsedService: Equatable, Sendable {
        public let package: String
        public let typeName: String
        public let requestIDL: IDLFile
        public let responseIDL: IDLFile

        public init(package: String, typeName: String, requestIDL: IDLFile, responseIDL: IDLFile) {
            self.package = package
            self.typeName = typeName
            self.requestIDL = requestIDL
            self.responseIDL = responseIDL
        }
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
            let label = "\(run.input.name)/msg/\(typeName).msg"
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

    /// Enumerate `<pkg>/srv/*.srv` for the run, parse each into request / response
    /// halves, and return them as ``ParsedService`` carriers. Returns an empty
    /// array when the package has no `srv/` subdirectory at all (the common case
    /// for pure message packages like `std_msgs`). The same `typesAllowList`
    /// filter applies as for messages — it matches the bare service name
    /// (`CancelGoal`).
    private static func parseServicesIn(run: PackageRun) throws -> [ParsedService] {
        let srvDir = run.input.directory.appendingPathComponent("srv", isDirectory: true)
        var isDir: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: srvDir.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            return []
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: srvDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let srvFiles =
            entries
            .filter { $0.pathExtension == "srv" }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        var out: [ParsedService] = []
        for fileURL in srvFiles {
            let typeName = fileURL.deletingPathExtension().lastPathComponent
            if let allow = run.typesAllowList, !allow.contains(typeName) { continue }
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let label = "\(run.input.name)/srv/\(typeName).srv"
            do {
                let svc = try Parser.parseService(
                    source: contents,
                    file: label,
                    package: run.input.name,
                    typeName: typeName
                )
                out.append(
                    ParsedService(
                        package: run.input.name,
                        typeName: typeName,
                        requestIDL: svc.request,
                        responseIDL: svc.response
                    ))
            } catch let err as ParseError {
                throw GeneratorError.parse(err)
            }
        }
        return out
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
