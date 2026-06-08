// crcl-golden — M2 serialization-validation gate.
//
// Builds a fixed sensor_msgs/Imu, then asserts:
//   1. SwiftROS2CDR wire bytes == real ROS 2 introspection serialization
//      (rmw_serialize, via rclSerializeImu) — byte-for-byte.
//   2. Imu.typeInfo.typeHash == crcl_type_hash (when available; spec risk R2).
// Prints "crcl_golden OK: …" + flush on success, then exits 0. On a byte
// mismatch it prints a diff and exits 1. Run by ci-rcl, SIGALRM-bounded, with
// success decided on the OK line (consistent with crcl-smoke).

import Foundation
import SwiftROS2
import SwiftROS2RCL

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

/// Assert SwiftROS2CDR wire bytes == real ROS 2 introspection serialization
/// (rmw_serialize) byte-for-byte, plus the type-hash gate when available.
/// Prints "crcl_golden OK: \(name) …" on success; on any mismatch prints a
/// diff and exits 1.
func goldenCheck<T: ROS2Message>(_ name: String, _ value: T, _ rclSerialize: (T) throws -> [UInt8]) {
    let enc = CDREncoder(isLegacySchema: false)
    enc.writeEncapsulationHeader()
    do { try value.encode(to: enc) } catch {
        print("crcl_golden FAIL: \(name) encode threw: \(error)")
        exit(1)
    }
    let wire = [UInt8](enc.getData())
    let rcl: [UInt8]
    do { rcl = try rclSerialize(value) } catch {
        print("crcl_golden FAIL: \(name) rclSerialize threw: \(error)")
        exit(1)
    }
    guard wire == rcl else {
        print("crcl_golden FAIL: \(name) byte mismatch (wire \(wire.count)B vs rcl \(rcl.count)B)")
        print("  wire: \(hex(wire))")
        print("  rcl : \(hex(rcl))")
        exit(1)
    }
    if let h = rclTypeHash(T.typeInfo.typeName) {
        guard h == T.typeInfo.typeHash else {
            print("crcl_golden FAIL: \(name) type hash mismatch")
            print("  swift: \(T.typeInfo.typeHash)")
            print("  rcl  : \(h)")
            exit(1)
        }
    }
    print("crcl_golden OK: \(name) (\(wire.count) bytes)")
}

// Fixed, fully finite Imu so the byte compare is deterministic.
let imu = Imu(
    header: Header(stamp: Time(sec: 1234, nanosec: 567_890_000), frameId: "imu_link"),
    orientation: Quaternion(x: 0.1, y: 0.2, z: 0.3, w: 0.4),
    orientationCovariance: [0, 1, 2, 3, 4, 5, 6, 7, 8],
    angularVelocity: Vector3(x: 1.5, y: 2.5, z: 3.5),
    angularVelocityCovariance: [9, 10, 11, 12, 13, 14, 15, 16, 17],
    linearAcceleration: Vector3(x: 9.8, y: 0.0, z: -9.8),
    linearAccelerationCovariance: [18, 19, 20, 21, 22, 23, 24, 25, 26]
)

// 1. Wire bytes via the production SwiftROS2CDR path (Jazzy is non-legacy).
let encoder = CDREncoder(isLegacySchema: false)
encoder.writeEncapsulationHeader()
do {
    try imu.encode(to: encoder)
} catch {
    print("crcl_golden FAIL: SwiftROS2CDR encode threw: \(error)")
    exit(1)
}
let wire = [UInt8](encoder.getData())

// 2. Real ROS 2 introspection serialization via rmw_serialize.
let rcl: [UInt8]
do {
    rcl = try rclSerializeImu(imu)
} catch {
    print("crcl_golden FAIL: rclSerializeImu threw: \(error)")
    exit(1)
}

guard wire == rcl else {
    print("crcl_golden FAIL: byte mismatch (wire \(wire.count)B vs rcl \(rcl.count)B)")
    print("  wire: \(hex(wire))")
    print("  rcl : \(hex(rcl))")
    exit(1)
}

// 3. Type-hash gate (hard when available; R2 fallback = warn + continue).
if let h = rclTypeHash("sensor_msgs/msg/Imu") {
    guard h == Imu.typeInfo.typeHash else {
        print("crcl_golden FAIL: type hash mismatch")
        print("  swift: \(Imu.typeInfo.typeHash)")
        print("  rcl  : \(h)")
        exit(1)
    }
} else {
    print("crcl_golden WARN: type hash unavailable from handle (R2) — byte gate only")
}

print("crcl_golden OK: SwiftROS2CDR == rmw_serialize for sensor_msgs/Imu (\(wire.count) bytes)")

// M3b T4 — scalar-sequence + heap-string fixtures (finite values only).
goldenCheck(
    "sensor_msgs/Joy",
    Joy(
        header: Header(stamp: Time(sec: 7, nanosec: 8), frameId: "joy"),
        axes: [0.0, 0.5, -0.5, 1.0],
        buttons: [0, 1, 0, 1, 1]
    ),
    rclSerializeJoy)

goldenCheck(
    "sensor_msgs/BatteryState",
    BatteryState(
        header: Header(stamp: Time(sec: 1, nanosec: 2), frameId: "bat"),
        voltage: 12.6, temperature: 25.0, current: -1.2, charge: 3.0, capacity: 4.0,
        designCapacity: 5.0, percentage: 0.75, powerSupplyStatus: 1, powerSupplyHealth: 1,
        powerSupplyTechnology: 2, present: true,
        cellVoltage: [4.2, 4.2, 4.1], cellTemperature: [25.0, 25.5],
        location: "slot0", serialNumber: "SN-123"
    ),
    rclSerializeBatteryState)

goldenCheck(
    "sensor_msgs/CompressedImage",
    CompressedImage(
        header: Header(stamp: Time(sec: 3, nanosec: 4), frameId: "cam"),
        format: "jpeg", data: [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]
    ),
    rclSerializeCompressedImage)

// M3b T5 — PointField[] struct sequence (SoA) + per-element heap string + uint8 sequence.
goldenCheck(
    "sensor_msgs/PointCloud2",
    PointCloud2(
        header: Header(stamp: Time(sec: 9, nanosec: 10), frameId: "lidar"),
        height: 1, width: 2,
        fields: [
            PointField(name: "x", offset: 0, datatype: 7, count: 1),
            PointField(name: "y", offset: 4, datatype: 7, count: 1),
            PointField(name: "z", offset: 8, datatype: 7, count: 1),
        ],
        isBigendian: false, pointStep: 12, rowStep: 24,
        data: Array(0..<24).map { UInt8($0) }, isDense: true
    ),
    rclSerializePointCloud2)

fflush(stdout)
exit(0)
