// SetBool.swift
// std_srvs/srv/SetBool service type

import SwiftROS2CDR

/// std_srvs/srv/SetBool
///
/// Request carries `bool data`, response carries `bool success` +
/// `string message`. Common toggle / enable pattern.
public enum SetBoolSrv: ROS2ServiceType {
    public static let typeInfo = ROS2ServiceTypeInfo(
        serviceName: "std_srvs/srv/SetBool",
        requestTypeName: "std_srvs/srv/SetBool_Request",
        responseTypeName: "std_srvs/srv/SetBool_Response",
        requestTypeHash: "RIHS01_e54ad97d4c6c0fb620d1c9b4b3866c61d4a0bdc6c3eed3a09d80f10cfd0f72ee",
        responseTypeHash: "RIHS01_94aedf69bdb9e2f31d05c6d54e1d8b9f9ac6ac2c1ebcf7a3bb37b21e6bd49d4f"
    )

    public struct Request: ROS2Message {
        public static let typeInfo = ROS2MessageTypeInfo(
            typeName: "std_srvs/srv/SetBool_Request",
            typeHash: "RIHS01_e54ad97d4c6c0fb620d1c9b4b3866c61d4a0bdc6c3eed3a09d80f10cfd0f72ee"
        )

        public var data: Bool

        public init(data: Bool = false) {
            self.data = data
        }

        public func encode(to encoder: CDREncoder) throws {
            encoder.writeEncapsulationHeader()
            encoder.writeBool(data)
        }

        public init(from decoder: CDRDecoder) throws {
            self.data = try decoder.readBool()
        }
    }

    public struct Response: ROS2Message {
        public static let typeInfo = ROS2MessageTypeInfo(
            typeName: "std_srvs/srv/SetBool_Response",
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
