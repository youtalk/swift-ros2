/// A name + value pair representing one ROS 2 parameter assignment.
///
/// Distinct from the wire-level `rcl_interfaces/msg/Parameter`, which uses
/// the discriminator-based `ParameterValue` struct in every typed slot.
public struct ROS2Parameter: Sendable, Equatable {
    public let name: String
    public let value: ROS2ParameterValue

    public init(name: String, value: ROS2ParameterValue) {
        self.name = name
        self.value = value
    }
}
