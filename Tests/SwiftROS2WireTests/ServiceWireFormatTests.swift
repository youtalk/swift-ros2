// ServiceWireFormatTests.swift
// Golden tests for the Service-shaped wire format helpers
// (Zenoh service key expression, SS / SC liveliness tokens, DDS rq / rr
// topic names, and Service request/response DDS type-name conversion).

import XCTest

@testable import SwiftROS2Wire

final class ServiceWireFormatTests: XCTestCase {
    // MARK: - DDS service type names

    func testDDSServiceRequestTypeName() {
        XCTAssertEqual(
            TypeNameConverter.toDDSServiceRequestTypeName("example_interfaces/srv/AddTwoInts"),
            "example_interfaces::srv::dds_::AddTwoInts_Request_"
        )
        XCTAssertEqual(
            TypeNameConverter.toDDSServiceRequestTypeName("std_srvs/srv/Trigger"),
            "std_srvs::srv::dds_::Trigger_Request_"
        )
    }

    func testDDSServiceResponseTypeName() {
        XCTAssertEqual(
            TypeNameConverter.toDDSServiceResponseTypeName("example_interfaces/srv/AddTwoInts"),
            "example_interfaces::srv::dds_::AddTwoInts_Response_"
        )
        XCTAssertEqual(
            TypeNameConverter.toDDSServiceResponseTypeName("std_srvs/srv/Trigger"),
            "std_srvs::srv::dds_::Trigger_Response_"
        )
    }

    // MARK: - Zenoh service key expression

