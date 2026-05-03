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

    // MARK: - DDSWireCodec.actionTopicNames

    func testDDSActionTopicNames() {
        let codec = DDSWireCodec()
        let names = codec.actionTopicNames(
            namespace: "",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci"
        )
        XCTAssertEqual(names.sendGoalRequestTopic, "rq/fibonacci/_action/send_goalRequest")
        XCTAssertEqual(names.sendGoalReplyTopic, "rr/fibonacci/_action/send_goalReply")
        XCTAssertEqual(names.cancelGoalRequestTopic, "rq/fibonacci/_action/cancel_goalRequest")
        XCTAssertEqual(names.cancelGoalReplyTopic, "rr/fibonacci/_action/cancel_goalReply")
        XCTAssertEqual(names.getResultRequestTopic, "rq/fibonacci/_action/get_resultRequest")
        XCTAssertEqual(names.getResultReplyTopic, "rr/fibonacci/_action/get_resultReply")
        XCTAssertEqual(names.feedbackTopic, "rt/fibonacci/_action/feedback")
        XCTAssertEqual(names.statusTopic, "rt/fibonacci/_action/status")

        XCTAssertEqual(
            names.sendGoalRequestTypeName,
            "example_interfaces::action::dds_::Fibonacci_SendGoal_Request_")
        XCTAssertEqual(
            names.sendGoalReplyTypeName,
            "example_interfaces::action::dds_::Fibonacci_SendGoal_Response_")
        XCTAssertEqual(
            names.cancelGoalRequestTypeName,
            "action_msgs::srv::dds_::CancelGoal_Request_")
        XCTAssertEqual(
            names.cancelGoalReplyTypeName,
            "action_msgs::srv::dds_::CancelGoal_Response_")
        XCTAssertEqual(
            names.getResultRequestTypeName,
            "example_interfaces::action::dds_::Fibonacci_GetResult_Request_")
        XCTAssertEqual(
            names.getResultReplyTypeName,
            "example_interfaces::action::dds_::Fibonacci_GetResult_Response_")
        XCTAssertEqual(
            names.feedbackTypeName,
            "example_interfaces::action::dds_::Fibonacci_FeedbackMessage_")
        XCTAssertEqual(
            names.statusTypeName,
            "action_msgs::msg::dds_::GoalStatusArray_")
    }

    func testDDSActionTopicNamesWithNamespace() {
        let codec = DDSWireCodec()
        let names = codec.actionTopicNames(
            namespace: "/ios",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci"
        )
        XCTAssertEqual(names.sendGoalRequestTopic, "rq/ios/fibonacci/_action/send_goalRequest")
        XCTAssertEqual(names.feedbackTopic, "rt/ios/fibonacci/_action/feedback")
        XCTAssertEqual(names.statusTopic, "rt/ios/fibonacci/_action/status")
    }

    func testDDSActionTopicNamesStripsLeadingSlashOnAction() {
        let codec = DDSWireCodec()
        let withSlash = codec.actionTopicNames(
            namespace: "",
            actionName: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci"
        )
        let withoutSlash = codec.actionTopicNames(
            namespace: "",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci"
        )
        XCTAssertEqual(withSlash, withoutSlash)
        XCTAssertFalse(withSlash.sendGoalRequestTopic.contains("//"))
    }
}
