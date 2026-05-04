import Foundation

/// Transforms a parsed ``IDLFile`` into the distro-neutral ``MessageIR`` used by the emitter.
public enum IRBuilder {
    /// Throwing build path. Translates the parser AST into the IR, parses every
    /// field default expression into a typed ``DefaultValue``, and validates
    /// constants (range-checks integers, parses bools, etc.). Surfaces every
    /// validation issue as ``IRBuildError``.
    public static func buildOrThrow(jazzy idl: IDLFile, kind: MessageKind = .msg) throws -> MessageIR {
        let fields = try idl.fields.map { f -> FieldIR in
            let irType = lift(f.type, currentPackage: idl.package)
            let dv = try f.defaultExpression.map {
                try parseDefault($0, for: irType, fieldName: f.name)
            }
            return FieldIR(
                ros2Name: f.name,
                swiftName: snakeToCamel(f.name),
                type: irType,
                defaultValue: dv
            )
        }
        let constants = try idl.constants.map { c -> ConstantIR in
            let dv = try parseConstantValue(c.value, type: c.type, name: c.name)
            return ConstantIR(ros2Name: c.name, swiftName: c.name, type: c.type, value: dv)
        }
        return MessageIR(
            package: idl.package,
            typeName: idl.typeName,
            kind: kind,
            fields: fields,
            constants: constants
        )
    }

    /// Back-compat non-throwing entry point. Existing callers (Pipeline) still
    /// invoke this; range / shape errors trip a `preconditionFailure`. Task 9 /
    /// Task 11 will move callers to ``buildOrThrow(jazzy:)`` so errors propagate
    /// as ``GeneratorError``.
    public static func build(jazzy idl: IDLFile, kind: MessageKind = .msg) -> MessageIR {
        do {
            return try buildOrThrow(jazzy: idl, kind: kind)
        } catch {
            preconditionFailure("IRBuilder.build hit \(error) — use buildOrThrow")
        }
    }

    // MARK: - Lifting

    static func lift(_ t: IDLFieldType, currentPackage: String) -> FieldType {
        switch t {
        case .primitive(let p):
            return .primitive(p)
        case .nested(let pkg, let name):
            return .nested(package: pkg ?? currentPackage, typeName: name)
        case .array(let e, let n):
            return .array(element: lift(e, currentPackage: currentPackage), length: n)
        case .sequence(let e, let upper):
            return .sequence(element: lift(e, currentPackage: currentPackage), upperBound: upper)
        case .boundedString(let wide, let n):
            return .boundedString(isWide: wide, upperBound: n)
        }
    }

    // MARK: - Defaults

