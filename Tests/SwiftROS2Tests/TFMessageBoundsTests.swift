// TFMessageBoundsTests.swift
// TFMessage decodes raw network bytes on the /tf subscribe path — a hostile
// or corrupt sample must be rejected by the sequence-count DoS cap
// (CDRDecoder.readSequenceCount), never reach reserveCapacity with a
// wire-controlled count.

import SwiftROS2CDR
import SwiftROS2Messages
import XCTest

final class TFMessageBoundsTests: XCTestCase {
    func testDecodeRejectsOversizedTransformCount() throws {
        // Encapsulation header + count = 0xFFFFFFFF and nothing else. The
        // decode must fail on the sequence-count cap BEFORE reserving any
        // capacity — failing later on exhausted input would mean the
        // wire-controlled count already reached reserveCapacity (a ~412 GB
        // virtual reservation; jetsam-fatal on iOS).
        let data = Data([0x00, 0x01, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF])
        let decoder = try CDRDecoder(data: data)
        XCTAssertThrowsError(try TFMessage(from: decoder)) { error in
            guard case CDRDecodingError.sequenceTooLarge = error else {
                return XCTFail("expected sequenceTooLarge, got \(error)")
            }
        }
    }

    func testRoundTripSurvivesBoundsGuard() throws {
        let msg = TFMessage(transforms: [
            TransformStamped(
                header: Header(sec: 1, nanosec: 2, frameId: "map"),
                childFrameId: "base_link",
                transform: Transform(
                    translation: Vector3(x: 1.5, y: -2.5, z: 0.25),
                    rotation: Quaternion(x: 0, y: 0, z: 0.7071, w: 0.7071))),
            TransformStamped(
                header: Header(sec: 3, nanosec: 4, frameId: "odom"),
                childFrameId: "laser",
                transform: Transform(
                    translation: Vector3(x: 0, y: 0, z: 1),
                    rotation: Quaternion(x: 0, y: 0, z: 0, w: 1))),
        ])
        let encoder = CDREncoder()
        encoder.writeEncapsulationHeader()
        try msg.encode(to: encoder)
        let decoded = try TFMessage(from: CDRDecoder(data: encoder.getData()))
        XCTAssertEqual(decoded.transforms, msg.transforms)
    }
}
