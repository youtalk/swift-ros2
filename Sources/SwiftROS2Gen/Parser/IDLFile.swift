/// The parsed representation of a single `.msg` file.
public struct IDLFile: Equatable, Sendable {
    public let package: String
    public let typeName: String
    public let fields: [IDLField]
    public let constants: [IDLConstant]

    public init(
        package: String,
        typeName: String,
        fields: [IDLField],
        constants: [IDLConstant] = []
    ) {
        self.package = package
        self.typeName = typeName
        self.fields = fields
        self.constants = constants
    }
}

/// A single field declaration parsed from a `.msg` file.
public struct IDLField: Equatable, Sendable {
    public let name: String
    public let type: IDLFieldType
    /// Raw text of the trailing default expression, exactly as written in the
    /// .msg file (no trimming beyond surrounding whitespace). Parsed into a
    /// typed `DefaultValue` by `IRBuilder`. `nil` when the field has no default.
    public let defaultExpression: String?
    public let sourceLine: Int

    public init(
        name: String,
        type: IDLFieldType,
        defaultExpression: String? = nil,
        sourceLine: Int
    ) {
        self.name = name
        self.type = type
        self.defaultExpression = defaultExpression
        self.sourceLine = sourceLine
    }
}

/// A constant declaration parsed from a `.msg` file (e.g. `int8 STATUS_UNKNOWN=0`).
public struct IDLConstant: Equatable, Sendable {
    public let name: String
    public let type: PrimitiveType
    /// Raw value token exactly as written in the .msg source (no trimming
    /// beyond surrounding whitespace). `IRBuilder` parses this into a typed
    /// constant value.
    public let value: String
    public let sourceLine: Int

    public init(name: String, type: PrimitiveType, value: String, sourceLine: Int) {
        self.name = name
        self.type = type
        self.value = value
        self.sourceLine = sourceLine
    }
}

/// The parsed representation of a single `.srv` file (a request / response pair).
public struct IDLService: Equatable, Sendable {
    public let package: String
    public let typeName: String
    public let request: IDLFile
    public let response: IDLFile

    public init(package: String, typeName: String, request: IDLFile, response: IDLFile) {
        self.package = package
        self.typeName = typeName
        self.request = request
        self.response = response
    }
}

/// The type of a field as parsed from the `.msg` source.
public indirect enum IDLFieldType: Equatable, Sendable {
    case primitive(PrimitiveType)
    /// A reference to another message type. `package == nil` means "same package as the
    /// declaring message" — the IR builder resolves it. `package != nil` is a fully
    /// qualified reference such as `std_msgs/Header`.
    case nested(package: String?, typeName: String)

    /// Fixed-size array: `<elem>[N]`. Element is recursively any IDLFieldType
    /// except another array or sequence (rosidl forbids nesting array shapes).
    case array(element: IDLFieldType, length: Int)

    /// Sequence: `<elem>[]` (unbounded, `upperBound == nil`) or
    /// `<elem>[<=N]` (bounded, `upperBound == N`).
    case sequence(element: IDLFieldType, upperBound: Int?)

    /// Bounded string / wstring: `string<=N` / `wstring<=N`.
    /// Modeled as a separate case (instead of carrying a bound on the
    /// `string` primitive) because the bound participates in the RIHS01
    /// type_id selection — keeping it lifted matches the rosidl JSON shape
    /// 1:1 and makes the emitter / hasher simpler.
    case boundedString(isWide: Bool, upperBound: Int)
}
