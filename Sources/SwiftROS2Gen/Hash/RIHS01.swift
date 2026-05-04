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
/// Reference JSON files extracted from `osrf/ros:jazzy-desktop`:
///   `/opt/ros/jazzy/share/std_msgs/msg/Empty.json`
///   `/opt/ros/jazzy/share/builtin_interfaces/msg/Time.json`
///   `/opt/ros/jazzy/share/geometry_msgs/msg/Pose.json`
///   `/opt/ros/jazzy/share/unique_identifier_msgs/msg/UUID.json`
///   `/opt/ros/jazzy/share/action_msgs/msg/GoalStatusArray.json`
///
/// Phase coverage:
///   - Phase 1: primitive-only messages.
///   - Phase 2: nested message references via `referenced_type_descriptions`.
///   - Phase 3 (this file): fixed-size arrays, bounded/unbounded sequences,
///     bounded strings. ``ConstantIR`` and ``FieldIR.defaultValue`` are
///     intentionally **not** consulted — upstream `calculate_type_hash` deletes
///     `default_value` from every field before SHA-256, and constants never
///     appear in `serialize_individual_type_description` at all.
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

    /// Compute the RIHS01 hash for a single distro view of a multi-distro IR.
    ///
    /// Filters fields to those whose `availability` includes `distro`, then
    /// runs the regular hashing path. Pass `registry` when the IR has nested
    /// references; for primitive-only IRs the empty-registry overload works.
    public static func hash(
        _ ir: MessageIR,
        for distro: String,
        registry: [String: MessageIR] = [:]
    ) -> String {
        let scopedFields = ir.fields.filter { $0.availability.includes(distro) }
        let scoped = MessageIR(
            package: ir.package,
            typeName: ir.typeName,
            kind: ir.kind,
            fields: scopedFields,
            constants: ir.constants
        )
        return hash(scoped, registry: registry)
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
    ///
    /// Note: ``FieldIR.defaultValue`` is intentionally not consulted. Upstream
    /// `calculate_type_hash` does:
    ///   ```python
    ///   for field in hashable_dict['type_description']['fields']:
    ///       del field['default_value']
    ///   ```
    /// before SHA-256, so the byte stream sees no `default_value` keys at all.
    /// Constants are likewise absent from `serialize_individual_type_description`
    /// — ``MessageIR.constants`` is intentionally not consulted here either.
    private static func canonicalFields(_ ir: MessageIR) -> [FieldEntry] {
        if ir.fields.isEmpty {
            // Sentinel field: `uint8 structure_needs_at_least_one_member`
            return [
                FieldEntry(
                    name: "structure_needs_at_least_one_member",
                    typeID: FieldTypeID.uint8,
                    capacity: 0,
                    stringCapacity: 0,
                    nestedTypeName: "")
            ]
        }
        return ir.fields.map { field in
            let resolved = resolve(field.type)
            return FieldEntry(
                name: field.ros2Name,
                typeID: resolved.typeID,
                capacity: resolved.capacity,
                stringCapacity: resolved.stringCapacity,
                nestedTypeName: resolved.nestedTypeName)
        }
    }

    /// Decompose a ``FieldType`` into the four canonical slots that rosidl
    /// emits per field: `(type_id, capacity, string_capacity, nested_type_name)`.
    ///
    /// The offsets follow `type_description_interfaces/msg/FieldType.msg`:
    ///   - Bare type: `value_id` (1..22).
    ///   - Fixed array `T[N]`: `value_id + 48`, `capacity = N`.
    ///   - Bounded sequence `T[<=N]`: `value_id + 96`, `capacity = N`.
    ///   - Unbounded sequence `T[]`: `value_id + 144`, `capacity = 0`.
    /// `nested_type_name` is the inner element type's full name when the
    /// element is `.nested(_:_:)`, even when wrapped in array/sequence.
    /// `string_capacity` is the bound for `string<=N` / `wstring<=N`,
    /// including arrays/sequences of bounded strings.
    private static func resolve(_ ft: FieldType) -> ResolvedFieldType {
        switch ft {
        case .primitive(let prim):
            return ResolvedFieldType(
                typeID: FieldTypeID.forPrimitive(prim),
                capacity: 0,
                stringCapacity: 0,
                nestedTypeName: "")
        case .nested(let pkg, let type):
            return ResolvedFieldType(
                typeID: FieldTypeID.nestedType,
                capacity: 0,
                stringCapacity: 0,
                nestedTypeName: "\(pkg)/msg/\(type)")
        case .array(let element, let length):
            let inner = resolve(element)
            return ResolvedFieldType(
                typeID: inner.typeID + FieldTypeID.arrayOffset,
                capacity: length,
                stringCapacity: inner.stringCapacity,
                nestedTypeName: inner.nestedTypeName)
        case .sequence(let element, let upper):
            let inner = resolve(element)
            if let upper = upper {
                return ResolvedFieldType(
                    typeID: inner.typeID + FieldTypeID.boundedSequenceOffset,
                    capacity: upper,
                    stringCapacity: inner.stringCapacity,
                    nestedTypeName: inner.nestedTypeName)
            } else {
                return ResolvedFieldType(
                    typeID: inner.typeID + FieldTypeID.unboundedSequenceOffset,
                    capacity: 0,
                    stringCapacity: inner.stringCapacity,
                    nestedTypeName: inner.nestedTypeName)
            }
        case .boundedString(let isWide, let upperBound):
            return ResolvedFieldType(
                typeID: isWide ? FieldTypeID.boundedWString : FieldTypeID.boundedString,
                capacity: 0,
                stringCapacity: upperBound,
                nestedTypeName: "")
        }
    }

    /// Walk `field.type` to find the nested element it ultimately points at,
    /// for BFS traversal of `referenced_type_descriptions`. Returns `nil` for
    /// purely primitive / bounded-string fields.
    private static func nestedTarget(of ft: FieldType) -> (pkg: String, type: String)? {
        switch ft {
        case .primitive, .boundedString:
            return nil
        case .nested(let pkg, let type):
            return (pkg, type)
        case .array(let element, _):
            return nestedTarget(of: element)
        case .sequence(let element, _):
            return nestedTarget(of: element)
        }
    }

    /// BFS the registry from the root, collecting every nested IR exactly once.
    /// The result is sorted by `type_name` (alphabetical) — this matches what
    /// upstream rosidl emits via `sorted(output_references)`.
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
                guard let target = nestedTarget(of: field.type) else { continue }
                let key = "\(target.pkg)/msg/\(target.type)"
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
            "{\"name\": \"\(f.name)\", \"type\": {\"type_id\": \(f.typeID), "
                + "\"capacity\": \(f.capacity), \"string_capacity\": \(f.stringCapacity), "
                + "\"nested_type_name\": \"\(f.nestedTypeName)\"}}"
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
    let capacity: Int
    let stringCapacity: Int
    let nestedTypeName: String
}

