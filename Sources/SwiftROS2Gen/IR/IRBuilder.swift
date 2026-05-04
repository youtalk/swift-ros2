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
            case .nested(let pkg, let type):
                let resolvedPackage = pkg ?? idl.package
                return FieldIR(
                    ros2Name: field.name,
                    swiftName: snakeToCamel(field.name),
                    type: .nested(package: resolvedPackage, typeName: type)
                )
            case .array, .sequence, .boundedString:
                preconditionFailure(
                    "IDLFieldType.array/sequence/boundedString not yet implemented in IRBuilder "
                        + "(Phase 3 Task 7); field '\(field.name)' in \(idl.package)/\(idl.typeName)"
                )
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
