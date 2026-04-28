// RMWRequestIdTests.swift
// Round-trip + golden-byte tests for the DDS sample-identity prefix.

import SwiftROS2CDR
import SwiftROS2Transport
import XCTest

final class RMWRequestIdTests: XCTestCase {

    func testRoundTrip() throws {
        let original = RMWRequestId(
            writerGuid: [
                0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
            ],
            sequenceNumber: 0x1122_3344_5566_7788
        )

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        original.encode(into: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try RMWRequestId(from: decoder)

        XCTAssertEqual(decoded, original)
    }

    func testGoldenBytesLittleEndianSequence() throws {
        let request = RMWRequestId(
            writerGuid: Array(repeating: 0xAA, count: 16),
            sequenceNumber: 0x0102_0304_0506_0708
        )

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        request.encode(into: encoder)
        let bytes = Array(encoder.getData())

        // 4-byte encap header (XCDR v1 LE).
        XCTAssertEqual(Array(bytes.prefix(4)), [0x00, 0x01, 0x00, 0x00])

        // 16 bytes of guid.
        XCTAssertEqual(Array(bytes[4..<20]), Array(repeating: 0xAA, count: 16))

        // 8 bytes sequence number, little-endian.
        XCTAssertEqual(
            Array(bytes[20..<28]),
            [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]
        )

        XCTAssertEqual(bytes.count, RMWRequestId.cdrByteCount + 4)
    }

    func testZeroValuedRoundTrip() throws {
        let zero = RMWRequestId(writerGuid: Array(repeating: 0, count: 16), sequenceNumber: 0)
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        zero.encode(into: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try RMWRequestId(from: decoder), zero)
    }
}
