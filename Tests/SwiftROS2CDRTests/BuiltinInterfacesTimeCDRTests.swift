import Foundation
import XCTest

@testable import SwiftROS2CDR
@testable import SwiftROS2Messages

final class BuiltinInterfacesTimeCDRTests: XCTestCase {

    func testRoundTrip() throws {
        let original = BuiltinInterfacesTime(sec: -42, nanosec: 1_234_567)
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try BuiltinInterfacesTime(from: dec)
        XCTAssertEqual(decoded.sec, -42)
        XCTAssertEqual(decoded.nanosec, 1_234_567)
    }

    func testGoldenBytes() throws {
        // sec = 1, nanosec = 2  →  4-byte encap + int32 LE 1 + uint32 LE 2
        let t = BuiltinInterfacesTime(sec: 1, nanosec: 2)
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try t.encode(to: enc)
        XCTAssertEqual(
            enc.getData(),
            Data([
                0x00, 0x01, 0x00, 0x00,  // encap header
                0x01, 0x00, 0x00, 0x00,  // sec = 1 (int32 LE)
                0x02, 0x00, 0x00, 0x00,  // nanosec = 2 (uint32 LE)
            ])
        )
    }
}
