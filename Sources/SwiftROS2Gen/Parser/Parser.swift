import Foundation

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
            guard tokens.count == 2 else {
                throw ParseError(
                    file: file,
                    line: lineNumber,
                    message: "expected '<type> <name>' (Phase 1: primitive types only); got '\(stripped)'"
                )
            }
            let typeToken = tokens[0]
            let nameToken = tokens[1]
            guard let primitive = PrimitiveType(rawROS: typeToken) else {
                throw ParseError(
                    file: file,
                    line: lineNumber,
                    message: "unsupported type '\(typeToken)' (Phase 1: primitive types only)"
                )
            }
            try validateFieldName(nameToken, file: file, line: lineNumber)
            fields.append(IDLField(name: nameToken, type: .primitive(primitive), sourceLine: lineNumber))
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
}
