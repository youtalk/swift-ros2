import Foundation

/// Parses `.msg` source text into an ``IDLFile`` (Phase 1: primitive fields only).
public enum Parser {
    public static func parseMessage(
        source: String,
        file: String,
        package: String,
        typeName: String
    ) throws -> IDLFile {
        var fields: [IDLField] = []
        let rawLines = source.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, raw) in rawLines.enumerated() {
            let lineNumber = index + 1
            let stripped = stripCommentAndTrim(String(raw))
            if stripped.isEmpty { continue }
            let tokens = stripped.split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)
            guard tokens.count >= 2 else {
                throw ParseError(
                    file: file,
                    line: lineNumber,
                    message: "expected '<type> <name>'; got '\(stripped)'"
                )
            }
            // Trailing tokens (default values, comments-as-tokens) are ignored in Phase 2.
            // Defaults are stripped before hashing per rosidl_generator_type_description,
            // so this matches the upstream behaviour for hash purposes.
            // Phase 3 Task 5 surfaces defaults explicitly.
            let typeToken = tokens[0]
            let nameToken = tokens[1]
            let fieldType = try parseTypeToken(
                typeToken,
                currentPackage: package,
                file: file,
                line: lineNumber
            )
            try validateFieldName(nameToken, file: file, line: lineNumber)
            fields.append(IDLField(name: nameToken, type: fieldType, sourceLine: lineNumber))
        }
        return IDLFile(package: package, typeName: typeName, fields: fields)
    }

    static func stripCommentAndTrim(_ line: String) -> String {
        if let hashIndex = line.firstIndex(of: "#") {
            return String(line[..<hashIndex]).trimmingCharacters(in: .whitespaces)
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    static func validateFieldName(_ name: String, file: String, line: Int) throws {
        guard let first = name.first else {
            throw ParseError(file: file, line: line, message: "empty field name")
        }
        guard first.isLetter || first == "_" else {
            throw ParseError(
                file: file,
                line: line,
                message: "field name must start with a letter or underscore: '\(name)'"
            )
        }
        for ch in name where !(ch.isLetter || ch.isNumber || ch == "_") {
            throw ParseError(
                file: file,
                line: line,
                message: "field name contains invalid character '\(ch)': '\(name)'"
            )
        }
    }

    /// Decompose a type token like `uint8[16]`, `float32[<=8]`, `string<=255`,
    /// or `geometry_msgs/Vector3[]` into an `IDLFieldType`.
    static func parseTypeToken(
        _ token: String,
        currentPackage: String,
        file: String,
        line: Int
    ) throws -> IDLFieldType {
        if let openIdx = token.firstIndex(of: "[") {
            guard let closeIdx = token.lastIndex(of: "]"), closeIdx > openIdx else {
                throw ParseError(
                    file: file,
                    line: line,
                    message: "malformed array/sequence token '\(token)' \u{2014} missing ']'"
                )
            }
            let baseToken = String(token[..<openIdx])
            let inside = String(token[token.index(after: openIdx)..<closeIdx])
            let element = try parseScalarTypeToken(
                baseToken, currentPackage: currentPackage, file: file, line: line
            )
            if inside.isEmpty {
                return .sequence(element: element, upperBound: nil)
            }
            if inside.hasPrefix("<=") {
                let bound = String(inside.dropFirst(2))
                guard let n = Int(bound), n > 0 else {
                    throw ParseError(
                        file: file,
                        line: line,
                        message: "invalid bounded-sequence size '\(inside)' in '\(token)'"
                    )
                }
                return .sequence(element: element, upperBound: n)
            }
            guard let n = Int(inside), n > 0 else {
                throw ParseError(
                    file: file,
                    line: line,
                    message: "invalid fixed-array size '\(inside)' in '\(token)'"
                )
            }
            return .array(element: element, length: n)
        }
        if let leqRange = token.range(of: "<=") {
            let head = String(token[..<leqRange.lowerBound])
            let tail = String(token[leqRange.upperBound...])
            guard let n = Int(tail), n > 0 else {
                throw ParseError(
                    file: file,
                    line: line,
                    message: "invalid bounded-string size in '\(token)'"
                )
            }
            switch head {
            case "string": return .boundedString(isWide: false, upperBound: n)
            case "wstring": return .boundedString(isWide: true, upperBound: n)
            default:
                throw ParseError(
                    file: file,
                    line: line,
                    message: "'<=' suffix only valid on string/wstring; got '\(head)'"
                )
            }
        }
        return try parseScalarTypeToken(
            token, currentPackage: currentPackage, file: file, line: line
        )
    }

    /// Resolve a non-decorated scalar type token into a primitive or nested ref.
    static func parseScalarTypeToken(
        _ token: String,
        currentPackage: String,
        file: String,
        line: Int
    ) throws -> IDLFieldType {
        if let prim = PrimitiveType(rawROS: token) {
            return .primitive(prim)
        }
        if let slash = token.firstIndex(of: "/") {
            let pkgPart = String(token[..<slash])
            let typePart = String(token[token.index(after: slash)...])
            guard isValidPackageName(pkgPart), isValidTypeName(typePart) else {
                throw ParseError(
                    file: file,
                    line: line,
                    message: "unsupported type '\(token)'"
                )
            }
            return .nested(package: pkgPart, typeName: typePart)
        }
        guard isValidTypeName(token) else {
            throw ParseError(
                file: file,
                line: line,
                message: "unsupported type '\(token)'"
            )
        }
        return .nested(package: nil, typeName: token)
    }

    static func isValidTypeName(_ s: String) -> Bool {
        guard let first = s.first, first.isUppercase else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func isValidPackageName(_ s: String) -> Bool {
        guard let first = s.first, first.isLetter || first == "_" else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