/// Result of decomposing a ``FieldType`` into the four canonical slots.
private struct ResolvedFieldType {
    let typeID: Int
    let capacity: Int
    let stringCapacity: Int
    let nestedTypeName: String
}

// MARK: - Field type IDs

/// Maps `FieldType` / `PrimitiveType` values to the integer `type_id` constants
/// defined by `type_description_interfaces/msg/FieldType.msg` and exposed by
/// `rosidl_generator_type_description.FIELD_TYPE_NAME_TO_ID`.
///
/// Confirmed against `osrf/ros:jazzy-desktop`:
///   - Nested type fields use `type_id == 1` (NESTED_TYPE).
///   - Fixed arrays add 48 (e.g. `uint8[16]` => 51, `T[N]` of nested => 49).
///   - Bounded sequences add 96 (`uint8[<=N]` => 99).
///   - Unbounded sequences add 144 (`GoalStatus[]` => 145).
private enum FieldTypeID {
    static let nestedType = 1  // NESTED_TYPE — `<pkg>/msg/<Type>` reference
    static let uint8 = 3  // FIELD_TYPE_UINT8 — used for the Empty sentinel field
    static let boundedString = 21  // FIELD_TYPE_BOUNDED_STRING
    static let boundedWString = 22  // FIELD_TYPE_BOUNDED_WSTRING

    static let arrayOffset = 48  // adds to base id => fixed array
    static let boundedSequenceOffset = 96  // adds to base id => bounded sequence
    static let unboundedSequenceOffset = 144  // adds to base id => unbounded sequence

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
