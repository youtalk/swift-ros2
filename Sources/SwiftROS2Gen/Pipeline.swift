import Foundation

/// Identifies a ROS 2 package directory that the generator should process.
public struct PackageInput: Sendable {
    public let name: String  // "std_msgs"
    public let directory: URL  // vendor/common_interfaces-jazzy/std_msgs
    /// ROS 2 distro this directory represents (e.g. "humble", "jazzy"). The
    /// pipeline groups inputs that share `name` across distros and merges
    /// their per-distro IDLs into a single distro-conditional IR.
    public let distro: String

    public init(name: String, directory: URL, distro: String = "jazzy") {
        self.name = name
        self.directory = directory
        self.distro = distro
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
    ///
    /// Phase 4: when two `runs` share the same `input.name` (typically because
    /// the caller passed both a Humble and a Jazzy directory for the same
    /// package), the per-distro IDL files for each type are merged via
    /// ``IRBuilder/build(perDistro:)`` into a single distro-conditional IR.
    /// `unresolvedIRs` then carries one merged IR per `(package, typeName)`
    /// even though the source IDLs come from multiple distros.
    public static func generateMulti(_ runs: [PackageRun]) throws -> [GeneratedFile] {
        var unresolvedIRs: [(run: PackageRun, ir: MessageIR, sourceLabel: String)] = []
        var collectedServices: [ParsedService] = []
        // Group runs by package name; multiple runs with the same name represent
        // different distros for the same logical package.
        var runsByPackage: [String: [PackageRun]] = [:]
        var packageOrder: [String] = []
        for run in runs {
            if runsByPackage[run.input.name] == nil { packageOrder.append(run.input.name) }
            runsByPackage[run.input.name, default: []].append(run)
        }
        for pkg in packageOrder {
            let pkgRuns = runsByPackage[pkg]!
            if pkgRuns.count == 1 {
                // Single-distro fast path (Phase 1-3 behavior preserved).
                let run = pkgRuns[0]
                let parsed = try parsePackage(run: run)
                for entry in parsed {
                    unresolvedIRs.append(
                        (run: run, ir: entry.ir, sourceLabel: entry.sourceLabel))
                }
                let services = try parseServicesIn(run: run)
                for svc in services {
                    let reqIR = IRBuilder.build(jazzy: svc.requestIDL, kind: .srv)
                    let resIR = IRBuilder.build(jazzy: svc.responseIDL, kind: .srv)
                    let label = sourceLabelFor(run: run, typeName: svc.typeName, kind: .srv)
                    unresolvedIRs.append((run: run, ir: reqIR, sourceLabel: label))
                    unresolvedIRs.append((run: run, ir: resIR, sourceLabel: label))
                }
                collectedServices.append(contentsOf: services)
            } else {
                // Multi-distro path: parse each run's IDLs, group by type name,
                // then merge per-distro IDLs via IRBuilder.build(perDistro:).
                let merged = try parseAndMergeMultiDistroPackage(runs: pkgRuns)
                let primaryRun = pkgRuns.first!
                for entry in merged {
                    unresolvedIRs.append(
                        (run: primaryRun, ir: entry.ir, sourceLabel: entry.sourceLabel))
                }
                // Phase 4: union services across the multi-distro runs, but
                // require structural agreement. A `.srv` whose request or
                // response shape differs between distros surfaces as an
                // IRMergeError so we never silently emit one distro's shape.
                // Phase 5 will widen this to true multi-distro service merging.
                var servicesByName: [String: ParsedService] = [:]
                var serviceOrder: [String] = []
                for run in pkgRuns {
                    let runServices = try parseServicesIn(run: run)
                    for svc in runServices {
                        if let existing = servicesByName[svc.typeName] {
                            guard
                                existing.requestIDL == svc.requestIDL,
                                existing.responseIDL == svc.responseIDL
                            else {
                                throw GeneratorError.parse(
                                    ParseError(
                                        file: "\(svc.package)/srv/\(svc.typeName).srv",
                                        line: 1,
                                        message:
                                            "service '\(svc.typeName)' differs between distros — multi-distro service merging is not implemented yet (Phase 5)"
                                    ))
                            }
                        } else {
                            servicesByName[svc.typeName] = svc
                            serviceOrder.append(svc.typeName)
                        }
                    }
                }
                let services = serviceOrder.compactMap { servicesByName[$0] }
                for svc in services {
                    let reqIR = IRBuilder.build(jazzy: svc.requestIDL, kind: .srv)
                    let resIR = IRBuilder.build(jazzy: svc.responseIDL, kind: .srv)
                    let label = sourceLabelFor(
                        run: primaryRun, typeName: svc.typeName, kind: .srv)
                    unresolvedIRs.append((run: primaryRun, ir: reqIR, sourceLabel: label))
                    unresolvedIRs.append((run: primaryRun, ir: resIR, sourceLabel: label))
                }
                collectedServices.append(contentsOf: services)
            }
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
        // Precompute the modern (jazzy-view) hash for every IR. Single-distro
        // humble-only inputs do not need a Jazzy hash (humble has no RIHS01
        // anyway), but computing it is cheap and the per-distro projection
        // below decides whether to emit it. Hashing is per-distro so nested
        // type lookups in the registry get the same field projection as the
        // root.
        var hashByRosName: [String: String] = [:]
        for entry in unresolvedIRs {
            hashByRosName[entry.ir.rosTypeName] = RIHS01.hash(
                entry.ir, for: "jazzy", registry: registry)
        }
        var results: [GeneratedFile] = []
        for entry in unresolvedIRs {
            guard let primaryHash = hashByRosName[entry.ir.rosTypeName] else {
                preconditionFailure(
                    "Pipeline: missing precomputed hash for \(entry.ir.rosTypeName)"
                )
            }
            // Determine which distros the IR was built against.
            //   - Multi-distro IR (`IRBuilder.build(perDistro:)`):
            //     `perDistroFieldPresence.keys` lists every contributing distro.
            //   - Single-distro IR (`IRBuilder.build(jazzy:)` from the
            //     fast path): the presence map is empty, so we fall back to
            //     the run's distro. For a humble-only run that means the
            //     emitted `typeInfo` advertises a `nil` humble hash.
            //   - Service halves (`kind == .srv`): treat as supported on
            //     every distro for now — Phase 5 will multi-distro-merge them.
            let distros: Set<String>
            if entry.ir.kind == .srv {
                distros = ["humble", "jazzy", "kilted", "rolling"]
            } else if entry.ir.perDistroFieldPresence.isEmpty {
                distros = [entry.run.input.distro]
            } else {
                distros = Set(entry.ir.perDistroFieldPresence.keys)
            }
            var perDistroHashes: [String: String?] = [:]
            for distro in distros {
                switch distro {
                case "humble":
                    // Humble has no RIHS01 — present in this distro, hash is nil.
                    perDistroHashes["humble"] = nil
                case "jazzy", "kilted", "rolling":
                    // Modern distros share the jazzy wire format and hash.
                    perDistroHashes[distro] = primaryHash
                default:
                    break
                }
            }
            // The non-conditional emit path keys on `perDistroHashes["jazzy"]`
            // for the static `typeInfo` constant. A humble-only single-distro
            // run does not naturally fill this in — plumb the primary
            // (computed-from-current-fields) hash so the emitter has
            // something to render. The conditional path uses the presence
            // map to decide which distros actually advertise the type.
            if perDistroHashes["jazzy"] == nil {
                perDistroHashes["jazzy"] = primaryHash
            }
            let hashed = MessageIR(
                package: entry.ir.package,
                typeName: entry.ir.typeName,
                kind: entry.ir.kind,
                fields: entry.ir.fields,
                constants: entry.ir.constants,
                perDistroHashes: perDistroHashes,
                perDistroFieldPresence: entry.ir.perDistroFieldPresence
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
        let msgExists =
            FileManager.default.fileExists(atPath: msgDir.path, isDirectory: &isDir)
            && isDir.boolValue
        guard msgExists else {
            // A package without a msg/ directory is valid when it ships only
            // services (e.g. std_srvs) or actions. Return empty here; the
            // caller still walks srv/ via parseServicesIn.
            return []
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
            let label = sourceLabelFor(run: run, typeName: typeName, kind: .msg)
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

    /// Produce a stable `// Source:` label for emitted Swift files. The label
    /// is informational only (it never affects the wire format), but tests
    /// and goldens key on it. We prefix with the parent vendor directory
    /// (`common_interfaces-jazzy`, etc.) when that name unambiguously
    /// identifies the upstream IDL source; bare names like `vendor` or
    /// repository roots that happen to be the immediate parent are stripped.
    private static func sourceLabelFor(
        run: PackageRun,
        typeName: String,
        kind: MessageKind
    ) -> String {
        let parent = run.input.directory.deletingLastPathComponent().lastPathComponent
        let suffix = "\(run.input.name)/\(kind.rawValue)/\(typeName).\(kind.rawValue)"
        if parent.isEmpty || parent == "vendor" || parent == "Vendor" {
            return suffix
        }
        // Strip a `<repo>-<distro>` parent down to its base when the package
        // is not the canonical sibling of that repo (e.g. action_msgs lives
        // under `rcl_interfaces-jazzy/`, but the historical labels emitted
        // it bare). The rule: keep the parent only when it begins with
        // `common_interfaces` (the one repo where the prefixed label was
        // historically committed).
        if parent.hasPrefix("common_interfaces") {
            return "\(parent)/\(suffix)"
        }
        return suffix
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
            let label = sourceLabelFor(run: run, typeName: typeName, kind: .srv)
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

    /// Phase 4 helper. Parses every `.msg` in each `pkgRuns[*].input.directory/msg`
    /// and groups the IDLFiles by type name; for each group, calls
    /// ``IRBuilder/build(perDistro:)`` to produce a single distro-conditional IR.
    /// `pkgRuns` must all share the same `input.name` — the caller in
    /// ``generateMulti`` already enforces that.
    private static func parseAndMergeMultiDistroPackage(
        runs pkgRuns: [PackageRun]
    ) throws -> [ParsedEntry] {
        precondition(!pkgRuns.isEmpty, "parseAndMergeMultiDistroPackage: empty runs")
        let packageName = pkgRuns[0].input.name
        precondition(
            pkgRuns.allSatisfy { $0.input.name == packageName },
            "parseAndMergeMultiDistroPackage: all runs must share the same package name")

        // Per-distro IDL collections, indexed by type name.
        var idlsByType: [String: [String: IDLFile]] = [:]
        var typeOrder: [String] = []
        // Pick the most-permissive type allow-list across the runs (a type
        // appears in the merge if any run lists it). Practically every run
        // shares the same allow-list because the CLI applies the same
        // `--types` filter to every input.
        var unifiedAllowList: Set<String>? = nil
        for run in pkgRuns {
            if let allow = run.typesAllowList {
                if unifiedAllowList == nil { unifiedAllowList = [] }
                unifiedAllowList?.formUnion(allow)
            }
        }

        for run in pkgRuns {
            let msgDir = run.input.directory.appendingPathComponent("msg", isDirectory: true)
            var isDir: ObjCBool = false
            let msgExists =
                FileManager.default.fileExists(atPath: msgDir.path, isDirectory: &isDir)
                && isDir.boolValue
            guard msgExists else {
                // Service-only packages (no msg/ directory) are tolerated;
                // the multi-distro path simply contributes no message IRs
                // for that distro.
                continue
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
            for fileURL in msgFiles {
                let typeName = fileURL.deletingPathExtension().lastPathComponent
                if let allow = unifiedAllowList, !allow.contains(typeName) { continue }
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                // Derive the parent name from the actual filesystem directory
                // so submodule renames (e.g. vendor/common_interfaces-jazzy ->
                // vendor/common_interfaces) are reflected in the label.
                let parentDir = run.input.directory.deletingLastPathComponent().lastPathComponent
                let label = "\(parentDir)/\(packageName)/msg/\(typeName).msg"
                do {
                    let idl = try Parser.parseMessage(
                        source: contents,
                        file: label,
                        package: packageName,
                        typeName: typeName
                    )
                    if idlsByType[typeName] == nil { typeOrder.append(typeName) }
                    idlsByType[typeName, default: [:]][run.input.distro] = idl
                } catch let err as ParseError {
                    throw GeneratorError.parse(err)
                }
            }
        }

        var parsed: [ParsedEntry] = []
        for typeName in typeOrder {
            guard let perDistroIDL = idlsByType[typeName] else { continue }
            let mergedIR = try IRBuilder.build(perDistro: perDistroIDL)
            // Use a stable label that names every distro the type came from.
            // The parent comes from the first run's vendor parent directory
            // ("common_interfaces" or similar) plus a `+`-joined distro list.
            let distros =
                perDistroIDL.keys.sorted().joined(separator: "+")
            let parentDir =
                pkgRuns.first!.input.directory.deletingLastPathComponent().lastPathComponent
            // Strip any trailing `-<distro>` suffix from the parent so the
            // label reads e.g. `common_interfaces-humble+jazzy/sensor_msgs/...`.
            let baseParent: String = {
                if let dashIdx = parentDir.firstIndex(of: "-") {
                    return String(parentDir[..<dashIdx])
                }
                return parentDir
            }()
            let label = "\(baseParent)-\(distros)/\(packageName)/msg/\(typeName).msg"
            parsed.append(ParsedEntry(ir: mergedIR, sourceLabel: label))
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
