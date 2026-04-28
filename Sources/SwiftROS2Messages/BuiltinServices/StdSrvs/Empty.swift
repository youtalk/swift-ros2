// Empty.swift
// std_srvs/srv/Empty service type

import SwiftROS2CDR

/// std_srvs/srv/Empty
///
/// Both request and response are empty. Useful as a wire / golden test
/// fixture and as a no-payload trigger primitive.
public enum EmptySrv: ROS2ServiceType {
    public static let typeInfo = ROS2ServiceTypeInfo(
        serviceName: "std_srvs/srv/Empty",
        requestTypeName: "std_srvs/srv/Empty_Request",
        responseTypeName: "std_srvs/srv/Empty_Response",
        requestTypeHash: "RIHS01_2bcae3ddbef0596d846efe3a73d144b3eee9aa9c92ed94d52ace1e10c3deb73e",
        responseTypeHash: "RIHS01_60bf1cb1f04a8f9a385bcfd2c8b682e74acc16cd2f04948e8b3a25b3aae3ea7c"
    )

    public struct Request: ROS2Message {
        public static let typeInfo = ROS2MessageTypeInfo(
            typeName: "std_srvs/srv/Empty_Request",
            typeHash: "RIHS01_2bcae3ddbef0596d846efe3a73d144b3eee9aa9c92ed94d52ace1e10c3deb73e"
        )

        public init() {}

        public func encode(to encoder: CDREncoder) throws {
            encoder.writeEncapsulationHeader()
            // Empty struct CDR convention: emit a single 0x00 dummy byte so
            // CycloneDDS does not collapse the sample to zero length.
            encoder.writeUInt8(0)
        }

        public init(from decoder: CDRDecoder) throws {
            // Dummy byte; ignore the value.
            _ = try decoder.readUInt8()
        }
    }

    public struct Response: ROS2Message {
        public static let typeInfo = ROS2MessageTypeInfo(
            typeName: "std_srvs/srv/Empty_Response",
            typeHash: "RIHS01_60bf1cb1f04a8f9a385bcfd2c8b682e74acc16cd2f04948e8b3a25b3aae3ea7c"
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
}
