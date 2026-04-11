// AudioData.swift
// audio_common_msgs/msg/AudioData

import Foundation
import RclSwiftCDR

/// audio_common_msgs/msg/AudioData
public struct AudioData: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "audio_common_msgs/msg/AudioData",
        typeHash: "RIHS01_a9742fba1567e649bbdba6ae034a72c7ef129b97c7a4da50fd2f3e1bfd8ffa86"
    )

    public var data: Data

    public init(data: Data = Data()) {
        self.data = data
    }

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        encoder.writeUInt8Sequence(data)
    }

    public init(from decoder: CDRDecoder) throws {
        self.data = try decoder.readUInt8Sequence()
    }
}
