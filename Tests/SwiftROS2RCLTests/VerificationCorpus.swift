#if SWIFT_ROS2_RCL
    import SwiftROS2

    /// Deterministic message fixtures for the verification corpus (design §2.1).
    /// The large-payload member is CompressedImage (bundled on RCL; the type
    /// Conduit actually publishes).
    enum VerificationCorpus {
        static func imu() -> Imu {
            Imu(
                header: Header(stamp: Time(sec: 7, nanosec: 13), frameId: "bench"),
                orientation: Quaternion(x: 0.1, y: 0.2, z: 0.3, w: 0.4),
                orientationCovariance: [0, 1, 2, 3, 4, 5, 6, 7, 8],
                angularVelocity: Vector3(x: 1.5, y: 2.5, z: 3.5),
                angularVelocityCovariance: [9, 10, 11, 12, 13, 14, 15, 16, 17],
                linearAcceleration: Vector3(x: 9.8, y: 0.0, z: -9.8),
                linearAccelerationCovariance: [18, 19, 20, 21, 22, 23, 24, 25, 26])
        }

        static func compressedImage(byteCount: Int) -> CompressedImage {
            CompressedImage(
                header: Header(stamp: Time(sec: 7, nanosec: 13), frameId: "bench"),
                format: "jpeg",
                data: (0..<byteCount).map { UInt8($0 & 0xFF) })
        }

        static func image(width: UInt32, height: UInt32) -> Image {
            let step = width * 3  // rgb8
            let byteCount = Int(step) * Int(height)
            return Image(
                header: Header(stamp: Time(sec: 7, nanosec: 13), frameId: "bench"),
                height: height, width: width,
                encoding: "rgb8", isBigendian: 0, step: step,
                data: (0..<byteCount).map { UInt8($0 & 0xFF) })
        }

        static func cameraInfo() -> CameraInfo {
            CameraInfo(
                header: Header(stamp: Time(sec: 7, nanosec: 13), frameId: "bench"),
                height: 480, width: 640,
                distortionModel: "plumb_bob",
                d: [0.1, -0.2, 0.003, -0.004, 0.05],
                k: (0..<9).map { Double($0) + 0.5 },
                r: (0..<9).map { Double($0) - 4.0 },
                p: (0..<12).map { Double($0) * 1.25 },
                binningX: 2, binningY: 4,
                roi: RegionOfInterest(
                    xOffset: 8, yOffset: 16, height: 240, width: 320, doRectify: true))
        }

        /// `width` points × 16-byte step (x,y,z float32 + 4-byte pad).
        /// 10_000 → 160 KB; 60_000 → ~0.96 MB (LiDAR scan scale).
        static func pointCloud2(width: UInt32) -> PointCloud2 {
            let step: UInt32 = 16
            let byteCount = Int(width) * Int(step)
            return PointCloud2(
                header: Header(stamp: Time(sec: 7, nanosec: 13), frameId: "bench"),
                height: 1, width: width,
                fields: [
                    PointField(name: "x", offset: 0, datatype: 7, count: 1),
                    PointField(name: "y", offset: 4, datatype: 7, count: 1),
                    PointField(name: "z", offset: 8, datatype: 7, count: 1),
                ],
                isBigendian: false, pointStep: step, rowStep: width * step,
                data: (0..<byteCount).map { UInt8($0 & 0xFF) }, isDense: true)
        }
    }
#endif
