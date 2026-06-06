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
    ///
    /// The attachment's `timestamp_ns` field carries the wall-clock publish time
    /// and the sequence number comes from this publisher's own monotonic counter.
    /// Use ``publish(_:timestamp:sequenceNumber:)`` to supply a source timestamp
    /// (e.g. a sensor capture time) and/or an explicit sequence number instead.
    public func publish(_ message: M) throws {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        try publish(message, timestamp: timestamp, sequenceNumber: nil)
    }

    /// Publish a message with a caller-supplied source timestamp.
    ///
    /// Identical to ``publish(_:)`` in how it serializes the message (4-byte CDR
    /// encapsulation header + `message.encode(to:)`), but the attachment's
    /// `timestamp_ns` field carries `timestamp` instead of the wall-clock publish
    /// time. This lets a publisher stamp the message with the moment the data was
    /// captured (e.g. a sensor sample time) rather than the moment it went on the
    /// wire.
    ///
    /// - Parameters:
    ///   - message: The typed message to publish.
    ///   - timestamp: Source timestamp in nanoseconds since the Unix epoch,
    ///     written verbatim into the attachment's `timestamp_ns` field.
    ///   - sequenceNumber: An explicit attachment sequence number. When `nil`
    ///     (the default) this publisher's own monotonic counter is used, exactly
    ///     as ``publish(_:)`` does.
    public func publish(_ message: M, timestamp: UInt64, sequenceNumber: Int64? = nil) throws {
        let encoder = CDREncoder(isLegacySchema: isLegacySchema)
        encoder.writeEncapsulationHeader()
        try message.encode(to: encoder)
        let data = encoder.getData()

        let seq: Int64
        if let sequenceNumber {
            seq = sequenceNumber
        } else {
            lock.lock()
            seq = self.sequenceNumber
            self.sequenceNumber += 1
            lock.unlock()
        }

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
