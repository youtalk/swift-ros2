// StdSrvsRoundTripTests.swift
// CDR round-trip tests for the std_srvs service types.

import SwiftROS2CDR
import SwiftROS2Messages
import XCTest

final class StdSrvsRoundTripTests: XCTestCase {

    func testEmptyRequestRoundTrip() throws {
        let request = EmptySrv.Request()
        let encoder = CDREncoder()
        try request.encode(to: encoder)
        let bytes = encoder.getData()

        // 4 bytes encap header + 1 byte filler.
        XCTAssertEqual(bytes.count, 5)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x00, 0x01, 0x00, 0x00])

        let decoder = try CDRDecoder(data: bytes)
        _ = try EmptySrv.Request(from: decoder)
    }

    func testEmptyResponseRoundTrip() throws {
        let response = EmptySrv.Response()
        let encoder = CDREncoder()
        try response.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        _ = try EmptySrv.Response(from: decoder)
    }

    func testTriggerRequestRoundTrip() throws {
        let request = TriggerSrv.Request()
        let encoder = CDREncoder()
        try request.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        _ = try TriggerSrv.Request(from: decoder)
    }

    func testTriggerResponseRoundTripSuccessTrue() throws {
        let response = TriggerSrv.Response(success: true, message: "ok")
        let encoder = CDREncoder()
        try response.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try TriggerSrv.Response(from: decoder)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.message, "ok")
    }

    func testTriggerResponseRoundTripSuccessFalseEmptyMessage() throws {
        let response = TriggerSrv.Response(success: false, message: "")
        let encoder = CDREncoder()
        try response.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try TriggerSrv.Response(from: decoder)
        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.message, "")
    }

    func testSetBoolRequestRoundTrip() throws {
        for value in [true, false] {
            let request = SetBoolSrv.Request(data: value)
            let encoder = CDREncoder()
            try request.encode(to: encoder)
            let decoder = try CDRDecoder(data: encoder.getData())
            let decoded = try SetBoolSrv.Request(from: decoder)
            XCTAssertEqual(decoded.data, value)
        }
    }

    func testSetBoolResponseRoundTrip() throws {
        let response = SetBoolSrv.Response(success: true, message: "applied")
        let encoder = CDREncoder()
        try response.encode(to: encoder)
        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try SetBoolSrv.Response(from: decoder)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.message, "applied")
    }

    func testServiceTypeInfoConsistency() {
        XCTAssertEqual(EmptySrv.typeInfo.serviceName, "std_srvs/srv/Empty")
        XCTAssertEqual(EmptySrv.typeInfo.requestTypeName, "std_srvs/srv/Empty_Request")
        XCTAssertEqual(EmptySrv.typeInfo.responseTypeName, "std_srvs/srv/Empty_Response")

        XCTAssertEqual(TriggerSrv.typeInfo.serviceName, "std_srvs/srv/Trigger")
        XCTAssertEqual(SetBoolSrv.typeInfo.serviceName, "std_srvs/srv/SetBool")
    }
}
