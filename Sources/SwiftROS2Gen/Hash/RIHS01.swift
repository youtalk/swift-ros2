import Crypto
import Foundation

/// Computes the RIHS01 type-hash for a ROS 2 message IR.
///
/// The algorithm mirrors `rosidl_generator_type_description.calculate_type_hash`:
/// 1. Build a `TypeDescription` dictionary in the canonical key order, stripping
///    `default_value` from every field (root and referenced).
/// 2. Serialize it with `json.dumps(separators=(", ", ": "), sort_keys=False)`.
/// 3. SHA-256 the UTF-8 bytes and prepend `"RIHS01_"`.
///
/// Phase 1 supports primitive-only messages. Phase 2 (this file) adds support
/// for nested message references via `referenced_type_descriptions`.
///
/// Reference JSON files extracted from `osrf/ros:jazzy-desktop`:
///   `/opt/ros/jazzy/share/std_msgs/msg/Empty.json`
///   `/opt/ros/jazzy/share/builtin_interfaces/msg/Time.json`
///   `/opt/ros/jazzy/share/geometry_msgs/msg/Pose.json`
public enum RIHS01 {

    // MARK: - Public API

    /// Phase 1 shim: hash a primitive-only IR with no nested deps.
    ///
    /// Traps if `ir` contains any nested fields — the empty registry would
    /// otherwise hit `preconditionFailure` deep inside `referencedTypeDescriptions`
    /// with a message about the unresolved type. Surfacing the misuse at the call
    /// site is friendlier than burying it in the BFS.
    public static func hash(_ ir: MessageIR) -> String {
        precondition(
            !ir.fields.contains(where: {
                if case .nested = $0.type { return true } else { return false }
            }),
            "RIHS01.hash(_:) requires primitive-only IR; pass a registry for nested types")
        return hash(ir, registry: [:])
    }

    /// Hash a (possibly nested) IR. `registry` maps `"<pkg>/msg/<Type>"` to the
    /// `MessageIR` for every type the root may reference (transitively). The
    /// Pipeline (Task 9) builds the registry once per multi-package run.
    public static func hash(_ ir: MessageIR, registry: [String: MessageIR]) -> String {
        let payload = canonicalBytes(ir, registry: registry)
        let digest = SHA256.hash(data: payload)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "RIHS01_\(hex)"
    }

    // MARK: - Canonical serialisation (internal, exposed for debugging)

