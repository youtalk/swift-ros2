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
}
