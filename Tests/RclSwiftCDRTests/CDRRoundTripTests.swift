// CDRRoundTripTests.swift
// Tests for CDR encoder/decoder round-trip correctness

import XCTest
@testable import RclSwiftCDR

final class CDRRoundTripTests: XCTestCase {

    // MARK: - Primitive Round-Trips

    func testUInt8RoundTrip() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeUInt8(42)
        encoder.writeUInt8(0)
        encoder.writeUInt8(255)

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readUInt8(), 42)
        XCTAssertEqual(try decoder.readUInt8(), 0)
        XCTAssertEqual(try decoder.readUInt8(), 255)
    }

    func testInt8RoundTrip() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeInt8(-128)
        encoder.writeInt8(0)
        encoder.writeInt8(127)

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readInt8(), -128)
        XCTAssertEqual(try decoder.readInt8(), 0)
        XCTAssertEqual(try decoder.readInt8(), 127)
    }

    func testBoolRoundTrip() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeBool(true)
        encoder.writeBool(false)

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readBool(), true)
        XCTAssertEqual(try decoder.readBool(), false)
    }

    func testUInt16RoundTrip() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeUInt16(12345)
        encoder.writeUInt16(0)
        encoder.writeUInt16(65535)

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readUInt16(), 12345)
        XCTAssertEqual(try decoder.readUInt16(), 0)
        XCTAssertEqual(try decoder.readUInt16(), 65535)
    }

    func testUInt32RoundTrip() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeUInt32(123456789)

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readUInt32(), 123456789)
    }

    func testInt32RoundTrip() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeInt32(-42)
        encoder.writeInt32(Int32.max)
        encoder.writeInt32(Int32.min)

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readInt32(), -42)
        XCTAssertEqual(try decoder.readInt32(), Int32.max)
        XCTAssertEqual(try decoder.readInt32(), Int32.min)
    }

    func testInt64RoundTrip() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeInt64(Int64.max)
        encoder.writeInt64(Int64.min)

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readInt64(), Int64.max)
        XCTAssertEqual(try decoder.readInt64(), Int64.min)
    }

    func testFloat32RoundTrip() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeFloat32(3.14)
        encoder.writeFloat32(-0.0)
        encoder.writeFloat32(.infinity)

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readFloat32(), 3.14, accuracy: 0.001)
        XCTAssertEqual(try decoder.readFloat32(), -0.0)
        XCTAssertEqual(try decoder.readFloat32(), .infinity)
    }

    func testFloat64RoundTrip() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeFloat64(3.141592653589793)
        encoder.writeFloat64(-1e-300)
        encoder.writeFloat64(.nan)

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readFloat64(), 3.141592653589793)
        XCTAssertEqual(try decoder.readFloat64(), -1e-300)
        XCTAssertTrue(try decoder.readFloat64().isNaN)
    }

    // MARK: - String Round-Trip

    func testStringRoundTrip() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeString("hello")
        encoder.writeString("")
        encoder.writeString("imu_link")

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readString(), "hello")
        XCTAssertEqual(try decoder.readString(), "")
        XCTAssertEqual(try decoder.readString(), "imu_link")
    }

    // MARK: - Array/Sequence Round-Trips

    func testFloat64ArrayRoundTrip() throws {
        let values = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeFloat64Array(values)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try decoder.readFloat64Array(count: 9)
        XCTAssertEqual(decoded, values)
    }

    func testFloat64SequenceRoundTrip() throws {
        let values = [1.5, 2.5, 3.5]

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeFloat64Sequence(values)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try decoder.readFloat64Sequence()
        XCTAssertEqual(decoded, values)
    }

    func testUInt8SequenceRoundTrip() throws {
        let data = Data([0x00, 0x01, 0xFF, 0x42, 0x88])

        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeUInt8Sequence(data)

        let decoder = try CDRDecoder(data: encoder.getData())
        let decoded = try decoder.readUInt8Sequence()
        XCTAssertEqual(decoded, data)
    }

    // MARK: - Alignment

    func testAlignmentAfterUInt8ThenUInt32() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeUInt8(1)
        encoder.writeUInt32(42)  // should auto-align to 4

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readUInt8(), 1)
        XCTAssertEqual(try decoder.readUInt32(), 42)
    }

    func testAlignmentAfterStringThenFloat64() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeString("hi")
        encoder.writeFloat64(9.81)  // should auto-align to 8

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readString(), "hi")
        XCTAssertEqual(try decoder.readFloat64(), 9.81)
    }

    // MARK: - Error Cases

    func testInvalidEncapsulationHeader() {
        let badData = Data([0x00, 0x00, 0x00, 0x00])
        XCTAssertThrowsError(try CDRDecoder(data: badData))
    }

    func testTooShortData() {
        let shortData = Data([0x00, 0x01])
        XCTAssertThrowsError(try CDRDecoder(data: shortData))
    }

    func testUnexpectedEndOfData() throws {
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeUInt8(1)  // only 1 byte of data

        let decoder = try CDRDecoder(data: encoder.getData())
        _ = try decoder.readUInt8()
        XCTAssertThrowsError(try decoder.readUInt32())  // not enough data
    }

    // MARK: - Complex Structure

    func testHeaderLikeStructure() throws {
        // Simulate std_msgs/Header: uint32 sec, uint32 nanosec, string frame_id
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        encoder.writeUInt32(1234567890)
        encoder.writeUInt32(500000000)
        encoder.writeString("imu_link")

        let decoder = try CDRDecoder(data: encoder.getData())
        XCTAssertEqual(try decoder.readUInt32(), 1234567890)
        XCTAssertEqual(try decoder.readUInt32(), 500000000)
        XCTAssertEqual(try decoder.readString(), "imu_link")
    }
}
