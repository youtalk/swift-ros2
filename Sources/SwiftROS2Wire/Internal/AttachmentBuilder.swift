// AttachmentBuilder.swift
// Builds the 33-byte rmw_zenoh attachment blob.
//
// Pure-bytes helper kept internal to SwiftROS2Wire — exposed only via
// ZenohWireCodec.buildAttachment. Lives in SwiftROS2Wire (not Transport)
// to avoid a Wire → Transport dependency cycle.

import Foundation

/// Builds the 33-byte rmw_zenoh attachment payload.
///
/// Layout (Zenoh ext::Serializer format):
/// - Bytes  0–7 : seq           (Int64 LE)
/// - Bytes  8–15: timestamp_ns  (Int64 LE)
/// - Byte   16  : 0x10          (LEB128 length prefix for 16-byte array)
/// - Bytes 17–32: GID           (16 raw bytes)
enum AttachmentBuilder {
    /// Build the 33-byte attachment.
    /// - Precondition: `gid.count == 16`.
    static func build(seq: Int64, tsNsec: Int64, gid: [UInt8]) -> Data {
        precondition(gid.count == 16, "Publisher GID must be exactly 16 bytes, got \(gid.count)")

        var data = Data(capacity: 33)

        var seqLE = seq.littleEndian
        withUnsafeBytes(of: &seqLE) { data.append(contentsOf: $0) }

        var tsLE = tsNsec.littleEndian
        withUnsafeBytes(of: &tsLE) { data.append(contentsOf: $0) }

        data.append(0x10)
        data.append(contentsOf: gid)

        assert(data.count == 33, "Attachment must be exactly 33 bytes")
        return data
    }
}