    func testJazzyServiceKeyExpression() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeServiceKeyExpr(
            domainId: 0,
            namespace: "",
            serviceName: "add_two_ints",
            serviceTypeName: "example_interfaces/srv/AddTwoInts",
            requestTypeHash: "RIHS01_abc123"
        )
        XCTAssertEqual(
            key,
            "0/add_two_ints/example_interfaces::srv::dds_::AddTwoInts_Request_/RIHS01_abc123"
        )
    }

    func testJazzyServiceKeyExpressionWithNamespace() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeServiceKeyExpr(
            domainId: 0,
            namespace: "/ios",
            serviceName: "trigger",
            serviceTypeName: "std_srvs/srv/Trigger",
            requestTypeHash: "RIHS01_aaa"
        )
        XCTAssertEqual(
            key,
            "0/ios/trigger/std_srvs::srv::dds_::Trigger_Request_/RIHS01_aaa"
        )
    }

    func testHumbleServiceKeyExpression() {
        let codec = ZenohWireCodec(distro: .humble)
        let key = codec.makeServiceKeyExpr(
            domainId: 0,
            namespace: "",
            serviceName: "add_two_ints",
            serviceTypeName: "example_interfaces/srv/AddTwoInts",
            requestTypeHash: nil
        )
        XCTAssertEqual(
            key,
            "0/add_two_ints/example_interfaces::srv::dds_::AddTwoInts_Request_/TypeHashNotSupported"
        )
    }

    func testJazzyServiceKeyExpressionNoTypeHash() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let key = codec.makeServiceKeyExpr(
            domainId: 0,
            namespace: "",
            serviceName: "add_two_ints",
            serviceTypeName: "example_interfaces/srv/AddTwoInts",
            requestTypeHash: nil
        )
        // Jazzy omits trailing segment when hash is empty (parallel to Pub/Sub).
        XCTAssertEqual(
            key,
            "0/add_two_ints/example_interfaces::srv::dds_::AddTwoInts_Request_"
        )
    }

    // MARK: - Zenoh service liveliness tokens

    func testJazzyServiceServerLiveliness() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let qosSuffix = QoSPolicy.servicesDefault.toKeyExpr()
        let token = codec.makeServiceLivelinessToken(
            entityKind: .serviceServer,
            domainId: 0,
            sessionId: "AABB",
            nodeId: "1",
            entityId: "2",
            namespace: "/ios",
            nodeName: "node",
            serviceName: "trigger",
            serviceTypeName: "std_srvs/srv/Trigger",
            requestTypeHash: "RIHS01_aaa",
            qos: .servicesDefault
        )
        XCTAssertEqual(
            token,
            "@ros2_lv/0/AABB/1/2/SS/%/%/node/%ios%trigger/std_srvs::srv::dds_::Trigger_Request_/RIHS01_aaa/\(qosSuffix)"
        )
    }

    func testJazzyServiceClientLiveliness() {
        let codec = ZenohWireCodec(distro: .jazzy)
        let qosSuffix = QoSPolicy.servicesDefault.toKeyExpr()
        let token = codec.makeServiceLivelinessToken(
            entityKind: .serviceClient,
            domainId: 0,
            sessionId: "AABB",
            nodeId: "1",
            entityId: "3",
            namespace: "",
            nodeName: "node",
            serviceName: "trigger",
            serviceTypeName: "std_srvs/srv/Trigger",
            requestTypeHash: "RIHS01_aaa",
            qos: .servicesDefault
        )
        XCTAssertEqual(
            token,
            "@ros2_lv/0/AABB/1/3/SC/%/%/node/%trigger/std_srvs::srv::dds_::Trigger_Request_/RIHS01_aaa/\(qosSuffix)"
        )
    }

    func testHumbleServiceServerLiveliness() {
        let codec = ZenohWireCodec(distro: .humble)
        let qosSuffix = QoSPolicy.servicesDefault.toKeyExpr()
        let token = codec.makeServiceLivelinessToken(
            entityKind: .serviceServer,
            domainId: 0,
            sessionId: "AABB",
            nodeId: "1",
            entityId: "2",
            namespace: "",
            nodeName: "node",
            serviceName: "trigger",
            serviceTypeName: "std_srvs/srv/Trigger",
            requestTypeHash: nil,
            qos: .servicesDefault
        )
        XCTAssertEqual(
            token,
            "@ros2_lv/0/AABB/1/2/SS/%/%/node/%trigger/std_srvs::srv::dds_::Trigger_Request_/TypeHashNotSupported/\(qosSuffix)"
        )
    }

    func testServiceEntityKindRawValues() {
        XCTAssertEqual(ZenohWireCodec.ServiceEntityKind.serviceServer.rawValue, "SS")
        XCTAssertEqual(ZenohWireCodec.ServiceEntityKind.serviceClient.rawValue, "SC")
    }

    // MARK: - DDS service topic names

    func testDDSServiceTopicNames() {
        let codec = DDSWireCodec()
        let names = codec.serviceTopicNames(
            serviceName: "/add_two_ints",
            serviceTypeName: "example_interfaces/srv/AddTwoInts"
        )
        XCTAssertEqual(names.requestTopic, "rq/add_two_intsRequest")
        XCTAssertEqual(names.replyTopic, "rr/add_two_intsReply")
        XCTAssertEqual(names.requestTypeName, "example_interfaces::srv::dds_::AddTwoInts_Request_")
        XCTAssertEqual(names.replyTypeName, "example_interfaces::srv::dds_::AddTwoInts_Response_")
    }

    func testDDSServiceTopicNamesNoLeadingSlash() {
        let codec = DDSWireCodec()
        let names = codec.serviceTopicNames(
            serviceName: "trigger",
            serviceTypeName: "std_srvs/srv/Trigger"
        )
        XCTAssertEqual(names.requestTopic, "rq/triggerRequest")
        XCTAssertEqual(names.replyTopic, "rr/triggerReply")
    }

    func testDDSServiceTopicNamesNamespacedService() {
        let codec = DDSWireCodec()
        let names = codec.serviceTopicNames(
            serviceName: "/ios/trigger",
            serviceTypeName: "std_srvs/srv/Trigger"
        )
        XCTAssertEqual(names.requestTopic, "rq/ios/triggerRequest")
        XCTAssertEqual(names.replyTopic, "rr/ios/triggerReply")
    }
}
