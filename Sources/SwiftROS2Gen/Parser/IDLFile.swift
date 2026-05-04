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

public enum IDLFieldType: Equatable, Sendable {
    case primitive(PrimitiveType)
    // Nested + array variants intentionally omitted in Phase 1.
}
