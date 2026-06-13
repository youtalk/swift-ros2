#if SWIFT_ROS2_RCL
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
        /// trailing bytes are zero padding. In practice every corpus message
        /// serializes to the same byte count on both paths (the tail is empty);
        /// the `rcl.count >= wire.count` tolerance is kept for future types
        /// where rmw might align-pad.
        private func assertByteParity(_ wire: [UInt8], _ rcl: [UInt8], _ what: String) {
            XCTAssertGreaterThanOrEqual(
                rcl.count, wire.count, "\(what): rmw bytes shorter than wire bytes")
            XCTAssertEqual(
                Array(rcl.prefix(wire.count)), wire, "\(what): CDR bytes diverge from rmw_serialize")
            XCTAssertTrue(
                rcl.dropFirst(wire.count).allSatisfy { $0 == 0 },
                "\(what): trailing rmw bytes are not zero padding")
        }

        func testImuByteParity() throws {
            let m = VerificationCorpus.imu()
            try assertByteParity(wireEncode(m), rclSerializeImu(m), "Imu")
        }

        func testCompressedImageByteParity() throws {
            let m = VerificationCorpus.compressedImage(byteCount: 65_536)
            try assertByteParity(
                wireEncode(m), rclSerializeCompressedImage(m), "CompressedImage 64K")
        }

        func testPointCloud2ByteParity() throws {
            let m = VerificationCorpus.pointCloud2(width: 10_000)
            try assertByteParity(
                wireEncode(m), rclSerializePointCloud2(m), "PointCloud2 10k pts")
        }
    }
#endif
