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
            // Phase 3 will surface defaults explicitly.
            let typeToken = tokens[0]
            let nameToken = tokens[1]
            if typeToken.contains("[") {
                throw ParseError(
                    file: file,
                    line: lineNumber,
                    message: "array fields are not yet supported (Phase 3): '\(typeToken)'"
                )
            }
            let fieldType: IDLFieldType
            if let primitive = PrimitiveType(rawROS: typeToken) {
                fieldType = .primitive(primitive)
            } else if let nested = parseNestedTypeToken(typeToken) {
                fieldType = nested
            } else {
                throw ParseError(
                    file: file,
                    line: lineNumber,
                    message: "unsupported type '\(typeToken)'"
                )
            }
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

    /// Returns a `.nested` IDLFieldType if `token` looks like a message reference, else nil.
    /// Accepted shapes:
    ///   - `<CamelCase>`          → nested(package: nil, typeName: token)
    ///   - `<snake_pkg>/<CamelCase>` → nested(package: pkg, typeName: type)
    static func parseNestedTypeToken(_ token: String) -> IDLFieldType? {
        if let slash = token.firstIndex(of: "/") {
            let pkgPart = String(token[..<slash])
            let typePart = String(token[token.index(after: slash)...])
            guard isValidPackageName(pkgPart), isValidTypeName(typePart) else { return nil }
            return .nested(package: pkgPart, typeName: typePart)
        }
        guard isValidTypeName(token) else { return nil }
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
