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
        /// CDR alignment padding is a don't-care region, and BOTH backends can
        /// leave it uninitialized: the zenoh variant serializes through
        /// Fast-CDR (fastrtps typesupport), and the cyclonedds variant
        /// (introspection typesupport) zeroes padding on Apple but leaves
        /// interior alignment padding as uninitialized heap garbage on Linux.
        /// So neither backend can be checked with strict byte equality across
        /// padding positions — parity is instead verified structurally: the
        /// rmw bytes are normalized through the pure-Swift codec first
        /// (decode → re-encode canonicalizes the padding), and the normalized
        /// form must match the wire bytes exactly. This is not a weaker check
        /// than strict equality — any real structural divergence (field
        /// order, alignment, lengths, endianness) still fails, because a
        /// misparse either throws, decodes to a different message, or
        /// re-encodes to different bytes; only the don't-care padding
        /// positions are given a pass.
        private func assertByteParity<M: CDREncodable & CDRDecodable & Equatable>(
            _ message: M, _ rcl: [UInt8], _ what: String
        ) throws {
            let wire = try wireEncode(message)
            XCTAssertGreaterThanOrEqual(
                rcl.count, wire.count, "\(what): rmw bytes shorter than wire bytes")
            let decoded = try M(from: CDRDecoder(data: Data(rcl.prefix(wire.count))))
            XCTAssertEqual(
                decoded, message, "\(what): rmw bytes decode to a different message")
            XCTAssertEqual(
                try wireEncode(decoded), wire,
                "\(what): normalized rmw bytes diverge from wire bytes")
            // Bytes beyond wire.count are uninitialized alignment padding
            // whose VALUES cannot be checked, but their LENGTH can: final
            // CDR alignment never exceeds 8 bytes. A longer tail means the
            // serializer emitted real data the decode above never
            // inspected — fail and show it.
            let tail = Array(rcl.dropFirst(wire.count))
            XCTAssertLessThanOrEqual(
                tail.count, 8,
                "\(what): rmw bytes carry a \(tail.count)-byte tail beyond the wire "
                    + "encoding — not alignment padding: \(tail.prefix(32))")
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

        func testImageByteParity() throws {
            // 640x480 rgb8 raw frame (~900 KB) — the R1 typed-marshal addition.
            let m = VerificationCorpus.image(width: 640, height: 480)
            try assertByteParity(m, rclSerializeImage(m), "Image 640x480 rgb8")
        }

        func testCameraInfoByteParity() throws {
            // Covers the float64[9]/[12] fixed arrays, the float64[] distortion
            // sequence, and the nested (non-Header) RegionOfInterest.
            let m = VerificationCorpus.cameraInfo()
            try assertByteParity(m, rclSerializeCameraInfo(m), "CameraInfo")
        }
    }
#endif
