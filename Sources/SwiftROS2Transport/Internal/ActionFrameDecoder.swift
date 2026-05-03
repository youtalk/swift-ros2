// ActionFrameDecoder.swift
// Pure CDR helpers for action wrapper frames (send_goal / get_result / feedback / status).
//
// Both the DDS and Zenoh action transports call into these helpers; there is
// no I/O here. The byte layouts mirror what `rosidl_generator_cpp` emits for
// the synthesized wrappers, validated by `Tests/SwiftROS2CDRTests/ActionWrappersCDRTests.swift`
// (Phase 1) and the recorded wire dumps from Phase 2.

import Foundation
import SwiftROS2CDR

enum ActionFrameDecoderError: Error {
    case payloadTooShort
    case invalidCount(UInt32)
    case malformedFrame(String)
}

/// CDR helpers for the synthesized action wrapper frames.
///
/// Frames in/out of this enum carry the 4-byte XCDR encapsulation header
/// (`00 01 00 00`). The transport calls `decode*` on incoming wire payloads
/// and `encode*` on outgoing wire payloads.
enum ActionFrameDecoder {
    static let cdrHeader = Data([0x00, 0x01, 0x00, 0x00])

    /// Status array entry — one per goal currently tracked server-side.
    typealias StatusEntry = (uuid: [UInt8], stampSec: Int32, stampNanosec: UInt32, status: Int8)

    // MARK: - SendGoal request

    /// Wire shape: `[header (4) | uuid[16] | <user goal CDR>]`.
    static func encodeSendGoalRequest(goalId: [UInt8], goalCDR: Data) -> Data {
        precondition(goalId.count == 16, "goalId must be 16 bytes")
        var out = Data(capacity: 4 + 16 + goalCDR.count)
        out.append(cdrHeader)
        out.append(contentsOf: goalId)
        out.append(goalCDR)
        return out
    }

    static func decodeSendGoalRequest(from data: Data) throws -> (goalId: [UInt8], goalCDR: Data) {
        guard data.count >= 4 + 16 else { throw ActionFrameDecoderError.payloadTooShort }
        let goalId = Array(data[(data.startIndex + 4)..<(data.startIndex + 4 + 16)])
        let body = data.suffix(from: data.startIndex + 4 + 16)
        return (goalId, Data(body))
    }

    // MARK: - SendGoal response

