import XCTest

@testable import SwiftROS2Messages

final class ROS2ActionTypeInfoTests: XCTestCase {

    func testLegacyThreeHashInitializerStillCompiles() {
        let info = ROS2ActionTypeInfo(
            actionName: "example_interfaces/action/Fibonacci",
            goalTypeHash: "RIHS01_aaaa",
            resultTypeHash: "RIHS01_bbbb",
            feedbackTypeHash: "RIHS01_cccc"
        )
        XCTAssertEqual(info.actionName, "example_interfaces/action/Fibonacci")
        XCTAssertEqual(info.goalTypeHash, "RIHS01_aaaa")
        XCTAssertEqual(info.resultTypeHash, "RIHS01_bbbb")
        XCTAssertEqual(info.feedbackTypeHash, "RIHS01_cccc")
        XCTAssertNil(info.sendGoalRequestTypeHash)
        XCTAssertNil(info.sendGoalResponseTypeHash)
        XCTAssertNil(info.getResultRequestTypeHash)
        XCTAssertNil(info.getResultResponseTypeHash)
        XCTAssertNil(info.feedbackMessageTypeHash)
    }

    func testFullEightHashInitializer() {
        let info = ROS2ActionTypeInfo(
            actionName: "example_interfaces/action/Fibonacci",
            goalTypeHash: "RIHS01_g",
            resultTypeHash: "RIHS01_r",
            feedbackTypeHash: "RIHS01_f",
            sendGoalRequestTypeHash: "RIHS01_sgrq",
            sendGoalResponseTypeHash: "RIHS01_sgrp",
            getResultRequestTypeHash: "RIHS01_grrq",
            getResultResponseTypeHash: "RIHS01_grrp",
            feedbackMessageTypeHash: "RIHS01_fm"
        )
        XCTAssertEqual(info.sendGoalRequestTypeHash, "RIHS01_sgrq")
        XCTAssertEqual(info.sendGoalResponseTypeHash, "RIHS01_sgrp")
        XCTAssertEqual(info.getResultRequestTypeHash, "RIHS01_grrq")
        XCTAssertEqual(info.getResultResponseTypeHash, "RIHS01_grrp")
        XCTAssertEqual(info.feedbackMessageTypeHash, "RIHS01_fm")
    }
}
