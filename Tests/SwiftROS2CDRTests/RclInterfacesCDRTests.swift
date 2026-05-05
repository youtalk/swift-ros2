import Foundation
import XCTest

@testable import SwiftROS2CDR
@testable import SwiftROS2Messages

final class RclInterfacesCDRTests: XCTestCase {

    func testParameterValueAllVariants() throws {
        let cases: [ParameterValue] = [
            ParameterValue(type: 1, boolValue: true),
            ParameterValue(type: 2, integerValue: -42),
            ParameterValue(type: 3, doubleValue: 3.14),
            ParameterValue(type: 4, stringValue: "hello"),
            ParameterValue(type: 5, byteArrayValue: [0xAA, 0xBB, 0xCC]),
            ParameterValue(type: 6, boolArrayValue: [true, false, true]),
            ParameterValue(type: 7, integerArrayValue: [1, 2, 3]),
            ParameterValue(type: 8, doubleArrayValue: [1.5, 2.5, 3.5]),
            ParameterValue(type: 9, stringArrayValue: ["a", "b", "c"]),
        ]
        for original in cases {
            let bytes = try roundTripEncode(original)
            let decoded = try roundTripDecode(ParameterValue.self, from: bytes)
            XCTAssertEqual(decoded, original)
        }
    }

    func testParameterDescriptorEmptyRanges() throws {
        let original = ParameterDescriptor(
            name: "rate",
            type: 3,
            description: "publish rate in Hz",
            additionalConstraints: "must be > 0",
            readOnly: false,
            dynamicTyping: false,
            floatingPointRange: [],
            integerRange: []
        )
        let bytes = try roundTripEncode(original)
        let decoded = try roundTripDecode(ParameterDescriptor.self, from: bytes)
        XCTAssertEqual(decoded, original)
    }

    func testParameterRoundTrip() throws {
        let original = Parameter(
            name: "node_name",
            value: ParameterValue(type: 4, stringValue: "swift_node")
        )
        let bytes = try roundTripEncode(original)
        let decoded = try roundTripDecode(Parameter.self, from: bytes)
        XCTAssertEqual(decoded, original)
    }

    func testParameterEventRoundTrip() throws {
        let stamp = Time(sec: 1_234, nanosec: 567_000_000)
        let p = Parameter(
            name: "x",
            value: ParameterValue(type: 2, integerValue: 7)
        )
        let original = ParameterEvent(
            stamp: stamp,
            node: "/swift_node",
            newParameters: [p],
            changedParameters: [],
            deletedParameters: []
        )
        let bytes = try roundTripEncode(original)
        let decoded = try roundTripDecode(ParameterEvent.self, from: bytes)
        XCTAssertEqual(decoded, original)
    }

    func testSetParametersServiceRoundTrip() throws {
        let request = SetParametersRequest(parameters: [
            Parameter(
                name: "rate",
                value: ParameterValue(type: 3, doubleValue: 100.0)
            )
        ])
        let response = SetParametersResponse(results: [
            SetParametersResult(successful: true, reason: "")
        ])
        let reqBytes = try roundTripEncode(request)
        XCTAssertEqual(try roundTripDecode(SetParametersRequest.self, from: reqBytes), request)
        let resBytes = try roundTripEncode(response)
        XCTAssertEqual(try roundTripDecode(SetParametersResponse.self, from: resBytes), response)
    }

    // MARK: - helpers

    private func roundTripEncode<M: ROS2Message>(_ value: M) throws -> Data {
        let encoder = CDREncoder(isLegacySchema: false)
        encoder.writeEncapsulationHeader()
        try value.encode(to: encoder)
        return encoder.getData()
    }

    private func roundTripDecode<M: ROS2Message>(_ type: M.Type, from bytes: Data) throws -> M {
        let decoder = try CDRDecoder(data: bytes, isLegacySchema: false)
        return try M(from: decoder)
    }
}
