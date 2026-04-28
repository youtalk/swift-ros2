// RMWRequestId.swift
// DDS service request-id primitive (rmw_cyclonedds_cpp interop)

import SwiftROS2CDR

/// 24-byte sample-identity prefix carried by every DDS service
/// request and reply payload, sitting after the 4-byte CDR
/// encapsulation header and before the user struct CDR.
///
/// Layout (XCDR v1 little-endian):
/// - bytes 0..15:  `writer_guid` (int8[16]) — client-side writer GUID
/// - bytes 16..23: `sequence_number` (int64 LE) — monotonic per client
///
/// The `int8[16]` array has 1-byte alignment, so the 8-byte
/// `sequence_number` lands on offset 16 with no padding.
public struct RMWRequestId: Sendable, Equatable {
    public let writerGuid: [UInt8]  // 16 bytes
    public let sequenceNumber: Int64

    public static let cdrByteCount: Int = 24

    public init(writerGuid: [UInt8], sequenceNumber: Int64) {
        precondition(writerGuid.count == 16, "writerGuid must be exactly 16 bytes")
        self.writerGuid = writerGuid
        self.sequenceNumber = sequenceNumber
    }

    /// Encode the 24-byte prefix into an existing encoder. Must be called
    /// immediately after `writeEncapsulationHeader()` and before the user
    /// struct's CDR contents.
    public func encode(into encoder: CDREncoder) {
        for byte in writerGuid {
            encoder.writeUInt8(byte)
        }
        encoder.writeInt64(sequenceNumber)
    }

    /// Decode the 24-byte prefix from a decoder positioned at the byte
    /// immediately following the encapsulation header.
    public init(from decoder: CDRDecoder) throws {
        var guid = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            guid[i] = try decoder.readUInt8()
        }
        let seq = try decoder.readInt64()
        self.init(writerGuid: guid, sequenceNumber: seq)
    }
}
