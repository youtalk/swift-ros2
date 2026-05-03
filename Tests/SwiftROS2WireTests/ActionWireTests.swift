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

    // MARK: - ZenohWireCodec.makeActionKeyExpr

    func testJazzyActionSendGoalKey() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeActionKeyExpr(
            role: .sendGoal,
            domainId: 0,
            namespace: "",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_3d088942b413247db536576f0286768c6be8fcd5d0c9a5d544f359fba090a238"
        )
        XCTAssertEqual(
            key,
            "0/fibonacci/_action/send_goal/example_interfaces::action::dds_::Fibonacci_SendGoal_Request_/RIHS01_3d088942b413247db536576f0286768c6be8fcd5d0c9a5d544f359fba090a238"
        )
    }

    func testJazzyActionCancelGoalKey() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeActionKeyExpr(
            role: .cancelGoal,
            domainId: 0,
            namespace: "",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_3d3c84653c1f96918086887e1dcb236faec88b81a5b14fd4cf4840065bcdf8af"
        )
        // cancel_goal uses the action_msgs/srv/CancelGoal_Request type, NOT the per-action type.
        XCTAssertEqual(
            key,
            "0/fibonacci/_action/cancel_goal/action_msgs::srv::dds_::CancelGoal_Request_/RIHS01_3d3c84653c1f96918086887e1dcb236faec88b81a5b14fd4cf4840065bcdf8af"
        )
    }

    func testJazzyActionGetResultKey() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeActionKeyExpr(
            role: .getResult,
            domainId: 0,
            namespace: "",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_c8a4f5e7d13b81286ee1043e2ecd084281cecf1ff06aaa799464f5f15479f003"
        )
        XCTAssertEqual(
            key,
            "0/fibonacci/_action/get_result/example_interfaces::action::dds_::Fibonacci_GetResult_Request_/RIHS01_c8a4f5e7d13b81286ee1043e2ecd084281cecf1ff06aaa799464f5f15479f003"
        )
    }

    func testJazzyActionFeedbackKey() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeActionKeyExpr(
            role: .feedback,
            domainId: 0,
            namespace: "",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_c1de71afd52e49a89c53d8262366884185bc0a02f78ce051c4e46b0a7fe59bb2"
        )
        XCTAssertEqual(
            key,
            "0/fibonacci/_action/feedback/example_interfaces::action::dds_::Fibonacci_FeedbackMessage_/RIHS01_c1de71afd52e49a89c53d8262366884185bc0a02f78ce051c4e46b0a7fe59bb2"
        )
    }

    func testJazzyActionStatusKey() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeActionKeyExpr(
            role: .status,
            domainId: 0,
            namespace: "",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_6c1684b00f177d37438febe6e709fc4e2b0d4248dca4854946f9ed8b30cda83e"
        )
        // status uses action_msgs/msg/GoalStatusArray, fixed across all actions.
        XCTAssertEqual(
            key,
            "0/fibonacci/_action/status/action_msgs::msg::dds_::GoalStatusArray_/RIHS01_6c1684b00f177d37438febe6e709fc4e2b0d4248dca4854946f9ed8b30cda83e"
        )
    }

    func testJazzyActionKeyWithNamespace() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeActionKeyExpr(
            role: .sendGoal,
            domainId: 0,
            namespace: "/ios",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_aaa"
        )
        XCTAssertEqual(
            key,
            "0/ios/fibonacci/_action/send_goal/example_interfaces::action::dds_::Fibonacci_SendGoal_Request_/RIHS01_aaa"
        )
    }

    func testHumbleActionKeyAppendsTypeHashNotSupported() {
        let codec = ZenohWireCodec(distro: .humble)
        let key = codec.makeActionKeyExpr(
            role: .sendGoal,
            domainId: 0,
            namespace: "",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: nil
        )
        XCTAssertEqual(
            key,
            "0/fibonacci/_action/send_goal/example_interfaces::action::dds_::Fibonacci_SendGoal_Request_/TypeHashNotSupported"
        )
    }

    func testJazzyActionKeyOmitsEmptyHashSegment() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeActionKeyExpr(
            role: .sendGoal,
            domainId: 0,
            namespace: "",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: nil
        )
        XCTAssertEqual(
            key,
            "0/fibonacci/_action/send_goal/example_interfaces::action::dds_::Fibonacci_SendGoal_Request_"
        )
    }

    func testActionKeyStripsLeadingSlashFromActionName() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let withSlash = codec.makeActionKeyExpr(
            role: .feedback,
            domainId: 0,
            namespace: "",
            actionName: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_aaa"
        )
        let withoutSlash = codec.makeActionKeyExpr(
            role: .feedback,
            domainId: 0,
            namespace: "",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_aaa"
        )
        XCTAssertEqual(withSlash, withoutSlash)
        XCTAssertFalse(withSlash.contains("//"))
    }

    func testActionRoleRawValues() {
        XCTAssertEqual(ZenohWireCodec.ActionRole.sendGoal.rawValue, "send_goal")
        XCTAssertEqual(ZenohWireCodec.ActionRole.cancelGoal.rawValue, "cancel_goal")
        XCTAssertEqual(ZenohWireCodec.ActionRole.getResult.rawValue, "get_result")
        XCTAssertEqual(ZenohWireCodec.ActionRole.feedback.rawValue, "feedback")
        XCTAssertEqual(ZenohWireCodec.ActionRole.status.rawValue, "status")
    }

    // MARK: - ZenohWireCodec.makeActionLivelinessToken

    func testActionEntityKindRawValues() {
        XCTAssertEqual(ZenohWireCodec.ActionEntityKind.actionServer.rawValue, "SA")
        XCTAssertEqual(ZenohWireCodec.ActionEntityKind.actionClient.rawValue, "CA")
    }

    func testJazzyActionServerLiveliness() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let token = codec.makeActionLivelinessToken(
            entityKind: .actionServer,
            domainId: 0,
            sessionId: "ses",
            nodeId: "nod",
            entityId: "ent",
            namespace: "",
            nodeName: "fib_node",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_3d088942b413247db536576f0286768c6be8fcd5d0c9a5d544f359fba090a238",
            qos: QoSPolicy.servicesDefault
        )
        XCTAssertEqual(
            token,
            "@ros2_lv/0/ses/nod/ent/SA/%/%/fib_node/%fibonacci/example_interfaces::action::dds_::Fibonacci_SendGoal_Request_/RIHS01_3d088942b413247db536576f0286768c6be8fcd5d0c9a5d544f359fba090a238/\(QoSPolicy.servicesDefault.toKeyExpr())"
        )
    }

    func testJazzyActionClientLiveliness() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let token = codec.makeActionLivelinessToken(
            entityKind: .actionClient,
            domainId: 0,
            sessionId: "ses",
            nodeId: "nod",
            entityId: "ent",
            namespace: "/ios",
            nodeName: "fib_client",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_aaa",
            qos: QoSPolicy.servicesDefault
        )
        XCTAssertEqual(
            token,
            "@ros2_lv/0/ses/nod/ent/CA/%/%/fib_client/%ios%fibonacci/example_interfaces::action::dds_::Fibonacci_SendGoal_Request_/RIHS01_aaa/\(QoSPolicy.servicesDefault.toKeyExpr())"
        )
    }

    func testHumbleActionLivelinessUsesPlaceholder() {
        let codec = ZenohWireCodec(distro: .humble)
        let token = codec.makeActionLivelinessToken(
            entityKind: .actionServer,
            domainId: 0,
            sessionId: "ses",
            nodeId: "nod",
            entityId: "ent",
            namespace: "",
            nodeName: "fib_node",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: nil,
            qos: QoSPolicy.servicesDefault
        )
        XCTAssertTrue(
            token.contains("/example_interfaces::action::dds_::Fibonacci_SendGoal_Request_/TypeHashNotSupported/"),
            "Humble must include TypeHashNotSupported segment, got: \(token)"
        )
    }

    func testJazzyActionLivelinessOmitsEmptyHashSegment() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let token = codec.makeActionLivelinessToken(
            entityKind: .actionServer,
            domainId: 0,
            sessionId: "ses",
            nodeId: "nod",
            entityId: "ent",
            namespace: "",
            nodeName: "fib_node",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: nil,
            qos: QoSPolicy.servicesDefault
        )
        XCTAssertFalse(
            token.contains("//"),
            "no double-slash segment when hash is empty, got: \(token)"
        )
        XCTAssertTrue(
            token.hasSuffix("Fibonacci_SendGoal_Request_/\(QoSPolicy.servicesDefault.toKeyExpr())")
        )
    }

    func testActionLivelinessStripsLeadingSlashFromActionName() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let withSlash = codec.makeActionLivelinessToken(
            entityKind: .actionServer,
            domainId: 0,
            sessionId: "ses",
            nodeId: "nod",
            entityId: "ent",
            namespace: "",
            nodeName: "fib_node",
            actionName: "/fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_aaa",
            qos: QoSPolicy.servicesDefault
        )
        let withoutSlash = codec.makeActionLivelinessToken(
            entityKind: .actionServer,
            domainId: 0,
            sessionId: "ses",
            nodeId: "nod",
            entityId: "ent",
            namespace: "",
            nodeName: "fib_node",
            actionName: "fibonacci",
            actionTypeName: "example_interfaces/action/Fibonacci",
            roleTypeHash: "RIHS01_aaa",
            qos: QoSPolicy.servicesDefault
        )
        XCTAssertEqual(withSlash, withoutSlash)
        XCTAssertFalse(withSlash.contains("//"))
        XCTAssertTrue(withSlash.contains("/%fibonacci/"))
    }
}
