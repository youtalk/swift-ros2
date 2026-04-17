// Publisher.swift
// ROS 2 Publisher

import Foundation
import SwiftROS2CDR
import SwiftROS2Messages
import SwiftROS2Transport

/// ROS 2 publisher for a specific message type
///
/// ```swift
/// let pub = try await node.createPublisher(Imu.self, topic: "imu")
/// try pub.publish(imuMessage)
/// ```
public final class ROS2Publisher<M: CDREncodable & ROS2MessageType>: @unchecked Sendable, PublisherCloseable {
    private let transportPublisher: any TransportPublisher
    private var sequenceNumber: Int64 = 0
    private let lock = NSLock()

    init(transportPublisher: any TransportPublisher) {
        self.transportPublisher = transportPublisher
    }

    /// Publish a message
    public func publish(_ message: M) throws {
        let encoder = CDREncoder()
        try message.encode(to: encoder)
        let data = encoder.getData()

        lock.lock()
        let seq = sequenceNumber
        sequenceNumber += 1
        lock.unlock()

        let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        try transportPublisher.publish(data: data, timestamp: timestamp, sequenceNumber: seq)
    }

    /// The topic this publisher is associated with
    public var topic: String {
        transportPublisher.topic
    }

    /// Whether the publisher is active
    public var isActive: Bool {
        transportPublisher.isActive
    }

    func closePublisher() throws {
        try transportPublisher.close()
    }
}
