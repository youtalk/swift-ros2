// Trigger.swift
// std_srvs/srv/Trigger service type

import SwiftROS2CDR

/// std_srvs/srv/Trigger
///
/// Empty request, response carries `bool success` + `string message`.
/// Standard ROS 2 demo / debugging service.
public enum TriggerSrv: ROS2ServiceType {
    public static let typeInfo = ROS2ServiceTypeInfo(
        serviceName: "std_srvs/srv/Trigger",
        requestTypeName: "std_srvs/srv/Trigger_Request",
        responseTypeName: "std_srvs/srv/Trigger_Response",
        requestTypeHash: "RIHS01_2bcae3ddbef0596d846efe3a73d144b3eee9aa9c92ed94d52ace1e10c3deb73e",
        responseTypeHash: "RIHS01_94aedf69bdb9e2f31d05c6d54e1d8b9f9ac6ac2c1ebcf7a3bb37b21e6bd49d4f"
    )

    public struct Request: ROS2Message {
        public static let typeInfo = ROS2MessageTypeInfo(
            typeName: "std_srvs/srv/Trigger_Request",
            typeHash: "RIHS01_2bcae3ddbef0596d846efe3a73d144b3eee9aa9c92ed94d52ace1e10c3deb73e"
        )

        public init() {}

        public func encode(to encoder: CDREncoder) throws {
            encoder.writeEncapsulationHeader()
            encoder.writeUInt8(0)
        }

        public init(from decoder: CDRDecoder) throws {
            _ = try decoder.readUInt8()
        }
    }

    public struct Response: ROS2Message {
        public static let typeInfo = ROS2MessageTypeInfo(
            typeName: "std_srvs/srv/Trigger_Response",
            typeHash: "RIHS01_94aedf69bdb9e2f31d05c6d54e1d8b9f9ac6ac2c1ebcf7a3bb37b21e6bd49d4f"
        )

        public var success: Bool
        public var message: String

        public init(success: Bool = false, message: String = "") {
            self.success = success
            self.message = message
        }

        public func encode(to encoder: CDREncoder) throws {
            encoder.writeEncapsulationHeader()
            encoder.writeBool(success)
            encoder.writeString(message)
        }

        public init(from decoder: CDRDecoder) throws {
            self.success = try decoder.readBool()
            self.message = try decoder.readString()
        }
    }
}
