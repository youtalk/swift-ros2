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
