// UUID.swift
// unique_identifier_msgs/msg/UUID

import Foundation
import SwiftROS2CDR

/// ROS 2 `unique_identifier_msgs/msg/UUID` (16-byte fixed array).
///
/// Named `UniqueIdentifierUUID` to avoid clashing with ``Foundation/UUID``.
/// Use ``foundationUUID`` to bridge.
///
/// This is a nested CDR payload — it travels inside `GoalInfo` and the action
/// wrapper messages, never as a standalone top-level topic. It deliberately
/// does **not** conform to `ROS2Message` so that `ROS2Publisher` cannot
/// accept it directly and emit invalid (header-less) CDR. Same convention as
/// `Header` and `Vector3`.
public struct UniqueIdentifierUUID: CDRCodable, Sendable, Equatable {

    /// 16 raw bytes. Settable only via the validating ``init(uuid:)`` /
    /// ``init(foundationUUID:)``, which keep the 16-byte invariant.
    public private(set) var uuid: [UInt8]

    public init(uuid: [UInt8] = Array(repeating: 0, count: 16)) {
        precondition(uuid.count == 16, "UniqueIdentifierUUID requires 16 bytes")
        self.uuid = uuid
    }

    public init(foundationUUID: Foundation.UUID) {
        let t = foundationUUID.uuid
        self.uuid = [
            t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7,
            t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15,
        ]
    }

    public var foundationUUID: Foundation.UUID {
        Foundation.UUID(
            uuid: (
                uuid[0], uuid[1], uuid[2], uuid[3],
                uuid[4], uuid[5], uuid[6], uuid[7],
                uuid[8], uuid[9], uuid[10], uuid[11],
                uuid[12], uuid[13], uuid[14], uuid[15]
            ))
    }

    public func encode(to encoder: CDREncoder) throws {
        precondition(uuid.count == 16, "UniqueIdentifierUUID requires 16 bytes")
        for b in uuid {
            encoder.writeUInt8(b)
        }
    }

    public init(from decoder: CDRDecoder) throws {
        var out: [UInt8] = []
        out.reserveCapacity(16)
        for _ in 0..<16 {
            out.append(try decoder.readUInt8())
        }
        self.uuid = out
    }
}
