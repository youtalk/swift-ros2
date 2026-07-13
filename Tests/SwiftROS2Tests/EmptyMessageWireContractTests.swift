// EmptyMessageWireContractTests.swift
// rosidl serializes the implicit `uint8 structure_needs_at_least_one_member`
// sentinel for every empty struct — message or service half — so the on-wire
// body of std_msgs/msg/Empty is exactly one 0x00 byte after the encapsulation
// header. The RIHS01 type hash already models the sentinel (the hash oracle
// pins it); these tests pin the codec to the same contract.

import SwiftROS2CDR
import SwiftROS2Messages
import XCTest

final class EmptyMessageWireContractTests: XCTestCase {
    func testEmptyMsgEncodesTheRosidlSentinelByte() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        try EmptyMsg().encode(to: encoder)
        XCTAssertEqual(
            [UInt8](encoder.getData()), [0x00, 0x01, 0x00, 0x00, 0x00],
            "empty message body must be the single rosidl sentinel byte")
    }

    func testEmptyMsgDecodesARosidlPayload() throws {
        // Exactly what rmw_serialize emits for std_msgs/msg/Empty.
        let decoder = try CDRDecoder(data: Data([0x00, 0x01, 0x00, 0x00, 0x00]))
        XCTAssertNoThrow(try EmptyMsg(from: decoder))
    }

    func testEmptySrvHalvesAgreeWithTheMessageContract() throws {
        // The service halves always carried the sentinel; the message type
        // must stay byte-compatible with them now that both share it.
        let msgEncoder = CDREncoder()
        msgEncoder.writeEncapsulationHeader()
        try EmptyMsg().encode(to: msgEncoder)
        let srvEncoder = CDREncoder()
        srvEncoder.writeEncapsulationHeader()
        try EmptyRequest().encode(to: srvEncoder)
        XCTAssertEqual(msgEncoder.getData(), srvEncoder.getData())
    }
}
