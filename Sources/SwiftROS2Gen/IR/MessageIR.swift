/// Indicates which ROS 2 IDL family a `MessageIR` came from. Phase 3 introduces
/// `.srv` to distinguish the synthesized request / response halves of a service
/// — they get rendered into the canonical `<pkg>/srv/<Type>_Request|Response`
/// type name, both in the RIHS01 hash input and in the emitted `typeInfo`.
public enum MessageKind: String, Equatable, Sendable {
    case msg
    case srv
}

/// Distro-neutral intermediate representation of a single ROS 2 message type.
public struct MessageIR: Equatable, Sendable {
    public let package: String  // "std_msgs"
    public let typeName: String  // "Bool"
    public let kind: MessageKind
    public let fields: [FieldIR]
    public let constants: [ConstantIR]
    /// Hash for each distro for which the IR was built. Phase 1 fills only `.jazzy`.
    public var perDistroHashes: [String: String] = [:]

    public init(
        package: String,
        typeName: String,
        kind: MessageKind = .msg,
        fields: [FieldIR],
        constants: [ConstantIR] = [],
        perDistroHashes: [String: String] = [:]
    ) {
        self.package = package
        self.typeName = typeName
        self.kind = kind
        self.fields = fields
        self.constants = constants
        self.perDistroHashes = perDistroHashes
    }

    /// "std_msgs/msg/Bool" or "action_msgs/srv/CancelGoal_Request" depending on `kind`.
    public var rosTypeName: String { "\(package)/\(kind.rawValue)/\(typeName)" }
}

/// Intermediate representation of a single field in a ROS 2 message.
public struct FieldIR: Equatable, Sendable {
    public let ros2Name: String  // "linear_acceleration"
    public let swiftName: String  // "linearAcceleration"
    public let type: FieldType
    public let defaultValue: DefaultValue?

    public init(
        ros2Name: String,
        swiftName: String,
        type: FieldType,
        defaultValue: DefaultValue? = nil
    ) {
        self.ros2Name = ros2Name
        self.swiftName = swiftName
        self.type = type
        self.defaultValue = defaultValue
    }
}

/// The resolved type of a single message field.
public indirect enum FieldType: Equatable, Sendable {
    case primitive(PrimitiveType)
    /// A reference to another message IR. `package` is always fully resolved
    /// (no implicit "same package" — IRBuilder rewrites those).
    case nested(package: String, typeName: String)
    /// Fixed-size array `<elem>[N]`.
    case array(element: FieldType, length: Int)
    /// Sequence `<elem>[]` (unbounded, `upperBound == nil`) or `<elem>[<=N]`.
    case sequence(element: FieldType, upperBound: Int?)
    /// Bounded string / wstring `string<=N` / `wstring<=N`.
    case boundedString(isWide: Bool, upperBound: Int)
}

extension FieldType {
    /// Canonical ROS type name (`<pkg>/msg/<Type>`) for nested references.
    /// `nil` for primitive / array / sequence / boundedString types.
    public var rosTypeName: String? {
        switch self {
        case .primitive: return nil
        case .nested(let pkg, let type): return "\(pkg)/msg/\(type)"
        case .array, .sequence, .boundedString: return nil
        }
    }
}

/// Typed representation of a field default. Emitted as a Swift literal in the
/// generated `init(...)` parameter default.
public enum DefaultValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int64)  // covers int8..int64; range-checked at parse time
    case uint(UInt64)  // covers uint8..uint64
    case float(Double)  // covers float32 + float64
    case string(String)  // raw Swift-literal-ready string (no surrounding quotes)
    case array([DefaultValue])
    case empty  // explicit "" / [] for sequences/strings without a value
}

/// A typed, validated constant declaration carried on a ``MessageIR``.
public struct ConstantIR: Equatable, Sendable {
    public let ros2Name: String
    public let swiftName: String
    public let type: PrimitiveType
    public let value: DefaultValue

    public init(ros2Name: String, swiftName: String, type: PrimitiveType, value: DefaultValue) {
        self.ros2Name = ros2Name
        self.swiftName = swiftName
        self.type = type
        self.value = value
    }
}
