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
    private let isLegacySchema: Bool
    private var sequenceNumber: Int64 = 0
    private let lock = NSLock()

    init(transportPublisher: any TransportPublisher, isLegacySchema: Bool = false) {
        self.transportPublisher = transportPublisher
        self.isLegacySchema = isLegacySchema
    }

    /// Publish a message
    ///
    /// The Publisher writes the 4-byte CDR encapsulation header (`00 01 00 00` for
    /// little-endian XCDR v1) before delegating to `message.encode(to:)`. All
    /// `ROS2Message` conformers (generated and hand-written) write payload only —
    /// the Publisher writes the header. Per-type `encode(to:)` implementations
    /// must therefore not call `writeEncapsulationHeader()` themselves.
    public func publish(_ message: M) throws {
        let encoder = CDREncoder(isLegacySchema: isLegacySchema)
        encoder.writeEncapsulationHeader()
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
