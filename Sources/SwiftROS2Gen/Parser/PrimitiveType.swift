public enum PrimitiveType: String, Sendable, Hashable, CaseIterable {
    case bool, byte, char
    case int8, uint8
    case int16, uint16
    case int32, uint32
    case int64, uint64
    case float32, float64
    case string, wstring

    public init?(rawROS raw: String) {
        self.init(rawValue: raw)
    }

    /// Swift type name used by the emitter for an unmodified primitive field.
    public var swiftTypeName: String {
        switch self {
        case .bool: return "Bool"
        case .byte, .uint8: return "UInt8"
        case .char, .int8: return "Int8"
        case .int16: return "Int16"
        case .uint16: return "UInt16"
        case .int32: return "Int32"
        case .uint32: return "UInt32"
        case .int64: return "Int64"
        case .uint64: return "UInt64"
        case .float32: return "Float"
        case .float64: return "Double"
        case .string, .wstring: return "String"
        }
    }
}
