// TFMessage.swift
// tf2_msgs/msg/TFMessage

import SwiftROS2CDR

/// tf2_msgs/msg/TFMessage
public struct TFMessage: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "tf2_msgs/msg/TFMessage",
        typeHash: "RIHS01_e369d0f05a23ae52508854b66f6aa0437f3449d652e8cbf22d5abe85d020f087"
    )

    public var transforms: [TransformStamped]

    public init(transforms: [TransformStamped] = []) {
        self.transforms = transforms
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeUInt32(UInt32(transforms.count))
        for tf in transforms {
            // Delegate per-element serialization (no encapsulation header per
            // element) so a future TransformStamped field cannot desynchronize.
            try tf.encode(to: encoder)
        }
    }

    public init(from decoder: CDRDecoder) throws {
        // readSequenceCount applies the shared DoS cap — the count is
        // network-controlled on the /tf subscribe path and must never reach
        // reserveCapacity unchecked.
        let count = try decoder.readSequenceCount()
        var tfs = [TransformStamped]()
        tfs.reserveCapacity(count)
        for _ in 0..<count {
            tfs.append(try TransformStamped(from: decoder))
        }
        self.transforms = tfs
    }
}
