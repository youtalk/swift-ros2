public enum ROS2ParameterType: UInt8, Sendable, CaseIterable {
    case notSet = 0
    case bool = 1
    case integer = 2
    case double = 3
    case string = 4
    case byteArray = 5
    case boolArray = 6
    case integerArray = 7
    case doubleArray = 8
    case stringArray = 9
}
