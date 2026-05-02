// TypeNameConverter.swift
// Utilities for ROS 2 / DDS type name conversion

import Foundation

/// Shared utilities for ROS 2 type and topic name conversion
public enum TypeNameConverter {
    /// Strip leading "/" from a namespace
    public static func stripLeadingSlash(_ namespace: String) -> String {
        namespace.hasPrefix("/") ? String(namespace.dropFirst()) : namespace
    }

    /// Convert ROS type name to DDS format
    ///
    /// "sensor_msgs/msg/Imu" -> "sensor_msgs::msg::dds_::Imu_"
    public static func toDDSTypeName(_ typeName: String) -> String {
        let parts = typeName.split(separator: "/", maxSplits: .max, omittingEmptySubsequences: true)
        guard parts.count == 3 else {
            return typeName.replacingOccurrences(of: "/", with: "::") + "_"
        }
        return "\(parts[0])::\(parts[1])::dds_::\(parts[2])_"
    }

    /// Mangle topic path for liveliness tokens
    ///
    /// Combines namespace and topic, replacing "/" with "%":
    /// "/ios" + "imu" -> "%ios%imu"
    public static func mangleTopicPath(namespace: String, topic: String) -> String {
        let cleanNamespace = stripLeadingSlash(namespace)
        let fullPath: String
        if cleanNamespace.isEmpty {
            fullPath = "/" + topic
        } else {
            fullPath = "/" + cleanNamespace + "/" + topic
        }
        return fullPath.replacingOccurrences(of: "/", with: "%")
    }

    /// Convert a ROS service type name to the DDS request type name.
    ///
    /// "example_interfaces/srv/AddTwoInts" -> "example_interfaces::srv::dds_::AddTwoInts_Request_"
    public static func toDDSServiceRequestTypeName(_ serviceTypeName: String) -> String {
        toDDSServiceSuffixedTypeName(serviceTypeName, suffix: "Request")
    }

    /// Convert a ROS service type name to the DDS response type name.
    ///
    /// "example_interfaces/srv/AddTwoInts" -> "example_interfaces::srv::dds_::AddTwoInts_Response_"
    public static func toDDSServiceResponseTypeName(_ serviceTypeName: String) -> String {
        toDDSServiceSuffixedTypeName(serviceTypeName, suffix: "Response")
    }

    private static func toDDSServiceSuffixedTypeName(_ serviceTypeName: String, suffix: String) -> String {
        let parts = serviceTypeName.split(separator: "/", maxSplits: .max, omittingEmptySubsequences: true)
        guard parts.count == 3 else {
            return serviceTypeName.replacingOccurrences(of: "/", with: "::") + "_\(suffix)_"
        }
        return "\(parts[0])::\(parts[1])::dds_::\(parts[2])_\(suffix)_"
    }
}