    static func parseDefault(
        _ expr: String,
        for type: FieldType,
        fieldName: String
    ) throws -> DefaultValue {
        switch type {
        case .primitive(let p):
            return try parseConstantValue(expr, type: p, name: fieldName)
        case .array(let element, let length):
            let trimmed = expr.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
                throw IRBuildError(
                    "default for array field '\(fieldName)' must be '[...]', got '\(expr)'"
                )
            }
            let inside = String(trimmed.dropFirst().dropLast())
            let items = inside.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard items.count == length else {
                throw IRBuildError(
                    "default for '\(fieldName)' has \(items.count) elements, expected \(length)"
                )
            }
            let parsed = try items.map {
                try parseDefault($0, for: element, fieldName: fieldName)
            }
            return .array(parsed)
        case .sequence:
            return .empty
        case .boundedString(_, let upper):
            let stripped =
                expr.hasPrefix("\"") && expr.hasSuffix("\"") && expr.count >= 2
                ? String(expr.dropFirst().dropLast())
                : expr
            if stripped.count > upper {
                throw IRBuildError(
                    "default for bounded-string field '\(fieldName)' has \(stripped.count) chars, exceeds bound \(upper)"
                )
            }
            return .string(stripped)
        case .nested:
            throw IRBuildError("nested field '\(fieldName)' cannot have a default value")
        }
    }

    // MARK: - Constant values

    static func parseConstantValue(
        _ raw: String,
        type: PrimitiveType,
        name: String
    ) throws -> DefaultValue {
        switch type {
        case .bool:
            guard let b = parseBool(raw) else {
                throw IRBuildError("'\(name)' bool literal must be true/false/1/0, got '\(raw)'")
            }
            return .bool(b)
        case .int8, .int16, .int32, .int64, .char:
            guard let n = Int64(raw) else {
                throw IRBuildError(
                    "'\(name)' \(type.rawValue) literal '\(raw)' is not an integer"
                )
            }
            try validateIntRange(n, type: type, name: name)
            return .int(n)
        case .uint8, .uint16, .uint32, .uint64, .byte:
            guard let n = UInt64(raw) else {
                throw IRBuildError(
                    "'\(name)' \(type.rawValue) literal '\(raw)' is not a non-negative integer"
                )
            }
            try validateUIntRange(n, type: type, name: name)
            return .uint(n)
        case .float32, .float64:
            guard let d = Double(raw) else {
                throw IRBuildError(
                    "'\(name)' \(type.rawValue) literal '\(raw)' is not a number"
                )
            }
            return .float(d)
        case .string, .wstring:
            let stripped =
                raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2
                ? String(raw.dropFirst().dropLast())
                : raw
            return .string(stripped)
        }
    }

    static func parseBool(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }

    static func validateIntRange(_ n: Int64, type: PrimitiveType, name: String) throws {
        let lo: Int64
        let hi: Int64
        switch type {
        case .char, .int8: (lo, hi) = (Int64(Int8.min), Int64(Int8.max))
        case .int16: (lo, hi) = (Int64(Int16.min), Int64(Int16.max))
        case .int32: (lo, hi) = (Int64(Int32.min), Int64(Int32.max))
        case .int64: (lo, hi) = (Int64.min, Int64.max)
        default: return
        }
        guard n >= lo, n <= hi else {
            throw IRBuildError(
                "constant '\(name)' value \(n) out of range for \(type.rawValue) (\(lo)...\(hi))"
            )
        }
    }

    static func validateUIntRange(_ n: UInt64, type: PrimitiveType, name: String) throws {
        let hi: UInt64
        switch type {
        case .byte, .uint8: hi = UInt64(UInt8.max)
        case .uint16: hi = UInt64(UInt16.max)
        case .uint32: hi = UInt64(UInt32.max)
        case .uint64: hi = UInt64.max
        default: return
        }
        guard n <= hi else {
            throw IRBuildError(
                "constant '\(name)' value \(n) out of range for \(type.rawValue) (0...\(hi))"
            )
        }
    }

    // MARK: - Naming

    static func snakeToCamel(_ snake: String) -> String {
        var leadingUnderscores = 0
        for ch in snake {
            if ch == "_" { leadingUnderscores += 1 } else { break }
        }
        let core = String(snake.dropFirst(leadingUnderscores))
        let parts = core.split(separator: "_", omittingEmptySubsequences: true)
        guard let first = parts.first else { return snake }
        var result = String(repeating: "_", count: leadingUnderscores)
        result += first.lowercased()
        for part in parts.dropFirst() {
            result += part.prefix(1).uppercased() + part.dropFirst().lowercased()
        }
        return result
    }
}

extension IRBuilder {
    /// Build an ``ActionIR`` from a parsed ``IDLAction``.
    ///
    /// Each of the three user-defined blocks becomes a ``MessageIR`` named
    /// `<typeName>_Goal` / `_Result` / `_Feedback` (matching what rosidl emits
    /// for the per-block type descriptions). Five wire-level wrapper IRs are
    /// then synthesized per the rcl action protocol, each containing nested
    /// references back to the user-defined IRs (matching the rosidl JSON):
    /// `<typeName>_SendGoal_Request` (UUID `goal_id` + nested `<typeName>_Goal`),
    /// `<typeName>_SendGoal_Response` (bool `accepted` + `builtin_interfaces/Time`),
    /// `<typeName>_GetResult_Request` (UUID `goal_id`), `<typeName>_GetResult_Response`
    /// (int8 `status` + nested `<typeName>_Result`), and
    /// `<typeName>_FeedbackMessage` (UUID `goal_id` + nested `<typeName>_Feedback`).
    /// All eight resulting IRs carry ``MessageKind/action`` so their canonical
    /// ROS type name renders with the `action/` segment.
    public static func build(jazzy idl: IDLAction) -> ActionIR {
        let goal = build(jazzy: idl.goal, kind: .action)
        let result = build(jazzy: idl.result, kind: .action)
        let feedback = build(jazzy: idl.feedback, kind: .action)

        let wrappers = synthesizeActionWrappers(
            actionPackage: idl.package,
            actionTypeName: idl.typeName,
            goalFields: goal.fields,
            resultFields: result.fields,
            feedbackFields: feedback.fields
        )

        return ActionIR(
            package: idl.package,
            typeName: idl.typeName,
            goal: goal,
            result: result,
            feedback: feedback,
            sendGoalRequest: wrappers.sendGoalRequest,
            sendGoalResponse: wrappers.sendGoalResponse,
            getResultRequest: wrappers.getResultRequest,
            getResultResponse: wrappers.getResultResponse,
            feedbackMessage: wrappers.feedbackMessage
        )
    }

