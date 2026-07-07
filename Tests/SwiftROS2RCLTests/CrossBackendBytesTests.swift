#if SWIFT_ROS2_RCL
    import Foundation
    import SwiftROS2
    import SwiftROS2RCL
    import XCTest

    /// Axis 3 (correctness): the pure-Swift CDR encoder and the native RCL
    /// rmw_serialize path must emit identical on-wire CDR bytes for every
    /// corpus type. In-process, deterministic, no LINUX_IP, no transport.
    final class CrossBackendBytesTests: XCTestCase {
        /// Pure-Swift wire bytes: XCDR v1 LE with the 4-byte encapsulation header.
        private func wireEncode<M: CDREncodable>(_ msg: M) throws -> [UInt8] {
            let enc = CDREncoder(isLegacySchema: false)
            enc.writeEncapsulationHeader()
            try msg.encode(to: enc)
            return Array(enc.getData())
        }

        /// rmw_serialize may pad the buffer to an alignment boundary beyond the
        /// CDR message length; assert the meaningful prefix matches and any
        /// trailing bytes are ignorable padding. In practice every corpus
        /// message serializes to the same byte count on both paths (the tail is
        /// empty); the `rcl.count >= wire.count` tolerance is kept for future
        /// types where rmw might align-pad.
        ///
        /// The cyclonedds variant (introspection typesupport) zeroes alignment
        /// padding, so the comparison is strict byte equality. The zenoh
        /// variant serializes through Fast-CDR (fastrtps typesupport), which
        /// leaves alignment-padding bytes uninitialized — a CDR don't-care —
        /// so exact byte equality cannot hold at padding positions. There the
        /// rmw bytes are normalized through the pure-Swift codec first
        /// (decode → re-encode zeroes the padding) and the normalized form
        /// must match the wire bytes exactly; any structural divergence
        /// (field order, alignment, lengths, endianness) still fails because
        /// the decode misparses and the re-encoded bytes differ.
        private func assertByteParity<M: CDREncodable & CDRDecodable & Equatable>(
            _ message: M, _ rcl: [UInt8], _ what: String
        ) throws {
            let wire = try wireEncode(message)
            XCTAssertGreaterThanOrEqual(
                rcl.count, wire.count, "\(what): rmw bytes shorter than wire bytes")
            #if SWIFT_ROS2_RCL_RMW_ZENOH
                let decoded = try M(from: CDRDecoder(data: Data(rcl.prefix(wire.count))))
                XCTAssertEqual(
                    decoded, message, "\(what): rmw bytes decode to a different message")
                XCTAssertEqual(
                    try wireEncode(decoded), wire,
                    "\(what): normalized rmw bytes diverge from wire bytes")
            #else
                XCTAssertEqual(
                    Array(rcl.prefix(wire.count)), wire,
                    "\(what): CDR bytes diverge from rmw_serialize")
                XCTAssertTrue(
                    rcl.dropFirst(wire.count).allSatisfy { $0 == 0 },
                    "\(what): trailing rmw bytes are not zero padding")
            #endif
        }

        func testImuByteParity() throws {
            let m = VerificationCorpus.imu()
            try assertByteParity(m, rclSerializeImu(m), "Imu")
        }

        func testCompressedImageByteParity() throws {
            let m = VerificationCorpus.compressedImage(byteCount: 65_536)
            try assertByteParity(m, rclSerializeCompressedImage(m), "CompressedImage 64K")
        }

        func testPointCloud2ByteParity() throws {
            let m = VerificationCorpus.pointCloud2(width: 10_000)
            try assertByteParity(m, rclSerializePointCloud2(m), "PointCloud2 10k pts")
        }

        func testPointCloud2ByteParityLidarScale() throws {
            // ~0.96 MB: 60_000 points × 16 B step — LiDAR-scan scale.
            let m = VerificationCorpus.pointCloud2(width: 60_000)
            try assertByteParity(m, rclSerializePointCloud2(m), "PointCloud2 60k pts (~0.96 MB)")
        }

        func testCompressedImageByteParityRealSize() throws {
            // ~900 KB: representative of a 640x480 rgb8 frame's compressed payload.
            let m = VerificationCorpus.compressedImage(byteCount: 900_000)
            try assertByteParity(m, rclSerializeCompressedImage(m), "CompressedImage ~900 KB")
        }
    }
#endif
