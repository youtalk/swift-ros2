// ActionWireTests.swift
// Phase 2 wire-codec golden tests for ROS 2 Actions.

import XCTest

@testable import SwiftROS2Wire

final class ActionWireTests: XCTestCase {

    // MARK: - TypeNameConverter.toDDSActionRoleTypeName

    func testActionRoleTypeNameSendGoalRequest() {
        let name = TypeNameConverter.toDDSActionRoleTypeName(
            "example_interfaces/action/Fibonacci",
            role: "SendGoal",
            suffix: "Request"
        )
        XCTAssertEqual(name, "example_interfaces::action::dds_::Fibonacci_SendGoal_Request_")
    }

    func testActionRoleTypeNameSendGoalResponse() {
        let name = TypeNameConverter.toDDSActionRoleTypeName(
            "example_interfaces/action/Fibonacci",
            role: "SendGoal",
            suffix: "Response"
        )
        XCTAssertEqual(name, "example_interfaces::action::dds_::Fibonacci_SendGoal_Response_")
    }

    func testActionRoleTypeNameGetResultRequest() {
        let name = TypeNameConverter.toDDSActionRoleTypeName(
            "example_interfaces/action/Fibonacci",
            role: "GetResult",
            suffix: "Request"
        )
        XCTAssertEqual(name, "example_interfaces::action::dds_::Fibonacci_GetResult_Request_")
    }

    func testActionRoleTypeNameGetResultResponse() {
        let name = TypeNameConverter.toDDSActionRoleTypeName(
            "example_interfaces/action/Fibonacci",
            role: "GetResult",
            suffix: "Response"
        )
        XCTAssertEqual(name, "example_interfaces::action::dds_::Fibonacci_GetResult_Response_")
    }

    func testActionRoleTypeNameFeedbackMessage() {
        let name = TypeNameConverter.toDDSActionRoleTypeName(
            "example_interfaces/action/Fibonacci",
            role: "FeedbackMessage",
            suffix: nil
        )
        XCTAssertEqual(name, "example_interfaces::action::dds_::Fibonacci_FeedbackMessage_")
    }

    func testActionRoleTypeNameMalformedFallback() {
        // No `/action/` infix → conservative fallback that still emits a valid DDS-shape string.
        let name = TypeNameConverter.toDDSActionRoleTypeName(
            "weird_pkg.Fibonacci",
            role: "SendGoal",
            suffix: "Request"
        )
        XCTAssertEqual(name, "weird_pkg.Fibonacci_SendGoal_Request_")
    }
}
