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
}
