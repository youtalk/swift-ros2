/// A single flat C parameter derived from a ROS message field. The native-RCL
/// marshaller never lets a Swift target touch a `CRos2Jazzy` struct, so every
/// message value is destructured into flat C arguments: nested single messages
/// flatten into scalar args, sequences pass as `(ptr, count)`, and a
/// sequence-of-structs passes as parallel arrays (struct-of-arrays). The
/// flattener encodes exactly that destructuring; the C emitter consumes it to
/// rebuild the rosidl struct.
public struct FlatParam: Equatable {
    /// How the C side reconstructs this argument into the rosidl struct.
    public enum Kind: Equatable {
        /// A plain by-value scalar (`double`, `int32_t`, …).
        case scalar
        /// A heap-allocated `rosidl_runtime_c__String` filled via `__assign`.
        case heapString
        /// A fixed-size array `<elem>[N]` `memcpy`'d into the struct member.
        case fixedArray(elementC: String, length: Int)
        /// A primitive sequence `<elem>[]` passed as `(data, count)`.
        case scalarSequence(elementC: String)
        /// A sequence of structs `<Struct>[]` passed as parallel member arrays
        /// (struct-of-arrays). `members` lists the per-element member params.
        case structSequence(elementType: String, members: [FlatParam])
    }

    /// Flat C identifier for this argument (e.g. `header_frame_id`).
    public let paramName: String
    public let kind: Kind
    /// C scalar / element type (`double`, `uint32_t`, `char`, …).
    public let cType: String
    /// Full C parameter declaration as it appears in the function signature.
    public let cParamDecl: String
    /// Path to the rosidl struct member this argument fills. Absolute
    /// (`msg->header.frame_id`) for top-level params; relative (`.name`) for
    /// struct-sequence members (the emitter prepends `msg->...data[i]`).
    public let cStructPath: String
    /// Swift expression (relative to the message value) that produces this
    /// argument's value (e.g. `header.frameId`).
    public let swiftValuePath: String

    public init(
        paramName: String,
        kind: Kind,
        cType: String,
        cParamDecl: String,
        cStructPath: String,
        swiftValuePath: String
    ) {
        self.paramName = paramName
        self.kind = kind
        self.cType = cType
        self.cParamDecl = cParamDecl
        self.cStructPath = cStructPath
        self.swiftValuePath = swiftValuePath
    }
}

/// Walks a ``MessageIR`` and produces the flat C-parameter list the native-RCL
/// marshaller emits. Pure (no I/O); recurses into nested IRs via `registry`.
public enum MarshalFlattener {
    /// C scalar / element type for a ROS primitive. `string` / `wstring` map to
    /// `char` (the element type of a C string).
    public static func cPrimitive(_ p: PrimitiveType) -> String {
        switch p {
        case .bool: return "bool"
        case .byte, .uint8: return "uint8_t"
        case .char, .int8: return "int8_t"
        case .int16: return "int16_t"
        case .uint16: return "uint16_t"
        case .int32: return "int32_t"
        case .uint32: return "uint32_t"
        case .int64: return "int64_t"
        case .uint64: return "uint64_t"
        case .float32: return "float"
        case .float64: return "double"
        case .string, .wstring: return "char"
        }
    }

    /// Callers must pass a `registry` already validated by
    /// `Pipeline.buildMessageRegistry`; unresolved nested refs trap via
    /// `preconditionFailure`.
    public static func flatten(_ ir: MessageIR, registry: [String: MessageIR]) -> [FlatParam] {
        var out: [FlatParam] = []
        for field in ir.fields {
            appendField(
                field,
                registry: registry,
                cPath: "msg->\(field.ros2Name)",
                swiftPath: field.swiftName,
                prefix: field.ros2Name,
                into: &out
            )
        }
        return out
    }

