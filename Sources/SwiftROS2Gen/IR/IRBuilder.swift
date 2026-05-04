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
