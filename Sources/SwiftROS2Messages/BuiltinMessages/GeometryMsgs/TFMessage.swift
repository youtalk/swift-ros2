// TFMessage.swift
// tf2_msgs/msg/TFMessage

import Foundation
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
        encoder.writeEncapsulationHeader()
        encoder.writeUInt32(UInt32(transforms.count))
        for tf in transforms {
            // Inline serialization (no encapsulation header per element)
            try tf.header.encode(to: encoder)
            encoder.writeString(tf.childFrameId)
            try tf.transform.encode(to: encoder)
        }
    }

    public init(from decoder: CDRDecoder) throws {
        let count = Int(try decoder.readUInt32())
        var tfs = [TransformStamped]()
        tfs.reserveCapacity(count)
        for _ in 0..<count {
            let header = try Header(from: decoder)
            let childFrameId = try decoder.readString()
            let transform = try Transform(from: decoder)
            tfs.append(TransformStamped(header: header, childFrameId: childFrameId, transform: transform))
        }
        self.transforms = tfs
    }
}
