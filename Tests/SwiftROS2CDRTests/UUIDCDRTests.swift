// Tests/SwiftROS2CDRTests/UUIDCDRTests.swift
import Foundation
import XCTest

@testable import SwiftROS2CDR
@testable import SwiftROS2Messages

final class UUIDCDRTests: XCTestCase {

    func testRoundTrip() throws {
        let bytes: [UInt8] = (0..<16).map { UInt8($0) }
        let original = UniqueIdentifierUUID(uuid: bytes)
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try UniqueIdentifierUUID(from: dec)
        XCTAssertEqual(decoded.uuid, bytes)
    }

    func testGoldenBytes() throws {
        let bytes: [UInt8] = Array(repeating: 0xAB, count: 16)
        let m = UniqueIdentifierUUID(uuid: bytes)
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try m.encode(to: enc)
        XCTAssertEqual(
            enc.getData(),
            Data([0x00, 0x01, 0x00, 0x00] + Array(repeating: UInt8(0xAB), count: 16))
        )
    }

    func testFoundationBridgeRoundTrip() {
        let f = Foundation.UUID()
        let m = UniqueIdentifierUUID(foundationUUID: f)
        XCTAssertEqual(m.foundationUUID, f)
    }

    func testTypeInfo() {
        XCTAssertEqual(UniqueIdentifierUUID.typeInfo.typeName, "unique_identifier_msgs/msg/UUID")
    }
}
