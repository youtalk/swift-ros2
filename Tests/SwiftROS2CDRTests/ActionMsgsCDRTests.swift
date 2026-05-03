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

    func testGoalStatusRoundTrip() throws {
        let original = GoalStatus(
            goalInfo: GoalInfo(
                goalId: UniqueIdentifierUUID(uuid: Array(repeating: 0xFE, count: 16)),
                stamp: BuiltinInterfacesTime(sec: 9, nanosec: 10)
            ),
            status: GoalStatusCode.executing.rawValue
        )
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try GoalStatus(from: dec)
        XCTAssertEqual(decoded.status, GoalStatusCode.executing.rawValue)
        XCTAssertEqual(decoded.goalInfo.stamp.sec, 9)
    }

    func testGoalStatusCodeRawValues() {
        XCTAssertEqual(GoalStatusCode.unknown.rawValue, 0)
        XCTAssertEqual(GoalStatusCode.accepted.rawValue, 1)
        XCTAssertEqual(GoalStatusCode.executing.rawValue, 2)
        XCTAssertEqual(GoalStatusCode.canceling.rawValue, 3)
        XCTAssertEqual(GoalStatusCode.succeeded.rawValue, 4)
        XCTAssertEqual(GoalStatusCode.canceled.rawValue, 5)
        XCTAssertEqual(GoalStatusCode.aborted.rawValue, 6)
    }

    func testGoalStatusArrayRoundTrip() throws {
        let s1 = GoalStatus(
            goalInfo: GoalInfo(
                goalId: UniqueIdentifierUUID(uuid: Array(repeating: 0x01, count: 16)),
                stamp: BuiltinInterfacesTime(sec: 1, nanosec: 0)
            ),
            status: GoalStatusCode.accepted.rawValue
        )
        let s2 = GoalStatus(
            goalInfo: GoalInfo(
                goalId: UniqueIdentifierUUID(uuid: Array(repeating: 0x02, count: 16)),
                stamp: BuiltinInterfacesTime(sec: 2, nanosec: 0)
            ),
            status: GoalStatusCode.succeeded.rawValue
        )
        let original = GoalStatusArray(statusList: [s1, s2])
        // GoalStatusArray is a top-level wire message; encode writes its own encapsulation header.
        let enc = CDREncoder()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try GoalStatusArray(from: dec)
        XCTAssertEqual(decoded.statusList.count, 2)
        XCTAssertEqual(decoded.statusList[0].status, GoalStatusCode.accepted.rawValue)
        XCTAssertEqual(decoded.statusList[1].status, GoalStatusCode.succeeded.rawValue)
    }

    func testGoalStatusArrayEmpty() throws {
        let original = GoalStatusArray(statusList: [])
        let enc = CDREncoder()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try GoalStatusArray(from: dec)
        XCTAssertEqual(decoded.statusList.count, 0)
    }

    func testCancelGoalRequestRoundTrip() throws {
        let original = CancelGoalSrv.Request(
            goalInfo: GoalInfo(
                goalId: UniqueIdentifierUUID(uuid: Array(repeating: 0x55, count: 16)),
                stamp: BuiltinInterfacesTime(sec: 100, nanosec: 200)
            )
        )
        let enc = CDREncoder()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try CancelGoalSrv.Request(from: dec)
        XCTAssertEqual(decoded.goalInfo.stamp.sec, 100)
    }

    func testCancelGoalResponseRoundTrip() throws {
        let original = CancelGoalSrv.Response(
            returnCode: CancelGoalReturnCode.none.rawValue,
            goalsCanceling: [
                GoalInfo(
                    goalId: UniqueIdentifierUUID(uuid: Array(repeating: 0xCC, count: 16)),
                    stamp: BuiltinInterfacesTime(sec: 1, nanosec: 0)
                )
            ]
        )
        let enc = CDREncoder()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try CancelGoalSrv.Response(from: dec)
        XCTAssertEqual(decoded.returnCode, CancelGoalReturnCode.none.rawValue)
        XCTAssertEqual(decoded.goalsCanceling.count, 1)
    }

    func testCancelGoalReturnCodeRawValues() {
        XCTAssertEqual(CancelGoalReturnCode.none.rawValue, 0)
        XCTAssertEqual(CancelGoalReturnCode.rejected.rawValue, 1)
        XCTAssertEqual(CancelGoalReturnCode.unknownGoalId.rawValue, 2)
        XCTAssertEqual(CancelGoalReturnCode.goalTerminated.rawValue, 3)
    }

    func testCancelGoalSrvTypeInfo() {
        XCTAssertEqual(CancelGoalSrv.typeInfo.serviceName, "action_msgs/srv/CancelGoal")
        XCTAssertEqual(CancelGoalSrv.typeInfo.requestTypeName, "action_msgs/srv/CancelGoal_Request")
        XCTAssertEqual(CancelGoalSrv.typeInfo.responseTypeName, "action_msgs/srv/CancelGoal_Response")
    }
}
