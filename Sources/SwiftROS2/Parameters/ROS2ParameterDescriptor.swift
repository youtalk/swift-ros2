/// Descriptor metadata that travels with a declared parameter.
///
/// Mirrors `rcl_interfaces/msg/ParameterDescriptor` but uses Swift-idiomatic
/// `ClosedRange` plus optional `step` instead of the wire's bounded ≤ 1
/// `[FloatingPointRange]` / `[IntegerRange]` sequences. The `step` fields
/// are advisory — they cross the wire for tools to consume but are not
/// enforced by `ParameterStore` (matching rclcpp behavior).
public struct ROS2ParameterDescriptor: Sendable, Equatable {
    public var name: String
    public var type: ROS2ParameterType
    public var description: String
    public var additionalConstraints: String
    public var readOnly: Bool
    public var dynamicTyping: Bool
    public var floatingPointRange: ClosedRange<Double>?
    public var floatingPointStep: Double?
    public var integerRange: ClosedRange<Int64>?
    public var integerStep: Int64?

    public init(
        name: String = "",
        type: ROS2ParameterType = .notSet,
        description: String = "",
        additionalConstraints: String = "",
        readOnly: Bool = false,
        dynamicTyping: Bool = false,
        floatingPointRange: ClosedRange<Double>? = nil,
        floatingPointStep: Double? = nil,
        integerRange: ClosedRange<Int64>? = nil,
        integerStep: Int64? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.additionalConstraints = additionalConstraints
        self.readOnly = readOnly
        self.dynamicTyping = dynamicTyping
        self.floatingPointRange = floatingPointRange
        self.floatingPointStep = floatingPointStep
        self.integerRange = integerRange
        self.integerStep = integerStep
    }
}
