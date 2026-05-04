/// Transforms a parsed ``IDLFile`` into the distro-neutral ``MessageIR`` used by the emitter.
public enum IRBuilder {
    public static func build(jazzy idl: IDLFile) -> MessageIR {
        let fields = idl.fields.map { field -> FieldIR in
            switch field.type {
            case .primitive(let prim):
                return FieldIR(
                    ros2Name: field.name,
                    swiftName: snakeToCamel(field.name),
                    type: .primitive(prim)
                )
            case .nested:
                // Nested-type lowering arrives in Phase 2 Task 5 (IRBuilder
                // resolution + MessageIR.FieldType.nested). The AST case is
                // wired here in Task 2 only so callers can construct the new
                // value; until Task 5 lands, lowering a nested field is a
                // programming error.
                fatalError("IDLFieldType.nested lowering not yet implemented (Phase 2 Task 5)")
            }
        }
        return MessageIR(package: idl.package, typeName: idl.typeName, fields: fields)
    }

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