    /// Synthesize the five wire-level wrapper ``MessageIR``s per the rcl action
    /// protocol. Field shapes mirror the hand-written generic wrappers in
    /// `BuiltinActions/ActionWrappers.swift` (kept until they are deleted in
    /// the same phase that ships this synthesis).
    static func synthesizeActionWrappers(
        actionPackage: String,
        actionTypeName: String,
        goalFields: [FieldIR],
        resultFields: [FieldIR],
        feedbackFields: [FieldIR]
    ) -> (
        sendGoalRequest: MessageIR,
        sendGoalResponse: MessageIR,
        getResultRequest: MessageIR,
        getResultResponse: MessageIR,
        feedbackMessage: MessageIR
    ) {
        let goalIdField = FieldIR(
            ros2Name: "goal_id",
            swiftName: "goalId",
            type: .nested(package: "unique_identifier_msgs", typeName: "UUID")
        )
        let acceptedField = FieldIR(
            ros2Name: "accepted",
            swiftName: "accepted",
            type: .primitive(.bool)
        )
        let stampField = FieldIR(
            ros2Name: "stamp",
            swiftName: "stamp",
            type: .nested(package: "builtin_interfaces", typeName: "Time")
        )
        let statusField = FieldIR(
            ros2Name: "status",
            swiftName: "status",
            type: .primitive(.int8)
        )
        let goalNestedField = FieldIR(
            ros2Name: "goal",
            swiftName: "goal",
            type: .nested(package: actionPackage, typeName: "\(actionTypeName)_Goal")
        )
        let resultNestedField = FieldIR(
            ros2Name: "result",
            swiftName: "result",
            type: .nested(package: actionPackage, typeName: "\(actionTypeName)_Result")
        )
        let feedbackNestedField = FieldIR(
            ros2Name: "feedback",
            swiftName: "feedback",
            type: .nested(package: actionPackage, typeName: "\(actionTypeName)_Feedback")
        )

        let sendGoalRequest = MessageIR(
            package: actionPackage,
            typeName: "\(actionTypeName)_SendGoal_Request",
            kind: .action,
            fields: [goalIdField, goalNestedField]
        )
        let sendGoalResponse = MessageIR(
            package: actionPackage,
            typeName: "\(actionTypeName)_SendGoal_Response",
            kind: .action,
            fields: [acceptedField, stampField]
        )
        let getResultRequest = MessageIR(
            package: actionPackage,
            typeName: "\(actionTypeName)_GetResult_Request",
            kind: .action,
            fields: [goalIdField]
        )
        let getResultResponse = MessageIR(
            package: actionPackage,
            typeName: "\(actionTypeName)_GetResult_Response",
            kind: .action,
            fields: [statusField, resultNestedField]
        )
        let feedbackMessage = MessageIR(
            package: actionPackage,
            typeName: "\(actionTypeName)_FeedbackMessage",
            kind: .action,
            fields: [goalIdField, feedbackNestedField]
        )

        _ = (goalFields, resultFields, feedbackFields)  // referenced via the nested wrappers above

        return (sendGoalRequest, sendGoalResponse, getResultRequest, getResultResponse, feedbackMessage)
    }
}

