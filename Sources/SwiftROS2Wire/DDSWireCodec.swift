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

    /// Names emitted for a DDS service: paired request / reply topics + DDS type names.
    public struct ServiceTopicNames: Sendable, Equatable {
        public let requestTopic: String
        public let replyTopic: String
        public let requestTypeName: String
        public let replyTypeName: String

        public init(
            requestTopic: String,
            replyTopic: String,
            requestTypeName: String,
            replyTypeName: String
        ) {
            self.requestTopic = requestTopic
            self.replyTopic = replyTopic
            self.requestTypeName = requestTypeName
            self.replyTypeName = replyTypeName
        }
    }

    /// Build the DDS topic / type name quadruple for a service.
    ///
    /// rmw_cyclonedds_cpp pairs each service with two topics:
    /// - `rq/<service>Request` (client → server)
    /// - `rr/<service>Reply`   (server → client)
    public func serviceTopicNames(
        serviceName: String,
        serviceTypeName: String
    ) -> ServiceTopicNames {
        let cleanService = TypeNameConverter.stripLeadingSlash(serviceName)
        return ServiceTopicNames(
            requestTopic: "rq/\(cleanService)Request",
            replyTopic: "rr/\(cleanService)Reply",
            requestTypeName: TypeNameConverter.toDDSServiceRequestTypeName(serviceTypeName),
            replyTypeName: TypeNameConverter.toDDSServiceResponseTypeName(serviceTypeName)
        )
    }
}