    private static func appendField(
        _ field: FieldIR,
        registry: [String: MessageIR],
        cPath: String,
        swiftPath: String,
        prefix: String,
        into out: inout [FlatParam]
    ) {
        switch field.type {
        case .primitive(.string), .primitive(.wstring), .boundedString:
            out.append(
                FlatParam(
                    paramName: prefix,
                    kind: .heapString,
                    cType: "char",
                    cParamDecl: "const char *\(prefix)",
                    cStructPath: cPath,
                    swiftValuePath: swiftPath
                ))

        case .primitive(let p):
            let cType = cPrimitive(p)
            out.append(
                FlatParam(
                    paramName: prefix,
                    kind: .scalar,
                    cType: cType,
                    cParamDecl: "\(cType) \(prefix)",
                    cStructPath: cPath,
                    swiftValuePath: swiftPath
                ))

        case .array(let element, let length):
            guard case .primitive(let p) = element else {
                preconditionFailure(
                    "MarshalFlattener: fixed array of non-primitive element is unsupported (\(prefix))")
            }
            let cType = cPrimitive(p)
            out.append(
                FlatParam(
                    paramName: prefix,
                    kind: .fixedArray(elementC: cType, length: length),
                    cType: cType,
                    cParamDecl: "const \(cType) *\(prefix)",
                    cStructPath: cPath,
                    swiftValuePath: swiftPath
                ))

        case .nested(let pkg, let typeName):
            guard let nestedIR = registry["\(pkg)/msg/\(typeName)"] else {
                preconditionFailure(
                    "MarshalFlattener: unresolved nested type \(pkg)/msg/\(typeName)")
            }
            for nf in nestedIR.fields {
                appendField(
                    nf,
                    registry: registry,
                    cPath: "\(cPath).\(nf.ros2Name)",
                    swiftPath: "\(swiftPath).\(nf.swiftName)",
                    prefix: "\(prefix)_\(nf.ros2Name)",
                    into: &out
                )
            }

        case .sequence(let element, _):
            switch element {
            case .primitive(let p):
                let cType = cPrimitive(p)
                out.append(
                    FlatParam(
                        paramName: prefix,
                        kind: .scalarSequence(elementC: cType),
                        cType: cType,
                        cParamDecl: "const \(cType) *\(prefix)_data, size_t \(prefix)_count",
                        cStructPath: cPath,
                        swiftValuePath: swiftPath
                    ))
            case .nested(let pkg, let typeName):
                guard let elementIR = registry["\(pkg)/msg/\(typeName)"] else {
                    preconditionFailure(
                        "MarshalFlattener: unresolved nested element type \(pkg)/msg/\(typeName)")
                }
                let elementType = "\(pkg)__msg__\(typeName)"
                let members = elementIR.fields.map { memberParam(for: $0, prefix: prefix) }
                let memberDecls = members.map(\.cParamDecl).joined(separator: ", ")
                out.append(
                    FlatParam(
                        paramName: prefix,
                        kind: .structSequence(elementType: elementType, members: members),
                        cType: elementType,
                        cParamDecl: "\(memberDecls), size_t \(prefix)_len",
                        cStructPath: cPath,
                        swiftValuePath: swiftPath
                    ))
            default:
                preconditionFailure(
                    "MarshalFlattener: sequence of \(element) is unsupported (\(prefix))")
            }
        }
    }

    /// Classifies one struct-sequence element member into a ``FlatParam``,
    /// sharing the same string-vs-scalar decision as the top-level
    /// `appendField`. A string member becomes a `const char *const *<prefix>_<name>`
    /// heapString (parallel array of strings); a primitive becomes a
    /// `const <c> *<prefix>_<name>` scalar (parallel array of scalars). Anything
    /// else traps — only scalar / string members are supported.
    private static func memberParam(for elementField: FieldIR, prefix: String) -> FlatParam {
        let memberParam = "\(prefix)_\(elementField.ros2Name)"
        switch elementField.type {
        case .primitive(.string), .primitive(.wstring), .boundedString:
            return FlatParam(
                paramName: memberParam,
                kind: .heapString,
                cType: "char",
                cParamDecl: "const char *const *\(memberParam)",
                cStructPath: ".\(elementField.ros2Name)",
                swiftValuePath: elementField.swiftName
            )
        case .primitive(let p):
            let cType = cPrimitive(p)
            return FlatParam(
                paramName: memberParam,
                kind: .scalar,
                cType: cType,
                cParamDecl: "const \(cType) *\(memberParam)",
                cStructPath: ".\(elementField.ros2Name)",
                swiftValuePath: elementField.swiftName
            )
        default:
            preconditionFailure(
                "MarshalFlattener: struct-sequence member \(elementField.ros2Name) has unsupported "
                    + "type (only scalar / string members are supported)")
        }
    }
}
