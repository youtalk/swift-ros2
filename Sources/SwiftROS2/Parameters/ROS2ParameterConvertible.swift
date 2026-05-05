public protocol ROS2ParameterConvertible {
    init(parameterValue: ROS2ParameterValue) throws
    var parameterValue: ROS2ParameterValue { get }
    static var parameterType: ROS2ParameterType { get }
}

extension ROS2ParameterValue {
    public var parameterType: ROS2ParameterType {
        switch self {
        case .notSet: return .notSet
        case .bool: return .bool
        case .integer: return .integer
        case .double: return .double
        case .string: return .string
        case .byteArray: return .byteArray
        case .boolArray: return .boolArray
        case .integerArray: return .integerArray
        case .doubleArray: return .doubleArray
        case .stringArray: return .stringArray
        }
    }
}

private func mismatch(
    _ value: ROS2ParameterValue,
    expected: ROS2ParameterType
) -> ROS2ParameterError {
    .invalidType(name: "", expected: expected, got: value.parameterType)
}

extension Bool: ROS2ParameterConvertible {
    public static var parameterType: ROS2ParameterType { .bool }
    public init(parameterValue: ROS2ParameterValue) throws {
        guard case .bool(let v) = parameterValue else {
            throw mismatch(parameterValue, expected: .bool)
        }
        self = v
    }
    public var parameterValue: ROS2ParameterValue { .bool(self) }
}

extension Int64: ROS2ParameterConvertible {
    public static var parameterType: ROS2ParameterType { .integer }
    public init(parameterValue: ROS2ParameterValue) throws {
        guard case .integer(let v) = parameterValue else {
            throw mismatch(parameterValue, expected: .integer)
        }
        self = v
    }
    public var parameterValue: ROS2ParameterValue { .integer(self) }
}

extension Int: ROS2ParameterConvertible {
    public static var parameterType: ROS2ParameterType { .integer }
    public init(parameterValue: ROS2ParameterValue) throws {
        guard case .integer(let v) = parameterValue else {
            throw mismatch(parameterValue, expected: .integer)
        }
        self = Int(v)
    }
    public var parameterValue: ROS2ParameterValue { .integer(Int64(self)) }
}

extension Double: ROS2ParameterConvertible {
    public static var parameterType: ROS2ParameterType { .double }
    public init(parameterValue: ROS2ParameterValue) throws {
        guard case .double(let v) = parameterValue else {
            throw mismatch(parameterValue, expected: .double)
        }
        self = v
    }
    public var parameterValue: ROS2ParameterValue { .double(self) }
}

extension String: ROS2ParameterConvertible {
    public static var parameterType: ROS2ParameterType { .string }
    public init(parameterValue: ROS2ParameterValue) throws {
        guard case .string(let v) = parameterValue else {
            throw mismatch(parameterValue, expected: .string)
        }
        self = v
    }
    public var parameterValue: ROS2ParameterValue { .string(self) }
}

extension Array: ROS2ParameterConvertible where Element == UInt8 {
    public static var parameterType: ROS2ParameterType { .byteArray }
    public init(parameterValue: ROS2ParameterValue) throws {
        guard case .byteArray(let v) = parameterValue else {
            throw mismatch(parameterValue, expected: .byteArray)
        }
        self = v
    }
    public var parameterValue: ROS2ParameterValue { .byteArray(self) }
}

// The four below are NOT protocol conformances — Swift forbids multiple
// conditional conformances of Array to the same protocol. They expose the
// same shape (parameterValue getter, throwing init from ROS2ParameterValue)
// so caller code reads the same.

extension Array where Element == Bool {
    public var parameterValue: ROS2ParameterValue { .boolArray(self) }
    public init(parameterValue: ROS2ParameterValue) throws {
        guard case .boolArray(let v) = parameterValue else {
            throw ROS2ParameterError.invalidType(
                name: "", expected: .boolArray, got: parameterValue.parameterType)
        }
        self = v
    }
}

extension Array where Element == Int64 {
    public var parameterValue: ROS2ParameterValue { .integerArray(self) }
    public init(parameterValue: ROS2ParameterValue) throws {
        guard case .integerArray(let v) = parameterValue else {
            throw ROS2ParameterError.invalidType(
                name: "", expected: .integerArray, got: parameterValue.parameterType)
        }
        self = v
    }
}

extension Array where Element == Double {
    public var parameterValue: ROS2ParameterValue { .doubleArray(self) }
    public init(parameterValue: ROS2ParameterValue) throws {
        guard case .doubleArray(let v) = parameterValue else {
            throw ROS2ParameterError.invalidType(
                name: "", expected: .doubleArray, got: parameterValue.parameterType)
        }
        self = v
    }
}

extension Array where Element == String {
    public var parameterValue: ROS2ParameterValue { .stringArray(self) }
    public init(parameterValue: ROS2ParameterValue) throws {
        guard case .stringArray(let v) = parameterValue else {
            throw ROS2ParameterError.invalidType(
                name: "", expected: .stringArray, got: parameterValue.parameterType)
        }
        self = v
    }
}
