import Crypto
import Foundation

/// Computes the RIHS01 type-hash for a ROS 2 message IR.
///
/// The algorithm mirrors `rosidl_generator_type_description.calculate_type_hash`:
/// 1. Build a `TypeDescription` dictionary in the canonical key order.
/// 2. Serialize it with `json.dumps(separators=(", ", ": "), sort_keys=False)`.
/// 3. SHA-256 the UTF-8 bytes and prepend `"RIHS01_"`.
///
/// Phase 1 supports primitive-only messages. The sentinel field
/// `structure_needs_at_least_one_member` (UINT8, type_id 3) is injected for
/// empty message definitions, mirroring what rosidl emits for `std_msgs/msg/Empty`.
///
/// Reference JSON files extracted from `osrf/ros:jazzy-desktop`:
///   `/opt/ros/jazzy/share/std_msgs/msg/Empty.json`
///   `/opt/ros/jazzy/share/std_msgs/msg/Bool.json`
///   etc.
public enum RIHS01 {

    // MARK: - Public API

    public static func hash(_ ir: MessageIR) -> String {
        let payload = canonicalBytes(ir)
        let digest = SHA256.hash(data: payload)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "RIHS01_\(hex)"
    }

    // MARK: - Canonical serialisation (internal, exposed for debugging)

    /// Builds the exact UTF-8 bytes that go into SHA-256.
    ///
    /// The format is a JSON object with this schema (key order preserved):
    ///
    /// ```json
    /// {
    ///   "type_description": {
    ///     "type_name": "<pkg>/msg/<Name>",
    ///     "fields": [
    ///       {
    ///         "name": "<field_name>",
    ///         "type": {
    ///           "type_id": <int>,
    ///           "capacity": 0,
    ///           "string_capacity": 0,
    ///           "nested_type_name": ""
    ///         }
    ///       }
    ///     ]
    ///   },
    ///   "referenced_type_descriptions": []
    /// }
    /// ```
    ///
    /// Separators: `, ` between items, `: ` between key and value (not compact,
    /// not indented — this is the exact `json.dumps` default-separator behaviour
    /// that Python's libyaml-compatible serializer uses).
    static func canonicalBytes(_ ir: MessageIR) -> Data {
        let fields = canonicalFields(ir)
        let json = buildJSON(typeName: ir.rosTypeName, fields: fields)
        // Force-unwrap: all inputs are ASCII-safe (pkg names, field names,
        // integer literals, empty string) — encoding to UTF-8 cannot fail.
        return json.data(using: .utf8)!
    }

    // MARK: - Private helpers

    /// Returns the list of field dictionaries for hashing.
    ///
    /// ROS 2 / rosidl injects a sentinel field for structurally-empty messages
    /// (those with zero user-defined fields) to satisfy the IDL requirement that
    /// every struct has at least one member.
    private static func canonicalFields(_ ir: MessageIR) -> [[String: Any]] {
        if ir.fields.isEmpty {
            // Sentinel field: `uint8 structure_needs_at_least_one_member`
            return [fieldDict(name: "structure_needs_at_least_one_member", typeID: FieldTypeID.uint8)]
        }
        return ir.fields.map { field in
            let typeID = FieldTypeID.forPrimitive(field.type)
            return fieldDict(name: field.ros2Name, typeID: typeID)
        }
    }

    /// Constructs one field entry (without `default_value` — it is stripped
    /// before hashing in the upstream Python implementation).
    private static func fieldDict(name: String, typeID: Int) -> [String: Any] {
        [
            "name": name,
            "type": [
                "type_id": typeID,
                "capacity": 0,
                "string_capacity": 0,
                "nested_type_name": "",
            ] as [String: Any],
        ]
    }

    /// Serialises the canonical structure to the exact JSON string that the
    /// Python `json.dumps(..., separators=(", ", ": "), sort_keys=False)`
    /// call produces, then returns it as a `String`.
    ///
    /// We hand-roll the serializer because `JSONSerialization` sorts keys
    /// alphabetically (different from insertion order) and uses compact
    /// separators (`,` and `:` without spaces), neither of which matches
    /// the upstream format.
    private static func buildJSON(typeName: String, fields: [[String: Any]]) -> String {
        let fieldsJSON = fields.map { f -> String in
            let name = f["name"] as! String
            let typeDict = f["type"] as! [String: Any]
            let typeID = typeDict["type_id"] as! Int
            let capacity = typeDict["capacity"] as! Int
            let stringCapacity = typeDict["string_capacity"] as! Int
            let nestedTypeName = typeDict["nested_type_name"] as! String
            let typeJSON =
                """
                {"type_id": \(typeID), "capacity": \(capacity), \
                "string_capacity": \(stringCapacity), "nested_type_name": "\(nestedTypeName)"}
                """
            return """
                {"name": "\(name)", "type": \(typeJSON)}
                """
        }
        let fieldsStr = fieldsJSON.joined(separator: ", ")
        return """
            {"type_description": {"type_name": "\(typeName)", "fields": [\(fieldsStr)]}, \
            "referenced_type_descriptions": []}
            """
    }
}

// MARK: - Field type IDs

/// Maps `FieldType` / `PrimitiveType` values to the integer `type_id` constants
/// defined by `type_description_interfaces/msg/FieldType.msg` and exposed by
/// `rosidl_generator_type_description.FIELD_TYPE_NAME_TO_ID`.
private enum FieldTypeID {
    static let uint8 = 3  // FIELD_TYPE_UINT8 — used for the Empty sentinel field

    static func forPrimitive(_ fieldType: FieldType) -> Int {
        guard case .primitive(let prim) = fieldType else {
            // Phase 1 only handles primitives; nested types are not yet supported.
            preconditionFailure("RIHS01: non-primitive FieldType not supported in Phase 1")
        }
        return forPrimitive(prim)
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func forPrimitive(_ prim: PrimitiveType) -> Int {
        switch prim {
        case .int8: return 2  // FIELD_TYPE_INT8
        case .uint8: return 3  // FIELD_TYPE_UINT8
        case .int16: return 4  // FIELD_TYPE_INT16
        case .uint16: return 5  // FIELD_TYPE_UINT16
        case .int32: return 6  // FIELD_TYPE_INT32
        case .uint32: return 7  // FIELD_TYPE_UINT32
        case .int64: return 8  // FIELD_TYPE_INT64
        case .uint64: return 9  // FIELD_TYPE_UINT64
        case .float32: return 10  // FIELD_TYPE_FLOAT
        case .float64: return 11  // FIELD_TYPE_DOUBLE
        case .char: return 13  // FIELD_TYPE_CHAR
        case .bool: return 15  // FIELD_TYPE_BOOLEAN
        case .byte: return 16  // FIELD_TYPE_BYTE
        case .string: return 17  // FIELD_TYPE_STRING
        case .wstring: return 18  // FIELD_TYPE_WSTRING
        }
    }
}
