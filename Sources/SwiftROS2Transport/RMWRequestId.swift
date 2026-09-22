// RMWRequestId.swift
// DDS service request-id primitive (rmw_cyclonedds_cpp interop)

import SwiftROS2CDR

/// 16-byte request header carried by every DDS service request and reply
/// payload, sitting after the 4-byte CDR encapsulation header and before the
/// user struct CDR.
///
/// This is `rmw_cyclonedds_cpp`'s `cdds_request_header_t { uint64_t guid;
/// int64_t seq; }` (`rmw_cyclonedds_cpp/src/serdata.hpp`), not the 24-byte
/// Fast-DDS `SampleIdentity`. A server echoes both fields verbatim into the
/// reply, which is how a client recognises its own replies.
///
/// Layout (XCDR v1 little-endian):
/// - bytes 0..7:  `guid` — opaque 8 bytes identifying the requesting client
/// - bytes 8..15: `seq` (int64 LE) — monotonic per client
///
/// The 8-byte `seq` lands on offset 8 with no padding.
package struct RMWRequestId: Sendable, Equatable {
    /// `cdds_request_header_t.guid` — 8 bytes on the wire. (rmw_cyclonedds_cpp's
    /// 16-byte `rmw_request_id_t.writer_guid` is this plus the locally derived
    /// publication handle, which never travels.)
    package let writerGuid: [UInt8]
    package let sequenceNumber: Int64

    package static let guidByteCount: Int = 8
    package static let cdrByteCount: Int = 16

    package init(writerGuid: [UInt8], sequenceNumber: Int64) {
        precondition(writerGuid.count == Self.guidByteCount, "writerGuid must be exactly 8 bytes")
        self.writerGuid = writerGuid
        self.sequenceNumber = sequenceNumber
    }

    /// Encode the 16-byte request header into an existing encoder. Must be
    /// called immediately after `writeEncapsulationHeader()` and before the
    /// user struct's CDR contents.
    package func encode(into encoder: CDREncoder) {
        for byte in writerGuid { encoder.writeUInt8(byte) }
        encoder.writeInt64(sequenceNumber)
    }

    /// Decode the 16-byte request header from a decoder positioned at the
    /// byte immediately following the encapsulation header.
    package init(from decoder: CDRDecoder) throws {
        var guid = [UInt8](repeating: 0, count: Self.guidByteCount)
        for i in 0..<Self.guidByteCount { guid[i] = try decoder.readUInt8() }
        self.init(writerGuid: guid, sequenceNumber: try decoder.readInt64())
    }
}
