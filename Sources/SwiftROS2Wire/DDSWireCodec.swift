// DDSWireCodec.swift
// Wire format codec for DDS (rmw_cyclonedds) compatibility

import Foundation

/// Wire format codec for DDS transport
///
/// Handles DDS-specific topic naming and type name mangling for
/// rmw_cyclonedds_cpp compatibility.
public struct DDSWireCodec: Sendable {
    public init() {}

    /// Convert ROS topic to DDS topic name
    ///
    /// Adds "rt/" prefix: "/conduit/imu" -> "rt/conduit/imu"
    public func ddsTopic(from rosTopic: String) -> String {
        let clean = TypeNameConverter.stripLeadingSlash(rosTopic)
        return "rt/\(clean)"
    }

    /// Convert ROS type name to DDS type name
    ///
    /// "sensor_msgs/msg/Imu" -> "sensor_msgs::msg::dds_::Imu_"
    public func ddsTypeName(from rosTypeName: String) -> String {
        TypeNameConverter.toDDSTypeName(rosTypeName)
    }

    /// Build USER_DATA QoS string for DDS discovery
    ///
    /// Format: "typehash=RIHS01_...;"
    public func userDataString(typeHash: String?) -> String? {
        guard let hash = typeHash, !hash.isEmpty else { return nil }
        return "typehash=\(hash);"
    }
}
