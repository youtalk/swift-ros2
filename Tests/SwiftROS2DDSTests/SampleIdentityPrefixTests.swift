// SampleIdentityPrefixTests.swift
// Encode / decode of the 24-byte sample-identity prefix used by DDS services.

import Foundation
import XCTest

@testable import SwiftROS2Transport

final class SampleIdentityPrefixTests: XCTestCase {
    func testEncodeProducesHeaderPlusPrefixPlusBody() {
        let id = RMWRequestId(
            writerGuid: Array(repeating: 0xAB, count: 16),
            sequenceNumber: 42
        )
        let userCDR = Data([0x00, 0x01, 0x00, 0x00, 0xDE, 0xAD, 0xBE, 0xEF])
        let wire = SampleIdentityPrefix.encode(requestId: id, userCDR: userCDR)
        XCTAssertEqual(wire.count, 32)
        XCTAssertEqual(wire.prefix(4), Data([0x00, 0x01, 0x00, 0x00]))
        XCTAssertEqual(wire.subdata(in: 4..<20), Data(repeating: 0xAB, count: 16))
        XCTAssertEqual(wire.subdata(in: 20..<28), Data([42, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(wire.suffix(4), Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testRoundTrip() throws {
        let id = RMWRequestId(
            writerGuid: (0..<16).map { UInt8($0) },
            sequenceNumber: 99
        )
        let userCDR = Data([0x00, 0x01, 0x00, 0x00, 0x01, 0x02, 0x03])
        let wire = SampleIdentityPrefix.encode(requestId: id, userCDR: userCDR)
        let (parsedId, parsedUserCDR) = try SampleIdentityPrefix.decode(wirePayload: wire)
        XCTAssertEqual(parsedId, id)
        XCTAssertEqual(parsedUserCDR, userCDR)
    }

    func testDecodeRejectsTooShortPayload() {
        XCTAssertThrowsError(try SampleIdentityPrefix.decode(wirePayload: Data(count: 27)))
    }

    func testDecodeRejectsMissingHeader() {
        var data = Data([0xFF, 0xFF, 0xFF, 0xFF])
        data.append(Data(count: 24))
        XCTAssertThrowsError(try SampleIdentityPrefix.decode(wirePayload: data))
    }
}