    /// Builds the exact UTF-8 bytes that go into SHA-256.
    static func canonicalBytes(_ ir: MessageIR, registry: [String: MessageIR]) -> Data {
        let rootFields = canonicalFields(ir)
        let referenced = referencedTypeDescriptions(rootIR: ir, registry: registry)
        let json = buildJSON(typeName: ir.rosTypeName, fields: rootFields, referenced: referenced)
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
    private static func canonicalFields(_ ir: MessageIR) -> [FieldEntry] {
        if ir.fields.isEmpty {
            // Sentinel field: `uint8 structure_needs_at_least_one_member`
            return [
                FieldEntry(
                    name: "structure_needs_at_least_one_member",
                    typeID: FieldTypeID.uint8,
                    nestedTypeName: "")
            ]
        }
        return ir.fields.map { field in
            switch field.type {
            case .primitive(let prim):
                return FieldEntry(
                    name: field.ros2Name,
                    typeID: FieldTypeID.forPrimitive(prim),
                    nestedTypeName: "")
            case .nested(let pkg, let type):
                return FieldEntry(
                    name: field.ros2Name,
                    typeID: FieldTypeID.nestedType,
                    nestedTypeName: "\(pkg)/msg/\(type)")
            case .array, .sequence, .boundedString:
                preconditionFailure(
                    "RIHS01: array/sequence/boundedString hashing not yet implemented "
                        + "(Phase 3 Task 8); field '\(field.ros2Name)' in \(ir.rosTypeName)")
            }
        }
    }

    /// BFS the registry from the root, collecting every nested IR exactly once.
    /// The result is sorted by `type_name` (alphabetical) — this matches what
    /// upstream rosidl emits.
    private static func referencedTypeDescriptions(
        rootIR: MessageIR,
        registry: [String: MessageIR]
    ) -> [(typeName: String, fields: [FieldEntry])] {
        var visited: Set<String> = []
        var queue: [MessageIR] = [rootIR]
        var collected: [MessageIR] = []
        // Index cursor instead of `queue.removeFirst()` — the latter is O(n) per
        // pop and would make the BFS O(n^2) on larger type graphs.
        var idx = 0
        while idx < queue.count {
            let current = queue[idx]
            idx += 1
            for field in current.fields {
                let pkg: String
                let type: String
                switch field.type {
                case .nested(let p, let t):
                    pkg = p
                    type = t
                case .primitive:
                    continue
                case .array, .sequence, .boundedString:
                    preconditionFailure(
                        "RIHS01: array/sequence/boundedString hashing not yet implemented "
                            + "(Phase 3 Task 8); field '\(field.ros2Name)' in \(current.rosTypeName)")
                }
                let key = "\(pkg)/msg/\(type)"
                if visited.contains(key) { continue }
                visited.insert(key)
                guard let nestedIR = registry[key] else {
                    preconditionFailure(
                        // swift-format-ignore: NeverForceUnwrap
                        "RIHS01: unresolved nested type '\(key)' — Pipeline must surface this "
                            + "as GeneratorError before reaching the hasher")
                }
                collected.append(nestedIR)
                queue.append(nestedIR)
            }
        }
        let sorted = collected.sorted { $0.rosTypeName < $1.rosTypeName }
        return sorted.map { ($0.rosTypeName, canonicalFields($0)) }
    }

    /// Serialises the canonical structure to the exact JSON string that the
    /// Python `json.dumps(..., separators=(", ", ": "), sort_keys=False)`
    /// call produces, then returns it as a `String`.
    ///
    /// We hand-roll the serializer because `JSONSerialization` sorts keys
    /// alphabetically (different from insertion order) and uses compact
    /// separators (`,` and `:` without spaces), neither of which matches
    /// the upstream format.
    private static func buildJSON(
        typeName: String,
        fields: [FieldEntry],
        referenced: [(typeName: String, fields: [FieldEntry])]
    ) -> String {
        let fieldsStr = renderFields(fields)
        let referencedStr =
            referenced.map { entry in
                "{\"type_name\": \"\(entry.typeName)\", \"fields\": [\(renderFields(entry.fields))]}"
            }
            .joined(separator: ", ")
        return
            "{\"type_description\": {\"type_name\": \"\(typeName)\", \"fields\": [\(fieldsStr)]}, "
            + "\"referenced_type_descriptions\": [\(referencedStr)]}"
    }

    private static func renderFields(_ fields: [FieldEntry]) -> String {
        fields.map { f in
            "{\"name\": \"\(f.name)\", \"type\": {\"type_id\": \(f.typeID), \"capacity\": 0, "
                + "\"string_capacity\": 0, \"nested_type_name\": \"\(f.nestedTypeName)\"}}"
        }
        .joined(separator: ", ")
    }
}

// MARK: - Field entry struct

/// One canonical field entry. Strongly typed so we don't shuffle `[String: Any]`
/// dictionaries through the serializer.
private struct FieldEntry {
    let name: String
    let typeID: Int
    let nestedTypeName: String
}

// MARK: - Field type IDs

/// Maps `FieldType` / `PrimitiveType` values to the integer `type_id` constants
/// defined by `type_description_interfaces/msg/FieldType.msg` and exposed by
/// `rosidl_generator_type_description.FIELD_TYPE_NAME_TO_ID`.
///
/// Confirmed against `osrf/ros:jazzy-desktop`:
///   - Nested type fields use `type_id == 1` (NESTED_TYPE), not 48.
///   - Primitive ids match the `FIELD_TYPE_*` constants in
///     `type_description_interfaces/msg/FieldType.msg`.
private enum FieldTypeID {
    static let nestedType = 1  // NESTED_TYPE — `<pkg>/msg/<Type>` reference
    static let uint8 = 3  // FIELD_TYPE_UINT8 — used for the Empty sentinel field

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