extension IRBuilder {
    /// Compute RIHS01 hashes for every contained ``MessageIR`` (Goal / Result
    /// / Feedback + 5 wire wrappers) and write them into
    /// `ir.perDistroHashes[distro]`. The provided `extraRegistry` must contain
    /// at least `unique_identifier_msgs/msg/UUID` and
    /// `builtin_interfaces/msg/Time` because the wrappers reference them; the
    /// per-action user IRs are added automatically.
    ///
    /// We intentionally do **not** synthesize the action-level
    /// `<pkg>/action/<Type>` hash. rosidl computes that from a six-field
    /// record that references additional service-shaped wrappers
    /// (`<Type>_SendGoal`, `<Type>_GetResult`, plus `_Event` types and
    /// `service_msgs/msg/ServiceEventInfo`) that this generator does not
    /// emit. The wire format only depends on the eight wrapper / block hashes
    /// stored here; emitting a synthetic action-level value that disagrees
    /// with upstream would be worse than omitting it.
    public static func populateActionHashes(
        _ ir: inout ActionIR,
        distro: String,
        extraRegistry: [String: MessageIR] = [:]
    ) {
        // Build the registry: extras (UUID, Time, ...) plus the per-action
        // user IRs (Goal/Result/Feedback) so the wrappers can resolve their
        // nested references.
        var registry = extraRegistry
        registry[ir.goal.rosTypeName] = ir.goal
        registry[ir.result.rosTypeName] = ir.result
        registry[ir.feedback.rosTypeName] = ir.feedback
        registry[ir.sendGoalRequest.rosTypeName] = ir.sendGoalRequest
        registry[ir.sendGoalResponse.rosTypeName] = ir.sendGoalResponse
        registry[ir.getResultRequest.rosTypeName] = ir.getResultRequest
        registry[ir.getResultResponse.rosTypeName] = ir.getResultResponse
        registry[ir.feedbackMessage.rosTypeName] = ir.feedbackMessage

        let goalHash = RIHS01.hash(ir.goal, registry: registry)
        let resultHash = RIHS01.hash(ir.result, registry: registry)
        let feedbackHash = RIHS01.hash(ir.feedback, registry: registry)
        let sgReqHash = RIHS01.hash(ir.sendGoalRequest, registry: registry)
        let sgRespHash = RIHS01.hash(ir.sendGoalResponse, registry: registry)
        let grReqHash = RIHS01.hash(ir.getResultRequest, registry: registry)
        let grRespHash = RIHS01.hash(ir.getResultResponse, registry: registry)
        let fbMsgHash = RIHS01.hash(ir.feedbackMessage, registry: registry)

        // Store per-message hashes on the contained IRs so the emitter (which
        // reuses the message emitter for each wrapper) can read them out of
        // `perDistroHashes["jazzy"]` like any normal MessageIR.
        ir.goal.perDistroHashes[distro] = goalHash
        ir.result.perDistroHashes[distro] = resultHash
        ir.feedback.perDistroHashes[distro] = feedbackHash
        ir.sendGoalRequest.perDistroHashes[distro] = sgReqHash
        ir.sendGoalResponse.perDistroHashes[distro] = sgRespHash
        ir.getResultRequest.perDistroHashes[distro] = grReqHash
        ir.getResultResponse.perDistroHashes[distro] = grRespHash
        ir.feedbackMessage.perDistroHashes[distro] = fbMsgHash

        ir.perDistroHashes[distro] = ActionHashes(
            goalHash: goalHash,
            resultHash: resultHash,
            feedbackHash: feedbackHash,
            sendGoalRequestHash: sgReqHash,
            sendGoalResponseHash: sgRespHash,
            getResultRequestHash: grReqHash,
            getResultResponseHash: grRespHash,
            feedbackMessageHash: fbMsgHash
        )
    }
}

/// An error produced by ``IRBuilder`` while validating defaults / constants.
public struct IRBuildError: Error, CustomStringConvertible, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

extension IRBuilder {
    /// Canonical ordering of distros for the multi-distro merge walk. Older
    /// distros come first so their field order takes precedence when a field
    /// is shared with a newer distro.
    public static let distroOrder: [String] = ["humble", "jazzy", "kilted", "rolling"]

