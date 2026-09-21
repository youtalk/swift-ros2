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
        /// Strict on every platform and every rmw backend: the bridge serializes
        /// every rmw_serialize / rcl_take output into a zero-filling rcutils
        /// allocator (`crcl__zeroing_allocator`, #162), so any alignment padding
        /// the serializer skips writing is deterministically zero rather than
        /// leftover heap garbage. That used to require two regimes — strict
        /// prefix-plus-zero-tail on Apple/cyclonedds, and a looser
        /// decode-and-re-encode normalization on Linux and the zenoh (Fast-CDR)
        /// variant, where padding was uninitialized heap memory. The zeroing
        /// allocator removed the platform-dependent non-determinism, so the
        /// strict check now applies everywhere.
        private func assertByteParity<M: CDREncodable & CDRDecodable & Equatable>(
            _ message: M, _ rcl: [UInt8], _ what: String
        ) throws {
            let wire = try wireEncode(message)
            XCTAssertGreaterThanOrEqual(
                rcl.count, wire.count, "\(what): rmw bytes shorter than wire bytes")
            // Strict on every platform: the bridge serializes into a zeroing
            // allocator (#162), so skipped alignment padding is deterministic.
            XCTAssertEqual(
                Array(rcl.prefix(wire.count)), wire,
                "\(what): CDR bytes diverge from rmw_serialize")
            XCTAssertTrue(
                rcl.dropFirst(wire.count).allSatisfy { $0 == 0 },
                "\(what): trailing rmw bytes are not zero padding")
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
