// RMWRequestIdTests.swift
// Round-trip + golden-byte tests for the DDS service request header
// (rmw_cyclonedds_cpp `cdds_request_header_t`).

import SwiftROS2CDR
import SwiftROS2Transport
import XCTest

final class RMWRequestIdTests: XCTestCase {

    func testRoundTrip() throws {
        let original = RMWRequestId(
            writerGuid: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
            sequenceNumber: 0x1122_3344_5566_7788
        )

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        original.encode(into: encoder)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try RMWRequestId(from: decoder)

        XCTAssertEqual(decoded, original)
    }

    func testGoldenBytesMatchCycloneDDSRequestHeader() throws {
        // rmw_cyclonedds_cpp: cdds_request_header_t { uint64_t guid; int64_t seq; }
        let id = RMWRequestId(
            writerGuid: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08], sequenceNumber: 0x0A)
        // `encode(into:)` runs right after the encapsulation header (CDREncoder
        // aligns relative to the end of that header), exactly as on the wire.
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        id.encode(into: encoder)
        XCTAssertEqual(
            Array(encoder.getData()),
            [0x00, 0x01, 0x00, 0x00]
                + [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x0A, 0, 0, 0, 0, 0, 0, 0])
    }

    func testWireWidthIs16Bytes() {
        XCTAssertEqual(RMWRequestId.cdrByteCount, 16)
    }

    func testZeroValuedRoundTrip() throws {
        let zero = RMWRequestId(writerGuid: Array(repeating: 0, count: 8), sequenceNumber: 0)
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        zero.encode(into: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try RMWRequestId(from: decoder), zero)
    }
}
