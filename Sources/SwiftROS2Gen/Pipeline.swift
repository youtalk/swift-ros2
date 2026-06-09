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
    case invalidExtraImport(String)
    case unknownRequestedTypes([String])

    public var description: String {
        switch self {
        case .packageDirectoryMissing(let url):
            return "package directory missing: \(url.path)"
        case .parse(let error):
            return error.description
        case .unresolvedNestedType(let pkg, let type):
            return
                "unresolved nested type '\(pkg)/\(type)' — pass a --input for '\(pkg)' on the same CLI invocation"
        case .invalidExtraImport(let value):
            return
                "invalid --extra-import '\(value)' — expected a Swift module identifier (e.g. 'SwiftROS2Messages' or 'My.Nested.Module')"
        case .unknownRequestedTypes(let names):
            return
                "--emit-rcl-marshalling: requested type(s) not found in the parsed packages: \(names) — check --types and --input"
        }
    }
}

/// Module-name validation shared by the CLI and the `Pipeline` so untrusted
/// user input cannot be spliced verbatim into emitted `import` lines. A valid
/// module identifier matches `[A-Za-z_][A-Za-z0-9_]*`, optionally dotted for
/// nested modules (e.g. `Foo.Bar`). Whitespace, quotes, and newlines are all
/// rejected.
public enum ModuleIdentifier {
    /// Returns `true` when `value` is a syntactically valid Swift module
    /// identifier (single segment or dotted). Empty strings are rejected.
    public static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return false }
        for segment in segments {
            if segment.isEmpty { return false }
            let scalars = segment.unicodeScalars
            guard let first = scalars.first else { return false }
            let isHeadValid =
                (first.value >= 0x41 && first.value <= 0x5A)  // A-Z
                || (first.value >= 0x61 && first.value <= 0x7A)  // a-z
                || first == "_"
            if !isHeadValid { return false }
            for scalar in scalars.dropFirst() {
                let isTailValid =
                    (scalar.value >= 0x41 && scalar.value <= 0x5A)  // A-Z
                    || (scalar.value >= 0x61 && scalar.value <= 0x7A)  // a-z
                    || (scalar.value >= 0x30 && scalar.value <= 0x39)  // 0-9
                    || scalar == "_"
                if !isTailValid { return false }
            }
        }
        return true
    }

    /// Throws ``GeneratorError/invalidExtraImport(_:)`` for any entry that
    /// isn't a valid module identifier. Called by the `Pipeline` boundary so
    /// `extraImports` can be trusted by the emitter even when the CLI
    /// validation layer is bypassed (e.g. when `Pipeline` is invoked directly
    /// from a unit test).
    public static func validateAll(_ values: [String]) throws {
        for value in values where !isValid(value) {
            throw GeneratorError.invalidExtraImport(value)
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
        typesAllowList: Set<String>? = nil,
        extraImports: [String] = []
    ) throws -> [GeneratedFile] {
        try ModuleIdentifier.validateAll(extraImports)
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
                    nestedNameOverrides: Pipeline.defaultSwiftNameOverrides,
                    extraImports: extraImports
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
    public static func generateMulti(
        _ runs: [PackageRun],
        extraImports: [String] = []
    ) throws -> [GeneratedFile] {
        try ModuleIdentifier.validateAll(extraImports)
        var unresolvedIRs: [(run: PackageRun, ir: MessageIR, sourceLabel: String)] = []
        var collectedServices: [ParsedService] = []
        var collectedActions: [ParsedAction] = []
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

                let actions = try parseActionsIn(run: run)
                for act in actions {
                    let label = sourceLabelFor(
                        run: run, typeName: act.typeName, kind: .action)
                    // Register the user-defined Goal/Result/Feedback IRs in
                    // the registry so wrapper nested references resolve.
                    unresolvedIRs.append(
                        (run: run, ir: act.actionIR.goal, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: run, ir: act.actionIR.result, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: run, ir: act.actionIR.feedback, sourceLabel: label))
                    // Register the wrappers so the action-level hash and any
                    // cross-package reference to a wrapper resolves.
                    unresolvedIRs.append(
                        (run: run, ir: act.actionIR.sendGoalRequest, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: run, ir: act.actionIR.sendGoalResponse, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: run, ir: act.actionIR.getResultRequest, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: run, ir: act.actionIR.getResultResponse, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: run, ir: act.actionIR.feedbackMessage, sourceLabel: label))
                }
                collectedActions.append(contentsOf: actions)
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

                // Same single-source-run policy for actions.
                let actions = try parseActionsIn(run: primaryRun)
                for act in actions {
                    let label = sourceLabelFor(
                        run: primaryRun, typeName: act.typeName, kind: .action)
                    unresolvedIRs.append(
                        (run: primaryRun, ir: act.actionIR.goal, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: primaryRun, ir: act.actionIR.result, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: primaryRun, ir: act.actionIR.feedback, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: primaryRun, ir: act.actionIR.sendGoalRequest, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: primaryRun, ir: act.actionIR.sendGoalResponse, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: primaryRun, ir: act.actionIR.getResultRequest, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: primaryRun, ir: act.actionIR.getResultResponse, sourceLabel: label))
                    unresolvedIRs.append(
                        (run: primaryRun, ir: act.actionIR.feedbackMessage, sourceLabel: label))
                }
                collectedActions.append(contentsOf: actions)
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
            // Action IRs (the three user blocks + five wrappers) are emitted
            // together in a single per-action Swift file below, not as
            // standalone files.
            if entry.ir.kind == .action {
                continue
            }
            let nameOverride = nameOverrides[key]
            let isNested = Pipeline.defaultNestedOnlyTypes.contains(key)
            let swift = SwiftEmitter.emit(
                hashed,
                sourceLabel: entry.sourceLabel,
                isNested: isNested,
                structNameOverride: nameOverride,
                nestedNameOverrides: nameOverrides,
                extraImports: extraImports
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
                sourceLabel: "\(svc.package)/srv/\(svc.typeName).srv",
                extraImports: extraImports
            )
            let pascalPackage = pascal(svc.package)
            results.append(
                GeneratedFile(
                    relativePath: "\(pascalPackage)/\(umbrellaName).swift",
                    contents: umbrella
                ))
        }
        // Phase 6: emit one Swift file per parsed `.action`. Each file owns the
        // outer `<TypeName>Action` enum (with nested `Goal` / `Result` /
        // `Feedback`) plus the five sibling `<TypeName>_<Wrapper>` structs.
        // The action-level + wrapper hashes come from
        // ``IRBuilder/populateActionHashes(_:distro:extraRegistry:)`` which
        // reuses the global registry assembled above.
        for act in collectedActions {
            var actionIR = act.actionIR
            IRBuilder.populateActionHashes(
                &actionIR, distro: "jazzy", extraRegistry: registry)
            let label = "\(act.package)/action/\(act.typeName).action"
            let swift = SwiftEmitter.emit(
                actionIR,
                sourceLabel: label,
                nestedNameOverrides: nameOverrides,
                extraImports: extraImports
            )
            let pascalPackage = pascal(act.package)
            results.append(
                GeneratedFile(
                    relativePath: "\(pascalPackage)/\(act.typeName)Action.swift",
                    contents: swift
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

    /// Throw ``GeneratorError/packageDirectoryMissing(_:)`` when `directory`
    /// does not exist or is not a directory. Used by every `--input` consumer
    /// before tolerating a missing `msg/` or `srv/` subdirectory, so a typo'd
    /// `--input` path surfaces as a hard error rather than as an empty
    /// (single-package path) or partial (multi-distro path) success.
    private static func requirePackageDirectory(_ directory: URL) throws {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir)
        guard exists, isDir.boolValue else {
            throw GeneratorError.packageDirectoryMissing(directory)
        }
    }

    /// Same parse-and-IR walk as ``generateMulti`` but stops short of
    /// emission. Used by `swift-ros2-gen --verify-hashes` to diff every
    /// generator-computed RIHS01 against the canonical rosidl oracle without
    /// touching the filesystem.
    ///
    /// Each returned ``VerifyPlanEntry`` carries the in-process IR, the
    /// generator-computed hash for the requested distro, and the
    /// ``topLevelTypeName`` of the IDL file that produced it (e.g. for
    /// `Fibonacci_SendGoal_Request` the top-level type is `Fibonacci`). The
    /// verifier groups entries by `(package, kind, topLevelTypeName, distro)`
    /// so it issues exactly one oracle JSON read per source IDL file.
    public static func buildVerifyPlan(
        _ runs: [PackageRun],
        distros allowedDistros: Set<String>? = nil
    ) throws -> [VerifyPlanEntry] {
        // Reuse the multi-package gather + register + hash sequence from
        // generateMulti so cross-package nested references resolve. We
        // collect one (run, ir, sourceLabel, topLevelTypeName) tuple per
        // generated MessageIR; for actions, the topLevelTypeName is the
        // outer .action stem rather than the contained sub-type's typeName.
        var unresolvedIRs: [(run: PackageRun, ir: MessageIR, sourceLabel: String, topLevelTypeName: String)] = []
        var collectedActions: [ParsedAction] = []

        var runsByPackage: [String: [PackageRun]] = [:]
        var packageOrder: [String] = []
        for run in runs {
            if runsByPackage[run.input.name] == nil { packageOrder.append(run.input.name) }
            runsByPackage[run.input.name, default: []].append(run)
        }
        for pkg in packageOrder {
            let pkgRuns = runsByPackage[pkg]!
            if pkgRuns.count == 1 {
                let run = pkgRuns[0]
                let parsed = try parsePackage(run: run)
                for entry in parsed {
                    unresolvedIRs.append(
                        (
                            run: run, ir: entry.ir, sourceLabel: entry.sourceLabel,
                            topLevelTypeName: entry.ir.typeName
                        ))
                }
                let services = try parseServicesIn(run: run)
                for svc in services {
                    let reqIR = IRBuilder.build(jazzy: svc.requestIDL, kind: .srv)
                    let resIR = IRBuilder.build(jazzy: svc.responseIDL, kind: .srv)
                    let label = sourceLabelFor(run: run, typeName: svc.typeName, kind: .srv)
                    unresolvedIRs.append(
                        (run: run, ir: reqIR, sourceLabel: label, topLevelTypeName: svc.typeName))
                    unresolvedIRs.append(
                        (run: run, ir: resIR, sourceLabel: label, topLevelTypeName: svc.typeName))
                }
                let actions = try parseActionsIn(run: run)
                for act in actions {
                    let label = sourceLabelFor(run: run, typeName: act.typeName, kind: .action)
                    let top = act.typeName
                    unresolvedIRs.append(
                        (run: run, ir: act.actionIR.goal, sourceLabel: label, topLevelTypeName: top))
                    unresolvedIRs.append(
                        (
                            run: run, ir: act.actionIR.result, sourceLabel: label,
                            topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: run, ir: act.actionIR.feedback, sourceLabel: label,
                            topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: run, ir: act.actionIR.sendGoalRequest, sourceLabel: label,
                            topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: run, ir: act.actionIR.sendGoalResponse, sourceLabel: label,
                            topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: run, ir: act.actionIR.getResultRequest, sourceLabel: label,
                            topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: run, ir: act.actionIR.getResultResponse, sourceLabel: label,
                            topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: run, ir: act.actionIR.feedbackMessage, sourceLabel: label,
                            topLevelTypeName: top
                        ))
                }
                collectedActions.append(contentsOf: actions)
            } else {
                let merged = try parseAndMergeMultiDistroPackage(runs: pkgRuns)
                let primaryRun = pkgRuns.first!
                for entry in merged {
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: entry.ir, sourceLabel: entry.sourceLabel,
                            topLevelTypeName: entry.ir.typeName
                        ))
                }
                let services = try parseServicesIn(run: primaryRun)
                for svc in services {
                    let reqIR = IRBuilder.build(jazzy: svc.requestIDL, kind: .srv)
                    let resIR = IRBuilder.build(jazzy: svc.responseIDL, kind: .srv)
                    let label = sourceLabelFor(
                        run: primaryRun, typeName: svc.typeName, kind: .srv)
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: reqIR, sourceLabel: label,
                            topLevelTypeName: svc.typeName
                        ))
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: resIR, sourceLabel: label,
                            topLevelTypeName: svc.typeName
                        ))
                }
                let actions = try parseActionsIn(run: primaryRun)
                for act in actions {
                    let label = sourceLabelFor(
                        run: primaryRun, typeName: act.typeName, kind: .action)
                    let top = act.typeName
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: act.actionIR.goal, sourceLabel: label,
                            topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: act.actionIR.result, sourceLabel: label,
                            topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: act.actionIR.feedback, sourceLabel: label,
                            topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: act.actionIR.sendGoalRequest,
                            sourceLabel: label, topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: act.actionIR.sendGoalResponse,
                            sourceLabel: label, topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: act.actionIR.getResultRequest,
                            sourceLabel: label, topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: act.actionIR.getResultResponse,
                            sourceLabel: label, topLevelTypeName: top
                        ))
                    unresolvedIRs.append(
                        (
                            run: primaryRun, ir: act.actionIR.feedbackMessage,
                            sourceLabel: label, topLevelTypeName: top
                        ))
                }
                collectedActions.append(contentsOf: actions)
            }
        }
        var registry: [String: MessageIR] = [:]
        for entry in unresolvedIRs {
            registry[entry.ir.rosTypeName] = entry.ir
        }
        try validateAllReferencesResolved(registry: registry)

        // For each distro the caller asked about (default: every distro any
        // IR was built against), compute the per-distro hash and emit one
        // VerifyPlanEntry per (ir, distro) pair. Distros that are out of
        // scope for an IR (e.g. Humble for a type that didn't exist on
        // Humble, or an IR that was built jazzy-only) are skipped.
        var out: [VerifyPlanEntry] = []
        for entry in unresolvedIRs {
            // Determine the distros this IR is "in scope" for.
            //   - Multi-distro merged IRs (Phase 4): one entry per distro
            //     in `perDistroFieldPresence`.
            //   - Single-distro IRs (Phase 1-3 messages, services,
            //     actions): the per-distro presence map is empty, so we
            //     fall back to the run's own `input.distro`. Hard-coding
            //     `"jazzy"` here would make `--input ...@kilted` (or
            //     `@rolling`) silently produce zero verify entries.
            let scopedDistros: [String]
            if entry.ir.perDistroFieldPresence.isEmpty {
                scopedDistros = [entry.run.input.distro]
            } else {
                scopedDistros = Array(entry.ir.perDistroFieldPresence.keys).sorted()
            }
            for distro in scopedDistros {
                if let allow = allowedDistros, !allow.contains(distro) { continue }
                // Humble does not have a hash oracle; rosidl pre-RIHS01.
                // Skip silently to keep the verify-mode focused on the
                // distros the rosidl `.json` files actually exist for.
                if distro == "humble" { continue }
                let hash = RIHS01.hash(entry.ir, for: distro, registry: registry)
                out.append(
                    VerifyPlanEntry(
                        package: entry.ir.package,
                        kind: entry.ir.kind,
                        typeName: entry.ir.typeName,
                        topLevelTypeName: entry.topLevelTypeName,
                        distro: distro,
                        expectedHash: hash
                    ))
            }
        }
        // NOTE: the action-level `<pkg>/action/<Type>` description is *not*
        // verified here. rosidl's canonical action-level type description
        // is built from the three constituent services (SendGoal,
        // GetResult, FeedbackMessage), not as a flat record of three
        // nested fields the way `IRBuilder.populateActionHashes`
        // synthesizes it for the generator's local typeInfo. The eight
        // wrapper / block hashes (which carry the wire format) are
        // verified above; the action-level hash drift is tracked as a
        // separate generator follow-up.
        _ = collectedActions
        return out
    }
}

