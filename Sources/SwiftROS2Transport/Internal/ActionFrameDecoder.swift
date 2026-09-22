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
/// Frames in/out of this enum carry exactly one 4-byte XCDR encapsulation
/// header (`00 01 00 00`), at offset 0 — the upstream `rosidl` layout that
/// real rmw peers (`rmw_cyclonedds_cpp`, `rmw_zenoh_cpp`, and `rmw_serialize`
/// on the `.rcl` transport) read. The transport calls `decode*` on incoming
/// wire payloads and `encode*` on outgoing wire payloads.
///
/// User payloads (goal / feedback / result) cross this boundary in the
/// umbrella's shape: `encode*` accepts them with or without a leading header
/// and splices only the bare body into the frame; `decode*` always returns
/// them with a leading header so `CDRDecoder` can read them.
enum ActionFrameDecoder {
    static let cdrHeader = Data([0x00, 0x01, 0x00, 0x00])

    /// The umbrella encodes every outbound user payload with a leading XCDR v1
    /// encapsulation header. Frames are consumed by real rmw peers, which expect
    /// the bare body at the splice offset (a Fibonacci goal would otherwise decode
    /// `order = 256`). Strip it before splicing.
    ///
    /// Precondition: `payload` is either umbrella-encoded (leading `00 01 00 00`)
    /// or bare. A *bare* payload whose first int32 happens to be 256 LE would be
    /// wrongly stripped — every caller today passes umbrella-encoded payloads.
    static func stripInnerEncapsulationHeader(_ payload: Data) -> Data {
        guard payload.count >= 4, payload.prefix(4) == cdrHeader else { return payload }
        return Data(payload.dropFirst(4))
    }

    /// Inbound bodies are always bare on the wire; hand the umbrella a payload
    /// `CDRDecoder` can read. Unconditional, so a body that merely *starts with*
    /// `00 01 00 00` (int32 256) is not mistaken for a header.
    private static func withHeader(_ body: Data) -> Data {
        var out = cdrHeader
        out.append(body)
        return out
    }

    /// Status array entry — one per goal currently tracked server-side.
    typealias StatusEntry = (uuid: [UInt8], stampSec: Int32, stampNanosec: UInt32, status: Int8)

    // MARK: - SendGoal request

    /// Wire shape: `[header (4) | uuid[16] | <bare user goal body>]`.
    /// `goalCDR` may carry the umbrella's encapsulation header; it is stripped.
    static func encodeSendGoalRequest(goalId: [UInt8], goalCDR: Data) -> Data {
        precondition(goalId.count == 16, "goalId must be 16 bytes")
        let goalCDR = stripInnerEncapsulationHeader(goalCDR)
        var out = Data(capacity: 4 + 16 + goalCDR.count)
        out.append(cdrHeader)
        out.append(contentsOf: goalId)
        out.append(goalCDR)
        return out
    }

    /// Returns the goal body with a leading encapsulation header.
    static func decodeSendGoalRequest(from data: Data) throws -> (goalId: [UInt8], goalCDR: Data) {
        guard data.count >= 4 + 16 else { throw ActionFrameDecoderError.payloadTooShort }
        let goalId = Array(data[(data.startIndex + 4)..<(data.startIndex + 4 + 16)])
        let body = data.suffix(from: data.startIndex + 4 + 16)
        return (goalId, withHeader(Data(body)))
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

    /// Wire shape: `[header (4) | status (i8) | pad (3) | <bare user result body>]`.
    /// The result body on the wire does NOT carry its own encapsulation header:
    /// `resultCDR` may carry the umbrella's header, and it is stripped here.
    ///
    /// Splice constraint: this frame pins the Result body to CDR offset 4.
    /// Real rosidl CDR pads `status` to offset 8 when the Result's first
    /// field is 8-byte aligned (float64 / int64 / uint64), so such an action
    /// would decode garbage on both this path and the `.rcl` rmw_deserialize
    /// path. The generator rejects those actions at registry-generation time
    /// — see `CActionRegistryEmitter.resultSpliceViolation` in SwiftROS2Gen.
    static func encodeGetResultResponse(status: Int8, resultCDR: Data) -> Data {
        let resultCDR = stripInnerEncapsulationHeader(resultCDR)
        var out = Data(capacity: 4 + 1 + 3 + resultCDR.count)
        out.append(cdrHeader)
        let s = UInt8(bitPattern: status)
        out.append(s)
        out.append(contentsOf: [0, 0, 0])
        out.append(resultCDR)
        return out
    }

    /// Returns the result body with a leading encapsulation header.
    static func decodeGetResultResponse(from data: Data) throws -> (status: Int8, resultCDR: Data) {
        guard data.count >= 4 + 1 + 3 else { throw ActionFrameDecoderError.payloadTooShort }
        let base = data.startIndex
        let status = Int8(bitPattern: data[base + 4])
        let body = data.suffix(from: base + 4 + 1 + 3)
        return (status, withHeader(Data(body)))
    }

    // MARK: - FeedbackMessage

    /// Wire shape: `[header (4) | uuid[16] | <bare user feedback body>]`.
    /// `feedbackCDR` may carry the umbrella's encapsulation header; it is stripped.
    static func encodeFeedbackMessage(goalId: [UInt8], feedbackCDR: Data) -> Data {
        precondition(goalId.count == 16, "goalId must be 16 bytes")
        let feedbackCDR = stripInnerEncapsulationHeader(feedbackCDR)
        var out = Data(capacity: 4 + 16 + feedbackCDR.count)
        out.append(cdrHeader)
        out.append(contentsOf: goalId)
        out.append(feedbackCDR)
        return out
    }

    /// Returns the feedback body with a leading encapsulation header.
    static func decodeFeedbackMessage(from data: Data) throws -> (
        goalId: [UInt8], feedbackCDR: Data
    ) {
        guard data.count >= 4 + 16 else { throw ActionFrameDecoderError.payloadTooShort }
        let goalId = Array(data[(data.startIndex + 4)..<(data.startIndex + 4 + 16)])
        let body = data.suffix(from: data.startIndex + 4 + 16)
        return (goalId, withHeader(Data(body)))
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
