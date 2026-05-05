public enum ROS2ParameterError: Error, Sendable, Equatable {
    case alreadyDeclared(name: String)
    case notDeclared(name: String)
    case invalidType(
        name: String, expected: ROS2ParameterType, got: ROS2ParameterType)
    case invalidValue(name: String, reason: String)
    case immutableTypeChange(name: String)
    case outOfRange(name: String, reason: String)
    case readOnly(name: String)
}