/// One in-process expectation produced by ``Pipeline/buildVerifyPlan(_:distros:)``.
public struct VerifyPlanEntry: Sendable, Equatable {
    public let package: String
    public let kind: MessageKind
    /// Sub-type name (e.g. `"Fibonacci_SendGoal_Request"`).
    public let typeName: String
    /// Outermost IDL stem the oracle JSON file is named after (e.g.
    /// `"Fibonacci"`). The verifier groups requests by this stem so it
    /// issues exactly one `docker run cat <Type>.json` per source file.
    public let topLevelTypeName: String
    public let distro: String
    public let expectedHash: String

    /// Canonical ROS type name used for `type_hashes[*].type_name` lookup
    /// in the oracle JSON.
    public var rosTypeName: String { "\(package)/\(kind.rawValue)/\(typeName)" }

    public init(
        package: String,
        kind: MessageKind,
        typeName: String,
        topLevelTypeName: String,
        distro: String,
        expectedHash: String
    ) {
        self.package = package
        self.kind = kind
        self.typeName = typeName
        self.topLevelTypeName = topLevelTypeName
        self.distro = distro
        self.expectedHash = expectedHash
    }
}

extension Pipeline {
    private static func parsePackage(run: PackageRun) throws -> [ParsedEntry] {
        // Reject typo'd / nonexistent package directories up-front so the
        // srv-only tolerance below cannot mask a bad `--input` path.
        try requirePackageDirectory(run.input.directory)
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
        // Same guard as parsePackage: a missing package directory must surface
        // as a hard error rather than as an empty service list.
        try requirePackageDirectory(run.input.directory)
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
            // Validate the per-distro `--input` path before falling through to
            // the msg/ tolerance: a typo'd directory must not be silently
            // skipped (which would yield a partial multi-distro merge with no
            // diagnostics), only the absence of the `msg/` subdirectory inside
            // an otherwise-valid package directory is tolerated.
            try requirePackageDirectory(run.input.directory)
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

    /// Parse every `.msg` across `runs` and assemble a fully-resolved
    /// `[rosTypeName: MessageIR]` registry (keyed by `<pkg>/msg/<Type>`). Unlike
    /// ``generateMulti``, this stops short of hashing / emission — it exists so
    /// the native-RCL marshaller emitter (and its unit tests) can recurse into
    /// nested message IRs (`std_msgs/Header → builtin_interfaces/Time`, …)
    /// without re-implementing the cross-package gather.
    ///
    /// Single-distro (jazzy) IRs only: the marshaller flattens the rosidl C
    /// struct layout, which does not branch on distro, so a per-distro merge is
    /// unnecessary here. Service / action IRs are intentionally excluded; the
    /// marshaller targets `.msg` types.
    ///
    /// Throws ``GeneratorError/unresolvedNestedType(package:typeName:)`` when a
    /// nested reference cannot be resolved from the supplied `runs`.
    public static func buildMessageRegistry(_ runs: [PackageRun]) throws -> [String: MessageIR] {
        var registry: [String: MessageIR] = [:]
        for run in runs {
            for entry in try parsePackage(run: run) {
                registry[entry.ir.rosTypeName] = entry.ir
            }
        }
        try validateAllReferencesResolved(registry: registry)
        return registry
    }

    /// Native-RCL marshalling entry point. Builds the IR registry, determines
    /// the requested emit set (the union of each run's `typesAllowList`; when a
    /// run has no allow-list, every top-level `.msg` type from that package's
    /// directory), and produces the generated C + Swift marshalling files plus a
    /// resolver registry and aggregator header.
    ///
    /// File routing is via `relativePath` prefixes: `c/...` files belong under
    /// the `CRclBridge` target, `swift/...` files under `SwiftROS2RCL`. The CLI
    /// strips the leading prefix and writes under the matching output root.
    public static func generateRclMarshalling(_ runs: [PackageRun]) throws -> [GeneratedFile] {
        // Build the registry from allow-list-free runs so every nested
        // dependency (std_msgs/Header → builtin_interfaces/Time, …) is present
        // for flattening even when the caller passes a narrow `--types` filter
        // applied uniformly to every `--input`. The emit set below still honors
        // each run's original allow-list.
        let registryRuns = runs.map { PackageRun(input: $0.input, typesAllowList: nil) }
        let registry = try buildMessageRegistry(registryRuns)

        // Requested emit set = union of each run's allow-list. A run with no
        // allow-list contributes every top-level `.msg` type it parsed (keyed
        // back through the registry by `<pkg>/msg/<Type>`).
        var requestedRosNames = Set<String>()
        // Track every explicitly-requested bare type name and whether it
        // resolved to a `<pkg>/msg/<Type>` registry key under *any* run. A
        // typo'd `--types Imuu` would otherwise be silently dropped — producing
        // zero marshalling files and exiting 0 — which makes the regen-drift CI
        // guard pass while a type is absent. Surface it as a hard error instead
        // (mirrors the verify-mode empty-plan guard).
        var requestedBareNames = Set<String>()
        var resolvedBareNames = Set<String>()
        for run in runs {
            if let allow = run.typesAllowList {
                for typeName in allow {
                    requestedBareNames.insert(typeName)
                    let key = "\(run.input.name)/msg/\(typeName)"
                    if registry[key] != nil {
                        requestedRosNames.insert(key)
                        resolvedBareNames.insert(typeName)
                    }
                }
            } else {
                for entry in try parsePackage(run: run) {
                    requestedRosNames.insert(entry.ir.rosTypeName)
                }
            }
        }
        // The CLI applies the same `--types` allow-list to every `--input`, so
        // a name like `Imu` resolves only under sensor_msgs and is absent from
        // the other runs — that is expected. Only fail on names that resolved
        // under *no* run at all.
        let unresolvedBareNames = requestedBareNames.subtracting(resolvedBareNames)
        if !unresolvedBareNames.isEmpty {
            throw GeneratorError.unknownRequestedTypes(unresolvedBareNames.sorted())
        }
        if requestedRosNames.isEmpty {
            throw GeneratorError.unknownRequestedTypes([])
        }

        // Deterministic order: sort the requested IRs by ROS type name.
        let requestedIRs: [MessageIR] =
            requestedRosNames
            .sorted()
            .compactMap { registry[$0] }

        var files: [GeneratedFile] = []
        for ir in requestedIRs {
            let snake = CMarshalEmitter.snakeCase(ir.typeName)
            files.append(
                GeneratedFile(
                    relativePath: "c/Generated/crcl_marshal_\(snake).c",
                    contents: CMarshalEmitter.emit(ir, registry: registry)
                ))
            files.append(
                GeneratedFile(
                    relativePath: "c/include/Generated/crcl_marshal_\(snake).h",
                    contents: CMarshalEmitter.emitHeader(ir, registry: registry)
                ))
            let structName = SwiftEmitter.swiftStructName(typeName: ir.typeName)
            files.append(
                GeneratedFile(
                    relativePath: "swift/\(structName)+RclMarshal.swift",
                    contents: RclMarshalSwiftEmitter.emit(ir, registry: registry)
                ))
        }

        // Registry C file: typesupport resolver over all requested types.
        files.append(
            GeneratedFile(
                relativePath: "c/Generated/crcl_marshal_registry.c",
                contents: emitRegistryC(requestedIRs)
            ))
        // Aggregator header.
        files.append(
            GeneratedFile(
                relativePath: "c/include/crcl_marshal.h",
                contents: emitAggregatorHeader(requestedIRs)
            ))
        return files
    }

    /// The `crcl_marshal_resolve_typesupport` resolver: a `strcmp` chain (sorted
    /// by ROS type name for determinism) mapping each requested type's ROS name
    /// to its `crcl_typesupport_<snake>()` accessor.
    private static func emitRegistryC(_ irs: [MessageIR]) -> String {
        let sorted = irs.sorted { $0.rosTypeName < $1.rosTypeName }
        var lines: [String] = []
        lines.append("// Generated by swift-ros2-gen — DO NOT EDIT.")
        lines.append("")
        lines.append("#include \"crcl_marshal.h\"")
        lines.append("")
        lines.append("#include <string.h>")
        lines.append("")
        lines.append(
            "const rosidl_message_type_support_t *crcl_marshal_resolve_typesupport(const char *name) {")
        for ir in sorted {
            let snake = CMarshalEmitter.snakeCase(ir.typeName)
            lines.append("    if (strcmp(name, \"\(ir.rosTypeName)\") == 0) {")
            lines.append("        return crcl_typesupport_\(snake)();")
            lines.append("    }")
        }
        lines.append("    return NULL;")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The aggregator header `crcl_marshal.h`: `#include`s every per-type header
    /// (sorted) and declares `crcl_marshal_resolve_typesupport`. Consumed by
    /// `rcl_bridge.h` (which `#include`s it) so the decls reach Swift.
    private static func emitAggregatorHeader(_ irs: [MessageIR]) -> String {
        let sorted = irs.sorted { $0.rosTypeName < $1.rosTypeName }
        var lines: [String] = []
        lines.append("// Generated by swift-ros2-gen — DO NOT EDIT.")
        lines.append("")
        lines.append("#ifndef CRCL_MARSHAL_H")
        lines.append("#define CRCL_MARSHAL_H")
        lines.append("")
        lines.append("#include <rosidl_runtime_c/message_type_support_struct.h>")
        lines.append("")
        for ir in sorted {
            let snake = CMarshalEmitter.snakeCase(ir.typeName)
            lines.append("#include \"Generated/crcl_marshal_\(snake).h\"")
        }
        lines.append("")
        lines.append("#ifdef __cplusplus")
        lines.append("extern \"C\" {")
        lines.append("#endif")
        lines.append("")
        lines.append(
            "const rosidl_message_type_support_t *crcl_marshal_resolve_typesupport(const char *name);")
        lines.append("")
        lines.append("#ifdef __cplusplus")
        lines.append("}")
        lines.append("#endif")
        lines.append("#endif  // CRCL_MARSHAL_H")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func validateAllReferencesResolved(registry: [String: MessageIR]) throws {
        for (_, ir) in registry {
            for field in ir.fields {
                guard case .nested(let pkg, let type) = field.type else { continue }
                // Phase 6: a nested reference may resolve under msg, srv, or
                // action — accept the first kind found in the registry.
                var resolved = false
                for kind in MessageKind.allCases {
                    if registry["\(pkg)/\(kind.rawValue)/\(type)"] != nil {
                        resolved = true
                        break
                    }
                }
                if !resolved {
                    throw GeneratorError.unresolvedNestedType(package: pkg, typeName: type)
                }
            }
        }
    }
}

extension Pipeline {
    /// Lightweight carrier for an as-parsed `.action`. The fully-built
    /// ``ActionIR`` lives here so the emitter can read out the eight contained
    /// ``MessageIR``s plus the per-distro hash bundle without re-running the
    /// builder.
    public struct ParsedAction: Equatable, Sendable {
        public let package: String
        public let typeName: String
        public let actionIR: ActionIR

        public init(package: String, typeName: String, actionIR: ActionIR) {
            self.package = package
            self.typeName = typeName
            self.actionIR = actionIR
        }
    }

    /// Enumerate `<pkg>/action/*.action` for the run, parse each into the
    /// three user-defined blocks + five synthesized wrappers via
    /// ``IRBuilder/build(jazzy:)``, and return them as ``ParsedAction``
    /// carriers. Returns an empty array when the package has no `action/`
    /// subdirectory at all (the common case for pure message / service
    /// packages). The same `typesAllowList` filter applies as for messages —
    /// it matches the bare action type name (`Fibonacci`).
    public static func parseActionsIn(run: PackageRun) throws -> [ParsedAction] {
        let actionDir = run.input.directory.appendingPathComponent("action", isDirectory: true)
        var isDir: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: actionDir.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            return []
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: actionDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let actionFiles =
            entries
            .filter { $0.pathExtension == "action" }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        var out: [ParsedAction] = []
        for fileURL in actionFiles {
            let typeName = fileURL.deletingPathExtension().lastPathComponent
            if let allow = run.typesAllowList, !allow.contains(typeName) { continue }
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let label = sourceLabelFor(run: run, typeName: typeName, kind: .action)
            do {
                let idl = try Parser.parseAction(
                    source: contents,
                    file: label,
                    package: run.input.name,
                    typeName: typeName
                )
                let ir = IRBuilder.build(jazzy: idl)
                out.append(
                    ParsedAction(
                        package: run.input.name,
                        typeName: typeName,
                        actionIR: ir
                    ))
            } catch let err as ParseError {
                throw GeneratorError.parse(err)
            }
        }
        return out
    }
}
