// SampleIdentityPrefix.swift
// Encode / decode the DDS service sample-identity prefix.

import Foundation

/// Encode / decode the DDS service sample-identity prefix.
///
/// Wire layout: `[CDR header (4) | RMWRequestId (24) | user struct body]`.
/// The user CDR passed in already carries its own 4-byte encapsulation header
/// at offset 0 — the encoder strips it once and writes the single header at
/// the start of the wire payload.
enum SampleIdentityPrefix {
    static let cdrHeader = Data([0x00, 0x01, 0x00, 0x00])
    static let prefixedHeaderCount = cdrHeader.count + RMWRequestId.cdrByteCount  // 28

    enum DecodeError: Error, Equatable {
        case payloadTooShort(Int)
        case missingEncapsulationHeader
    }

    static func encode(requestId: RMWRequestId, userCDR: Data) -> Data {
        precondition(userCDR.count >= 4, "userCDR must include 4-byte CDR encapsulation header")
        var out = Data(capacity: prefixedHeaderCount + (userCDR.count - 4))
        out.append(cdrHeader)
        out.append(contentsOf: requestId.writerGuid)
        var seqLE = requestId.sequenceNumber.littleEndian
        withUnsafeBytes(of: &seqLE) { out.append(contentsOf: $0) }
        out.append(userCDR.dropFirst(4))
        return out
    }

    static func decode(wirePayload: Data) throws -> (RMWRequestId, Data) {
        guard wirePayload.count >= prefixedHeaderCount else {
            throw DecodeError.payloadTooShort(wirePayload.count)
        }
        guard wirePayload.prefix(4) == cdrHeader else {
            throw DecodeError.missingEncapsulationHeader
        }
        let guidStart = wirePayload.startIndex.advanced(by: 4)
        let seqStart = guidStart.advanced(by: 16)
        let bodyStart = seqStart.advanced(by: 8)
        let guid = Array(wirePayload[guidStart..<seqStart])
        let seq = wirePayload[seqStart..<bodyStart].withUnsafeBytes {
            $0.loadUnaligned(as: Int64.self).littleEndian
        }
        let id = RMWRequestId(writerGuid: guid, sequenceNumber: seq)
        var userCDR = cdrHeader
        userCDR.append(wirePayload[bodyStart..<wirePayload.endIndex])
        return (id, userCDR)
    }
}
