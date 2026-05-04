/// Distro-neutral intermediate representation of a single ROS 2 message type.
public struct MessageIR: Equatable, Sendable {
    public let package: String  // "std_msgs"
    public let typeName: String  // "Bool"
    public let fields: [FieldIR]
    /// Hash for each distro for which the IR was built. Phase 1 fills only `.jazzy`.
    public var perDistroHashes: [String: String] = [:]

    public init(
        package: String,
        typeName: String,
        fields: [FieldIR],
        perDistroHashes: [String: String] = [:]
    ) {
        self.package = package
        self.typeName = typeName
        self.fields = fields
        self.perDistroHashes = perDistroHashes
    }

    /// "std_msgs/msg/Bool"
    public var rosTypeName: String { "\(package)/msg/\(typeName)" }
}

/// Intermediate representation of a single field in a ROS 2 message.
public struct FieldIR: Equatable, Sendable {
    public let ros2Name: String  // "linear_acceleration"
    public let swiftName: String  // "linearAcceleration"
    public let type: FieldType

    public init(ros2Name: String, swiftName: String, type: FieldType) {
        self.ros2Name = ros2Name
        self.swiftName = swiftName
        self.type = type
    }
}

/// The resolved type of a single message field (Phase 1: primitives only).
public enum FieldType: Equatable, Sendable {
    case primitive(PrimitiveType)
}
