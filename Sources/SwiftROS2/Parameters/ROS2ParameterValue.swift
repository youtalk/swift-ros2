// The wire-level rcl_interfaces.ParameterValue uses a uint8 discriminator
// + nine fixed-name typed slots; we hide that in WireBridge.swift and
// give callers a Swift-shaped sum type.

/// Type-erased value of a ROS 2 parameter.
///
/// Mirrors the nine typed slots of `rcl_interfaces/msg/ParameterValue` plus
/// a `notSet` case for absent or default-constructed values.
public enum ROS2ParameterValue: Sendable, Equatable {
    case notSet
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case byteArray([UInt8])
    case boolArray([Bool])
    case integerArray([Int64])
    case doubleArray([Double])
    case stringArray([String])
}