    /// Build a unified IR from one parsed IDL per distro.
    ///
    /// Walks `idls` in `distroOrder`. For each distro, fields appear in source
    /// order; new fields are appended at the position they first surface. Each
    /// resulting `FieldIR.availability` reflects the set of distros that
    /// declared the field, simplified to `.all` when every input distro had it.
    ///
    /// Constants and defaults are taken from the latest (highest-precedence)
    /// distro that declares each name — newer distros own the canonical
    /// representation when a constant value or default expression diverges.
    /// Constants are not part of the wire schema, so they do not participate
    /// in conflict detection.
    ///
    /// Throws `IRMergeError.conflictingFieldType` when the same `ros2Name`
    /// resolves to incompatible `FieldType`s across distros, and
    /// `IRMergeError.identityMismatch` when distros disagree on the package
    /// or type name.
    public static func build(
        perDistro idls: [String: IDLFile],
        kind: MessageKind = .msg
    ) throws -> MessageIR {
        precondition(!idls.isEmpty, "IRBuilder.build(perDistro:) needs at least one IDL")

        // Validate identity (package/typeName) agreement across all input distros.
        var identityPerDistro: [String: String] = [:]
        for (distro, idl) in idls {
            identityPerDistro[distro] = "\(idl.package)/\(idl.typeName)"
        }
        if Set(identityPerDistro.values).count > 1 {
            let any = idls.first!.value
            throw IRMergeError(
                kind: .identityMismatch(perDistroIdentity: identityPerDistro),
                typeName: "\(any.package)/\(any.typeName)"
            )
        }
        let firstKey = idls.keys.sorted().first!
        let canonicalPackage = idls[firstKey]!.package
        let canonicalType = idls[firstKey]!.typeName

        // Walk the distros in canonical order; only consider distros actually present.
        let orderedDistros = distroOrder.filter { idls[$0] != nil }

        // Track field types and the distros each field appears in.
        var fieldOrder: [String] = []
        var fieldTypeByName: [String: FieldType] = [:]
        // Carry through the field-level metadata (default, swiftName) of the
        // latest distro that declared the field; newer distros win.
        var latestFieldByName: [String: (default: DefaultValue?, swiftName: String)] = [:]
        var fieldTypeConflict: [String: [String: FieldType]] = [:]
        var presenceByName: [String: Set<String>] = [:]
        var presencePerDistro: [String: Set<String>] = [:]

        for distro in orderedDistros {
            let idl = idls[distro]!
            var thisDistroPresence: Set<String> = []
            for f in idl.fields {
                let irType = lift(f.type, currentPackage: idl.package)
                thisDistroPresence.insert(f.name)
                if let existing = fieldTypeByName[f.name] {
                    if existing != irType {
                        var bucket = fieldTypeConflict[f.name] ?? [:]
                        // Backfill the canonical type for already-walked distros that had it.
                        for prior in orderedDistros {
                            if prior == distro { break }
                            if presenceByName[f.name]?.contains(prior) == true {
                                bucket[prior] = existing
                            }
                        }
                        bucket[distro] = irType
                        fieldTypeConflict[f.name] = bucket
                    }
                } else {
                    fieldTypeByName[f.name] = irType
                    fieldOrder.append(f.name)
                }
                let dv = try f.defaultExpression.map {
                    try parseDefault($0, for: irType, fieldName: f.name)
                }
                latestFieldByName[f.name] = (dv, snakeToCamel(f.name))
                presenceByName[f.name, default: []].insert(distro)
            }
            presencePerDistro[distro] = thisDistroPresence
        }

        if let (name, perDistroTypes) = fieldTypeConflict.first {
            throw IRMergeError(
                kind: .conflictingFieldType(name: name, perDistroTypes: perDistroTypes),
                typeName: "\(canonicalPackage)/\(canonicalType)"
            )
        }

        let allDistros = Set(orderedDistros)
        let fields: [FieldIR] = fieldOrder.map { name in
            let type = fieldTypeByName[name]!
            let presence = presenceByName[name]!
            let availability: FieldAvailability =
                presence == allDistros ? .all : .onlyIn(presence)
            let meta = latestFieldByName[name]!
            return FieldIR(
                ros2Name: name,
                swiftName: meta.swiftName,
                type: type,
                defaultValue: meta.default,
                availability: availability
            )
        }

        // Constants: take the union; later distros win on conflicting values.
        // Constants do not participate in the RIHS01 hash so a value mismatch
        // is not treated as an error here.
        var constantsByName: [String: ConstantIR] = [:]
        var constantOrder: [String] = []
        for distro in orderedDistros {
            let idl = idls[distro]!
            for c in idl.constants {
                let dv = try parseConstantValue(c.value, type: c.type, name: c.name)
                let cir = ConstantIR(
                    ros2Name: c.name, swiftName: c.name, type: c.type, value: dv)
                if constantsByName[c.name] == nil {
                    constantOrder.append(c.name)
                }
                constantsByName[c.name] = cir
            }
        }
        let constants = constantOrder.compactMap { constantsByName[$0] }

        return MessageIR(
            package: canonicalPackage,
            typeName: canonicalType,
            kind: kind,
            fields: fields,
            constants: constants,
            perDistroHashes: [:],  // populated by Pipeline (Task 6)
            perDistroFieldPresence: presencePerDistro
        )
    }
}
