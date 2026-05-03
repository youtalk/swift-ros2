// ActionFrameDecoderTests.swift
// Round-trip tests for the per-frame CDR helpers shared between the DDS and Zenoh
// action transports.

import Foundation
import XCTest

@testable import SwiftROS2Transport

final class ActionFrameDecoderTests: XCTestCase {
    private let cdrHeader = Data([0x00, 0x01, 0x00, 0x00])  // XCDR v1 little-endian
    private let goalId16 = [UInt8](repeating: 0xAB, count: 16)

    func testEncodeDecodeSendGoalRequestRoundTrip() throws {
        let goalCDR = Data([0xDE, 0xAD, 0xBE, 0xEF])  // user-encoded Goal payload
        let frame = ActionFrameDecoder.encodeSendGoalRequest(goalId: goalId16, goalCDR: goalCDR)
        let (parsedId, parsedGoal) = try ActionFrameDecoder.decodeSendGoalRequest(from: frame)
        XCTAssertEqual(parsedId, goalId16)
        XCTAssertEqual(parsedGoal, goalCDR)
    }

    func testDecodeSendGoalRequestTooShortThrows() {
        let tooShort = Data([0x00, 0x01, 0x00, 0x00, 0x00])  // header + 1 byte
        XCTAssertThrowsError(try ActionFrameDecoder.decodeSendGoalRequest(from: tooShort))
    }

    func testEncodeDecodeGetResultRequestRoundTrip() throws {
        let frame = ActionFrameDecoder.encodeGetResultRequest(goalId: goalId16)
        let parsedId = try ActionFrameDecoder.decodeGetResultRequest(from: frame)
        XCTAssertEqual(parsedId, goalId16)
    }

    func testEncodeSendGoalResponse() {
        let frame = ActionFrameDecoder.encodeSendGoalResponse(
            accepted: true, stampSec: 7, stampNanosec: 11
        )
        // [header (4) | accepted (1) | pad (3) | sec (4) | nanosec (4)]
        XCTAssertEqual(frame.count, 4 + 1 + 3 + 4 + 4)
        XCTAssertEqual(frame[0..<4], cdrHeader)
        XCTAssertEqual(frame[4], 1)
        // Sec / nanosec start at offset 8 due to alignment.
        let sec = frame.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 8, as: Int32.self).littleEndian
        }
        let nsec = frame.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self).littleEndian
        }
        XCTAssertEqual(sec, 7)
        XCTAssertEqual(nsec, 11)
    }

    func testEncodeGetResultResponse() {
        let userCDR = Data([0x11, 0x22, 0x33, 0x44])
        let frame = ActionFrameDecoder.encodeGetResultResponse(
            status: 4, resultCDR: userCDR
        )
        // [header (4) | status (1) | pad (3) | userCDR ...]
        XCTAssertEqual(frame[0..<4], cdrHeader)
        XCTAssertEqual(frame[4], 4)
        XCTAssertEqual(frame.suffix(userCDR.count), userCDR)
    }

    func testEncodeDecodeFeedbackMessageRoundTrip() throws {
        let userCDR = Data([0x77, 0x88])
        let frame = ActionFrameDecoder.encodeFeedbackMessage(
            goalId: goalId16, feedbackCDR: userCDR
        )
        let (parsedId, parsedFeedback) = try ActionFrameDecoder.decodeFeedbackMessage(
            from: frame
        )
        XCTAssertEqual(parsedId, goalId16)
        XCTAssertEqual(parsedFeedback, userCDR)
    }

    func testEncodeDecodeStatusArrayRoundTrip() throws {
        let entries: [ActionFrameDecoder.StatusEntry] = [
            (uuid: goalId16, stampSec: 1, stampNanosec: 2, status: 1),
            (uuid: Array(repeating: 0xCD, count: 16), stampSec: 3, stampNanosec: 4, status: 4),
        ]
        let frame = ActionFrameDecoder.encodeStatusArray(entries: entries)
        let parsed = try ActionFrameDecoder.decodeStatusArray(from: frame)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].uuid, entries[0].uuid)
        XCTAssertEqual(parsed[0].status, 1)
        XCTAssertEqual(parsed[1].uuid, entries[1].uuid)
        XCTAssertEqual(parsed[1].status, 4)
    }

    func testDecodeStatusArrayEmptyRoundTrip() throws {
        let frame = ActionFrameDecoder.encodeStatusArray(entries: [])
        let parsed = try ActionFrameDecoder.decodeStatusArray(from: frame)
        XCTAssertTrue(parsed.isEmpty)
    }
}
