public struct ROS2Parameter: Sendable, Equatable {
    public let name: String
    public let value: ROS2ParameterValue

    public init(name: String, value: ROS2ParameterValue) {
        self.name = name
        self.value = value
    }
}
