// SampleIdentityPrefixTests.swift
// Encode / decode of the 16-byte request-header prefix used by DDS services
// (rmw_cyclonedds_cpp `cdds_request_header_t`).

import Foundation
import XCTest

@testable import SwiftROS2Transport

final class SampleIdentityPrefixTests: XCTestCase {
    func testEncodeProducesHeaderPlusPrefixPlusBody() {
        let id = RMWRequestId(writerGuid: [UInt8](1...8), sequenceNumber: 7)
        let wire = SampleIdentityPrefix.encode(
            requestId: id, userCDR: Data([0x00, 0x01, 0x00, 0x00, 0xAA, 0xBB]))
        XCTAssertEqual(
            Array(wire),
            [0x00, 0x01, 0x00, 0x00] + [UInt8](1...8) + [7, 0, 0, 0, 0, 0, 0, 0] + [0xAA, 0xBB])
        XCTAssertEqual(SampleIdentityPrefix.prefixedHeaderCount, 20)
    }

    func testRoundTrip() throws {
        let id = RMWRequestId(
            writerGuid: (0..<8).map { UInt8($0) },
            sequenceNumber: 99
        )
        let userCDR = Data([0x00, 0x01, 0x00, 0x00, 0x01, 0x02, 0x03])
        let wire = SampleIdentityPrefix.encode(requestId: id, userCDR: userCDR)
        let (parsedId, parsedUserCDR) = try SampleIdentityPrefix.decode(wirePayload: wire)
        XCTAssertEqual(parsedId, id)
        XCTAssertEqual(parsedUserCDR, userCDR)
    }

    func testDecodeRejectsTooShortPayload() {
        XCTAssertThrowsError(try SampleIdentityPrefix.decode(wirePayload: Data(count: 19)))
    }

    func testDecodeAcceptsMinimalRequestHeader() throws {
        // [header (4) | guid (8) | seq (8)] with an empty user body is the
        // shortest payload the decoder must accept.
        let wire = Data([0x00, 0x01, 0x00, 0x00] + [UInt8](1...8) + [3, 0, 0, 0, 0, 0, 0, 0])
        let (parsedId, parsedUserCDR) = try SampleIdentityPrefix.decode(wirePayload: wire)
        XCTAssertEqual(parsedId, RMWRequestId(writerGuid: [UInt8](1...8), sequenceNumber: 3))
        XCTAssertEqual(Array(parsedUserCDR), [0x00, 0x01, 0x00, 0x00])
    }

    func testDecodeRejectsMissingHeader() {
        var data = Data([0xFF, 0xFF, 0xFF, 0xFF])
        data.append(Data(count: 16))
        XCTAssertThrowsError(try SampleIdentityPrefix.decode(wirePayload: data))
    }
}
