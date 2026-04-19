// CDRBoundsTests.swift
// Verifies CDRDecoder rejects untrusted lengths that would trigger allocation DoS.

import XCTest

@testable import SwiftROS2CDR

final class CDRBoundsTests: XCTestCase {

    private func cdrBuffer(_ body: [UInt8]) -> Data {
        var bytes: [UInt8] = [0x00, 0x01, 0x00, 0x00]
        bytes.append(contentsOf: body)
        return Data(bytes)
    }

    // MARK: - Typed sequence bounds (S-1)

    func testFloat64SequenceRejectsOversizedLength() throws {
        let body: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        XCTAssertThrowsError(try decoder.readFloat64Sequence()) { error in
            guard case CDRDecodingError.sequenceTooLarge(let elements, let max) = error else {
                XCTFail("Expected sequenceTooLarge, got \(error)")
                return
            }
            XCTAssertEqual(elements, UInt32.max)
            XCTAssertEqual(max, CDRDecoder.maxSequenceElements)
        }
    }

    func testFloat32SequenceRejectsOversizedLength() throws {
        let body: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        XCTAssertThrowsError(try decoder.readFloat32Sequence()) { error in
            guard case CDRDecodingError.sequenceTooLarge = error else {
                XCTFail("Expected sequenceTooLarge, got \(error)")
                return
            }
        }
    }

    func testInt32SequenceRejectsOversizedLength() throws {
        let body: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        XCTAssertThrowsError(try decoder.readInt32Sequence()) { error in
            guard case CDRDecodingError.sequenceTooLarge = error else {
                XCTFail("Expected sequenceTooLarge, got \(error)")
                return
            }
        }
    }

    func testSequenceAllowsValidSmallPayload() throws {
        // Use the encoder to produce a valid stream (alignment handled for us),
        // then decode with the bounds-checking decoder.
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeFloat64Sequence([1.0, 2.0])
        let decoder = try CDRDecoder(data: encoder.getData())
        let result = try decoder.readFloat64Sequence()
        XCTAssertEqual(result, [1.0, 2.0])
    }

    func testSequenceAllowsEmpty() throws {
        let body: [UInt8] = [0x00, 0x00, 0x00, 0x00]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        let result = try decoder.readFloat64Sequence()
        XCTAssertEqual(result, [])
    }

    // MARK: - Byte sequence bounds (S-1)

    func testByteSequenceRejectsOversizedLength() throws {
        let body: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        XCTAssertThrowsError(try decoder.readUInt8Sequence()) { error in
            guard case CDRDecodingError.byteSequenceTooLarge(let bytes, let max) = error else {
                XCTFail("Expected byteSequenceTooLarge, got \(error)")
                return
            }
            XCTAssertEqual(bytes, UInt32.max)
            XCTAssertEqual(max, CDRDecoder.maxByteSequenceLength)
        }
    }

    func testByteSequenceAllowsValidPayload() throws {
        // count = 3, bytes: [0x41, 0x42, 0x43] ("ABC")
        let body: [UInt8] = [0x03, 0x00, 0x00, 0x00, 0x41, 0x42, 0x43]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        let result = try decoder.readUInt8Sequence()
        XCTAssertEqual(Array(result), [0x41, 0x42, 0x43])
    }

    // MARK: - String bounds (S-2)

    func testStringRejectsOversizedLength() throws {
        let body: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        XCTAssertThrowsError(try decoder.readString()) { error in
            guard case CDRDecodingError.stringTooLarge(let length, let max) = error else {
                XCTFail("Expected stringTooLarge, got \(error)")
                return
            }
            XCTAssertEqual(length, UInt32.max)
            XCTAssertEqual(max, CDRDecoder.maxStringLength)
        }
    }

    func testStringAllowsSpecConformantEmpty() throws {
        // CDR empty string: length = 1 for the lone null terminator.
        let body: [UInt8] = [0x01, 0x00, 0x00, 0x00, 0x00]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        let result = try decoder.readString()
        XCTAssertEqual(result, "")
    }

    func testStringTreatsZeroLengthAsEmpty() throws {
        // Non-standard: length = 0 with no terminator byte. The decoder
        // intentionally tolerates this shape for backwards compatibility; this
        // test pins that behavior so a future change cannot remove it silently.
        let body: [UInt8] = [0x00, 0x00, 0x00, 0x00]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        let result = try decoder.readString()
        XCTAssertEqual(result, "")
    }

    func testStringAllowsShort() throws {
        // length = 3 ("hi\0"), bytes: 0x68 0x69 0x00
        let body: [UInt8] = [0x03, 0x00, 0x00, 0x00, 0x68, 0x69, 0x00]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        let result = try decoder.readString()
        XCTAssertEqual(result, "hi")
    }

    func testStringRejectsMissingNullTerminator() throws {
        // length = 3, bytes "ABC" (no trailing 0x00). Must fail rather than
        // silently decode as "AB" and drop the last byte.
        let body: [UInt8] = [0x03, 0x00, 0x00, 0x00, 0x41, 0x42, 0x43]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        XCTAssertThrowsError(try decoder.readString()) { error in
            guard case CDRDecodingError.missingStringNullTerminator = error else {
                XCTFail("Expected missingStringNullTerminator, got \(error)")
                return
            }
        }
    }

    // MARK: - Float NaN/Inf preservation (ensure bounds changes did not over-validate)

    func testFloat64PreservesQuietNaN() throws {
        // Quiet NaN: 0x7FF8000000000000 LE
        let body: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF8, 0x7F]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        let value = try decoder.readFloat64()
        XCTAssertTrue(value.isNaN)
    }

    func testFloat64PreservesPositiveInfinity() throws {
        // +Inf: 0x7FF0000000000000 LE
        let body: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x7F]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        let value = try decoder.readFloat64()
        XCTAssertEqual(value, .infinity)
    }

    func testFloat64PreservesNegativeInfinity() throws {
        // -Inf: 0xFFF0000000000000 LE
        let body: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0xFF]
        let decoder = try CDRDecoder(data: cdrBuffer(body))
        let value = try decoder.readFloat64()
        XCTAssertEqual(value, -.infinity)
    }
}
