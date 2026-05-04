/// The parsed representation of a single `.msg` file.
public struct IDLFile: Equatable, Sendable {
    public let package: String
    public let typeName: String
    public let fields: [IDLField]

    public init(package: String, typeName: String, fields: [IDLField]) {
        self.package = package
        self.typeName = typeName
        self.fields = fields
    }
}

/// A single field declaration parsed from a `.msg` file.
public struct IDLField: Equatable, Sendable {
    public let name: String
    public let type: IDLFieldType
    public let sourceLine: Int

    public init(name: String, type: IDLFieldType, sourceLine: Int) {
        self.name = name
        self.type = type
        self.sourceLine = sourceLine
    }
}

/// The type of a field as parsed from the `.msg` source.
public enum IDLFieldType: Equatable, Sendable {
    case primitive(PrimitiveType)
    /// A reference to another message type. `package == nil` means "same package as the
    /// declaring message" — the IR builder resolves it. `package != nil` is a fully
    /// qualified reference such as `std_msgs/Header`.
    case nested(package: String?, typeName: String)
    // Array variants intentionally omitted in Phase 2.
}
