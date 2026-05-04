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
            status: GoalStatus.STATUS_EXECUTING
        )
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try GoalStatus(from: dec)
        XCTAssertEqual(decoded.status, GoalStatus.STATUS_EXECUTING)
        XCTAssertEqual(decoded.goalInfo.stamp.sec, 9)
    }

    func testGoalStatusCodeRawValues() {
        XCTAssertEqual(GoalStatus.STATUS_UNKNOWN, 0)
        XCTAssertEqual(GoalStatus.STATUS_ACCEPTED, 1)
        XCTAssertEqual(GoalStatus.STATUS_EXECUTING, 2)
        XCTAssertEqual(GoalStatus.STATUS_CANCELING, 3)
        XCTAssertEqual(GoalStatus.STATUS_SUCCEEDED, 4)
        XCTAssertEqual(GoalStatus.STATUS_CANCELED, 5)
        XCTAssertEqual(GoalStatus.STATUS_ABORTED, 6)
    }

    func testGoalStatusArrayRoundTrip() throws {
        let s1 = GoalStatus(
            goalInfo: GoalInfo(
                goalId: UniqueIdentifierUUID(uuid: Array(repeating: 0x01, count: 16)),
                stamp: BuiltinInterfacesTime(sec: 1, nanosec: 0)
            ),
            status: GoalStatus.STATUS_ACCEPTED
        )
        let s2 = GoalStatus(
            goalInfo: GoalInfo(
                goalId: UniqueIdentifierUUID(uuid: Array(repeating: 0x02, count: 16)),
                stamp: BuiltinInterfacesTime(sec: 2, nanosec: 0)
            ),
            status: GoalStatus.STATUS_SUCCEEDED
        )
        let original = GoalStatusArray(statusList: [s1, s2])
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try GoalStatusArray(from: dec)
        XCTAssertEqual(decoded.statusList.count, 2)
        XCTAssertEqual(decoded.statusList[0].status, GoalStatus.STATUS_ACCEPTED)
        XCTAssertEqual(decoded.statusList[1].status, GoalStatus.STATUS_SUCCEEDED)
    }

    func testGoalStatusArrayEmpty() throws {
        let original = GoalStatusArray(statusList: [])
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
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
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try CancelGoalSrv.Request(from: dec)
        XCTAssertEqual(decoded.goalInfo.stamp.sec, 100)
    }

    func testCancelGoalResponseRoundTrip() throws {
        let original = CancelGoalSrv.Response(
            returnCode: CancelGoalResponse.ERROR_NONE,
            goalsCanceling: [
                GoalInfo(
                    goalId: UniqueIdentifierUUID(uuid: Array(repeating: 0xCC, count: 16)),
                    stamp: BuiltinInterfacesTime(sec: 1, nanosec: 0)
                )
            ]
        )
        let enc = CDREncoder()
        enc.writeEncapsulationHeader()
        try original.encode(to: enc)
        let dec = try CDRDecoder(data: enc.getData())
        let decoded = try CancelGoalSrv.Response(from: dec)
        XCTAssertEqual(decoded.returnCode, CancelGoalResponse.ERROR_NONE)
        XCTAssertEqual(decoded.goalsCanceling.count, 1)
    }

    func testCancelGoalReturnCodeRawValues() {
        XCTAssertEqual(CancelGoalResponse.ERROR_NONE, 0)
        XCTAssertEqual(CancelGoalResponse.ERROR_REJECTED, 1)
        XCTAssertEqual(CancelGoalResponse.ERROR_UNKNOWN_GOAL_ID, 2)
        XCTAssertEqual(CancelGoalResponse.ERROR_GOAL_TERMINATED, 3)
    }

    func testCancelGoalSrvTypeInfo() {
        XCTAssertEqual(CancelGoalSrv.typeInfo.serviceName, "action_msgs/srv/CancelGoal")
        XCTAssertEqual(CancelGoalSrv.typeInfo.requestTypeName, "action_msgs/srv/CancelGoal_Request")
        XCTAssertEqual(CancelGoalSrv.typeInfo.responseTypeName, "action_msgs/srv/CancelGoal_Response")
    }
}
