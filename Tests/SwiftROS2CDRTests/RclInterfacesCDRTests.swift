import Foundation
import XCTest

@testable import SwiftROS2CDR
@testable import SwiftROS2Messages

final class RclInterfacesCDRTests: XCTestCase {

    func testParameterValueAllVariants() throws {
        let cases: [ParameterValue] = [
            ParameterValue(type: ParameterType.PARAMETER_BOOL, boolValue: true),
            ParameterValue(type: ParameterType.PARAMETER_INTEGER, integerValue: -42),
            ParameterValue(type: ParameterType.PARAMETER_DOUBLE, doubleValue: 3.14),
            ParameterValue(type: ParameterType.PARAMETER_STRING, stringValue: "hello"),
            ParameterValue(type: ParameterType.PARAMETER_BYTE_ARRAY, byteArrayValue: [0xAA, 0xBB, 0xCC]),
            ParameterValue(type: ParameterType.PARAMETER_BOOL_ARRAY, boolArrayValue: [true, false, true]),
            ParameterValue(type: ParameterType.PARAMETER_INTEGER_ARRAY, integerArrayValue: [1, 2, 3]),
            ParameterValue(type: ParameterType.PARAMETER_DOUBLE_ARRAY, doubleArrayValue: [1.5, 2.5, 3.5]),
            ParameterValue(type: ParameterType.PARAMETER_STRING_ARRAY, stringArrayValue: ["a", "b", "c"]),
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
            type: ParameterType.PARAMETER_DOUBLE,
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

    func testParameterDescriptorWithRanges() throws {
        let original = ParameterDescriptor(
            name: "rate",
            type: ParameterType.PARAMETER_DOUBLE,
            description: "",
            additionalConstraints: "",
            readOnly: true,
            dynamicTyping: true,
            floatingPointRange: [FloatingPointRange(fromValue: 0.0, toValue: 100.0, step: 0.5)],
            integerRange: [IntegerRange(fromValue: 0, toValue: 100, step: 1)]
        )
        let bytes = try roundTripEncode(original)
        let decoded = try roundTripDecode(ParameterDescriptor.self, from: bytes)
        XCTAssertEqual(decoded, original)
    }

    func testParameterDescriptorRejectsOversizedRangeOnDecode() throws {
        // Hand-craft a ParameterDescriptor wire payload whose floating_point_range
        // declares 2 elements (above the IDL <=1 bound) and confirm the generated
        // decoder rejects it. Encoding the same value would precondition-fail —
        // so we go through CDREncoder primitives directly.
        let encoder = CDREncoder(isLegacySchema: false)
        encoder.writeEncapsulationHeader()
        encoder.writeString("name")
        encoder.writeUInt8(ParameterType.PARAMETER_DOUBLE)
        encoder.writeString("")
        encoder.writeString("")
        encoder.writeBool(false)
        encoder.writeBool(false)
        // Two FloatingPointRange entries — out of spec.
        encoder.writeUInt32(2)
        for _ in 0..<2 {
            encoder.writeFloat64(0)
            encoder.writeFloat64(1)
            encoder.writeFloat64(0.1)
        }
        encoder.writeUInt32(0)  // empty integer_range
        let bytes = encoder.getData()

        XCTAssertThrowsError(try roundTripDecode(ParameterDescriptor.self, from: bytes)) { error in
            guard case CDRDecodingError.sequenceTooLarge = error else {
                XCTFail("expected sequenceTooLarge, got \(error)")
                return
            }
        }
    }

    func testParameterRoundTrip() throws {
        let original = Parameter(
            name: "node_name",
            value: ParameterValue(type: ParameterType.PARAMETER_STRING, stringValue: "swift_node")
        )
        let bytes = try roundTripEncode(original)
        let decoded = try roundTripDecode(Parameter.self, from: bytes)
        XCTAssertEqual(decoded, original)
    }

    func testParameterEventRoundTrip() throws {
        let stamp = Time(sec: 1_234, nanosec: 567_000_000)
        let p = Parameter(
            name: "x",
            value: ParameterValue(type: ParameterType.PARAMETER_INTEGER, integerValue: 7)
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

    func testParameterEventDescriptorsRoundTrip() throws {
        let descriptor = ParameterDescriptor(
            name: "x", type: ParameterType.PARAMETER_INTEGER,
            description: "", additionalConstraints: "",
            readOnly: false, dynamicTyping: false,
            floatingPointRange: [], integerRange: []
        )
        let original = ParameterEventDescriptors(
            newParameters: [descriptor],
            changedParameters: [],
            deletedParameters: []
        )
        let bytes = try roundTripEncode(original)
        let decoded = try roundTripDecode(ParameterEventDescriptors.self, from: bytes)
        XCTAssertEqual(decoded, original)
    }

    func testListParametersResultRoundTrip() throws {
        let original = ListParametersResult(
            names: ["rate", "frame_id"],
            prefixes: ["sensor", "imu"]
        )
        let bytes = try roundTripEncode(original)
        let decoded = try roundTripDecode(ListParametersResult.self, from: bytes)
        XCTAssertEqual(decoded, original)
    }

    func testParameterTypeRoundTrip() throws {
        // ParameterType is an enum-like message with only static constants — its
        // CDR payload is empty. Round-tripping it confirms encode/decode are
        // wired and exercises the constants in this PR.
        let original = ParameterType()
        let bytes = try roundTripEncode(original)
        let decoded = try roundTripDecode(ParameterType.self, from: bytes)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(ParameterType.PARAMETER_NOT_SET, 0)
        XCTAssertEqual(ParameterType.PARAMETER_STRING_ARRAY, 9)
    }

    func testGetParametersServiceRoundTrip() throws {
        let request = GetParametersRequest(names: ["rate", "frame_id"])
        let response = GetParametersResponse(values: [
            ParameterValue(type: ParameterType.PARAMETER_DOUBLE, doubleValue: 100.0),
            ParameterValue(type: ParameterType.PARAMETER_STRING, stringValue: "imu_link"),
        ])
        let reqBytes = try roundTripEncode(request)
        XCTAssertEqual(try roundTripDecode(GetParametersRequest.self, from: reqBytes), request)
        let resBytes = try roundTripEncode(response)
        XCTAssertEqual(try roundTripDecode(GetParametersResponse.self, from: resBytes), response)
    }

    func testGetParameterTypesServiceRoundTrip() throws {
        let request = GetParameterTypesRequest(names: ["rate"])
        let response = GetParameterTypesResponse(types: [ParameterType.PARAMETER_DOUBLE])
        let reqBytes = try roundTripEncode(request)
        XCTAssertEqual(try roundTripDecode(GetParameterTypesRequest.self, from: reqBytes), request)
        let resBytes = try roundTripEncode(response)
        XCTAssertEqual(try roundTripDecode(GetParameterTypesResponse.self, from: resBytes), response)
    }

    func testListParametersServiceRoundTrip() throws {
        let request = ListParametersRequest(prefixes: ["sensor"], depth: 2)
        let response = ListParametersResponse(
            result: ListParametersResult(names: ["sensor.rate"], prefixes: ["sensor"])
        )
        let reqBytes = try roundTripEncode(request)
        XCTAssertEqual(try roundTripDecode(ListParametersRequest.self, from: reqBytes), request)
        let resBytes = try roundTripEncode(response)
        XCTAssertEqual(try roundTripDecode(ListParametersResponse.self, from: resBytes), response)
    }

    func testDescribeParametersServiceRoundTrip() throws {
        let descriptor = ParameterDescriptor(
            name: "rate", type: ParameterType.PARAMETER_DOUBLE,
            description: "", additionalConstraints: "",
            readOnly: false, dynamicTyping: false,
            floatingPointRange: [], integerRange: []
        )
        let request = DescribeParametersRequest(names: ["rate"])
        let response = DescribeParametersResponse(descriptors: [descriptor])
        let reqBytes = try roundTripEncode(request)
        XCTAssertEqual(try roundTripDecode(DescribeParametersRequest.self, from: reqBytes), request)
        let resBytes = try roundTripEncode(response)
        XCTAssertEqual(try roundTripDecode(DescribeParametersResponse.self, from: resBytes), response)
    }

    func testSetParametersServiceRoundTrip() throws {
        let request = SetParametersRequest(parameters: [
            Parameter(
                name: "rate",
                value: ParameterValue(type: ParameterType.PARAMETER_DOUBLE, doubleValue: 100.0)
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

    func testSetParametersAtomicallyServiceRoundTrip() throws {
        let request = SetParametersAtomicallyRequest(parameters: [
            Parameter(
                name: "rate",
                value: ParameterValue(type: ParameterType.PARAMETER_DOUBLE, doubleValue: 50.0)
            )
        ])
        let response = SetParametersAtomicallyResponse(
            result: SetParametersResult(successful: false, reason: "out of range")
        )
        let reqBytes = try roundTripEncode(request)
        XCTAssertEqual(
            try roundTripDecode(SetParametersAtomicallyRequest.self, from: reqBytes), request)
        let resBytes = try roundTripEncode(response)
        XCTAssertEqual(
            try roundTripDecode(SetParametersAtomicallyResponse.self, from: resBytes), response)
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
