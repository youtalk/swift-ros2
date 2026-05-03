import Foundation
import XCTest

@testable import SwiftROS2CDR
@testable import SwiftROS2Messages

final class ActionMsgsCDRTests: XCTestCase {

    func testGoalInfoRoundTrip() throws {
        let original = GoalInfo(
            goalId: UniqueIdentifierUUID(uuid: (1...16).map { UInt8($0) }),
            stamp: BuiltinInterfacesTime(sec: 7, nanosec: 8)
        )
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try GoalInfo(from: dec)
        XCTAssertEqual(decoded.goalId.uuid, original.goalId.uuid)
        XCTAssertEqual(decoded.stamp.sec, 7)
        XCTAssertEqual(decoded.stamp.nanosec, 8)
    }

    func testGoalInfoGoldenBytes() throws {
        let m = GoalInfo(
            goalId: UniqueIdentifierUUID(uuid: Array(repeating: 0, count: 16)),
            stamp: BuiltinInterfacesTime(sec: 1, nanosec: 2)
        )
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try m.encode(to: enc)
        // 4-byte encap + 16 zero UUID bytes + int32 sec + uint32 nanosec.
        // UUID is 16 bytes already aligned to 4; sec / nanosec offsets need no padding.
        XCTAssertEqual(
            enc.getData(),
            Data(
                [0x00, 0x01, 0x00, 0x00]
                    + Array(repeating: UInt8(0), count: 16)
                    + [
                        0x01, 0x00, 0x00, 0x00,
                        0x02, 0x00, 0x00, 0x00,
                    ]
            )
        )
    }
}
