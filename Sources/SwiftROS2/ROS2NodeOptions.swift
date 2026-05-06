// Per-node creation knobs. Currently single-purpose (parameter-services
// opt-out) — future phases may add publisher-default QoS / event toggles
// alongside, hence the dedicated struct rather than a bare Bool argument
// on createNode.

/// Configuration toggles applied at `ROS2Node` construction time.
public struct ROS2NodeOptions: Sendable, Equatable {
    /// Whether `ROS2Context.createNode` automatically registers the six
    /// `rcl_interfaces` parameter services (`get_parameters`,
    /// `set_parameters`, `set_parameters_atomically`, `list_parameters`,
    /// `describe_parameters`, `get_parameter_types`) under
    /// `<node_fqn>/<service>`.
    ///
    /// rclcpp / rclpy register these unconditionally; we follow the same
    /// default. Embedded callers that never need `ros2 param` interop can
    /// set this to `false` to skip the six service objects.
    public var startParameterServices: Bool

    public init(startParameterServices: Bool = true) {
        self.startParameterServices = startParameterServices
    }

    /// Default options: auto-register parameter services. Equivalent to
    /// `ROS2NodeOptions()`.
    public static let `default` = ROS2NodeOptions()
}