    /// Wire shape: `[header (4) | accepted (1) | pad (3) | sec (i32 LE) | nanosec (u32 LE)]`.
    /// The 3-byte pad satisfies the int32 alignment after the bool.
    static func encodeSendGoalResponse(accepted: Bool, stampSec: Int32, stampNanosec: UInt32) -> Data {
        var out = Data(capacity: 4 + 1 + 3 + 4 + 4)
        out.append(cdrHeader)
        out.append(accepted ? 1 : 0)
        out.append(contentsOf: [0, 0, 0])
        var sec = stampSec.littleEndian
        var nsec = stampNanosec.littleEndian
        withUnsafeBytes(of: &sec) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &nsec) { out.append(contentsOf: $0) }
        return out
    }

    static func decodeSendGoalResponse(from data: Data) throws -> (
        accepted: Bool, stampSec: Int32, stampNanosec: UInt32
    ) {
        guard data.count >= 4 + 1 + 3 + 4 + 4 else { throw ActionFrameDecoderError.payloadTooShort }
        let base = data.startIndex
        let accepted = data[base + 4] != 0
        let sec = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 8, as: Int32.self).littleEndian
        }
        let nsec = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self).littleEndian
        }
        return (accepted, sec, nsec)
    }

    // MARK: - GetResult request

    /// Wire shape: `[header (4) | uuid[16]]`.
    static func encodeGetResultRequest(goalId: [UInt8]) -> Data {
        precondition(goalId.count == 16, "goalId must be 16 bytes")
        var out = Data(capacity: 4 + 16)
        out.append(cdrHeader)
        out.append(contentsOf: goalId)
        return out
    }

    static func decodeGetResultRequest(from data: Data) throws -> [UInt8] {
        guard data.count >= 4 + 16 else { throw ActionFrameDecoderError.payloadTooShort }
        return Array(data[(data.startIndex + 4)..<(data.startIndex + 4 + 16)])
    }

    // MARK: - GetResult response

    /// Wire shape: `[header (4) | status (i8) | pad (3) | <user result CDR>]`.
    /// Note the user CDR here is the bare result body — it does NOT carry its
    /// own encapsulation header; that header was consumed when the umbrella
    /// API encoded just the body fields.
    static func encodeGetResultResponse(status: Int8, resultCDR: Data) -> Data {
        var out = Data(capacity: 4 + 1 + 3 + resultCDR.count)
        out.append(cdrHeader)
        let s = UInt8(bitPattern: status)
        out.append(s)
        out.append(contentsOf: [0, 0, 0])
        out.append(resultCDR)
        return out
    }

    static func decodeGetResultResponse(from data: Data) throws -> (status: Int8, resultCDR: Data) {
        guard data.count >= 4 + 1 + 3 else { throw ActionFrameDecoderError.payloadTooShort }
        let base = data.startIndex
        let status = Int8(bitPattern: data[base + 4])
        let body = data.suffix(from: base + 4 + 1 + 3)
        return (status, Data(body))
    }

    // MARK: - FeedbackMessage

    /// Wire shape: `[header (4) | uuid[16] | <user feedback CDR>]`.
    static func encodeFeedbackMessage(goalId: [UInt8], feedbackCDR: Data) -> Data {
        precondition(goalId.count == 16, "goalId must be 16 bytes")
        var out = Data(capacity: 4 + 16 + feedbackCDR.count)
        out.append(cdrHeader)
        out.append(contentsOf: goalId)
        out.append(feedbackCDR)
        return out
    }

    static func decodeFeedbackMessage(from data: Data) throws -> (
        goalId: [UInt8], feedbackCDR: Data
    ) {
        guard data.count >= 4 + 16 else { throw ActionFrameDecoderError.payloadTooShort }
        let goalId = Array(data[(data.startIndex + 4)..<(data.startIndex + 4 + 16)])
        let body = data.suffix(from: data.startIndex + 4 + 16)
        return (goalId, Data(body))
    }

    // MARK: - GoalStatusArray

    /// Wire shape: `[header (4) | count (u32 LE) | { uuid[16] | sec (i32) | nanosec (u32) | status (i8) | pad (3) } * count ]`.
    /// Each entry is 16 + 4 + 4 + 1 + 3 = 28 bytes (28 % 4 == 0).
    static func encodeStatusArray(entries: [StatusEntry]) -> Data {
        var out = Data(capacity: 4 + 4 + entries.count * 28)
        out.append(cdrHeader)
        var count = UInt32(entries.count).littleEndian
        withUnsafeBytes(of: &count) { out.append(contentsOf: $0) }
        for e in entries {
            precondition(e.uuid.count == 16, "uuid must be 16 bytes")
            out.append(contentsOf: e.uuid)
            var sec = e.stampSec.littleEndian
            var nsec = e.stampNanosec.littleEndian
            withUnsafeBytes(of: &sec) { out.append(contentsOf: $0) }
            withUnsafeBytes(of: &nsec) { out.append(contentsOf: $0) }
            out.append(UInt8(bitPattern: e.status))
            out.append(contentsOf: [0, 0, 0])
        }
        return out
    }

    static func decodeStatusArray(from data: Data) throws -> [StatusEntry] {
        guard data.count >= 4 + 4 else { throw ActionFrameDecoderError.payloadTooShort }
        let base = data.startIndex
        let count = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian
        }
        // Defensive cap mirrors `CDRDecoder.maxSequenceElements` (64 MiB / 28 bytes).
        let maxCount: UInt32 = (64 * 1024 * 1024) / 28
        guard count <= maxCount else { throw ActionFrameDecoderError.invalidCount(count) }
        let needed = 4 + 4 + Int(count) * 28
        guard data.count >= needed else { throw ActionFrameDecoderError.payloadTooShort }

        var out: [StatusEntry] = []
        out.reserveCapacity(Int(count))
        var offset = base + 8
        for _ in 0..<Int(count) {
            let uuid = Array(data[offset..<(offset + 16)])
            offset += 16
            let sec = data.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: offset - base, as: Int32.self).littleEndian
            }
            offset += 4
            let nsec = data.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: offset - base, as: UInt32.self).littleEndian
            }
            offset += 4
            let status = Int8(bitPattern: data[offset])
            offset += 1 + 3  // pad
            out.append((uuid: uuid, stampSec: sec, stampNanosec: nsec, status: status))
        }
        return out
    }
}
