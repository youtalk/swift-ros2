// RclImuMarshal.swift
// M2: hand-written sensor_msgs/Imu marshalling for the RCL serialization-
// validation gate. Unpacks an `Imu` value into the flat `crcl_serialize_imu`
// FFI (the C side builds the C struct and runs the real rmw_serialize), and
// wraps `crcl_type_hash`. Validation-only — not on the production publish path.

import CRclBridge
import Foundation
import SwiftROS2Messages

/// Serialize `imu` via the real ROS 2 introspection serializer (rmw_serialize),
/// returning the on-wire CDR bytes (incl. the 4-byte encapsulation header).
package func rclSerializeImu(_ imu: Imu) throws -> [UInt8] {
    precondition(imu.orientationCovariance.count == 9, "orientationCovariance needs 9 elements")
    precondition(imu.angularVelocityCovariance.count == 9, "angularVelocityCovariance needs 9 elements")
    precondition(
        imu.linearAccelerationCovariance.count == 9, "linearAccelerationCovariance needs 9 elements")

    var outBuf: UnsafeMutablePointer<UInt8>?
    var outLen: Int = 0
    let rc: Int32 = imu.orientationCovariance.withUnsafeBufferPointer { oc in
        imu.angularVelocityCovariance.withUnsafeBufferPointer { ac in
            imu.linearAccelerationCovariance.withUnsafeBufferPointer { lc in
                crcl_serialize_imu(
                    imu.header.stamp.sec, imu.header.stamp.nanosec, imu.header.frameId,
                    imu.orientation.x, imu.orientation.y, imu.orientation.z, imu.orientation.w,
                    oc.baseAddress,
                    imu.angularVelocity.x, imu.angularVelocity.y, imu.angularVelocity.z,
                    ac.baseAddress,
                    imu.linearAcceleration.x, imu.linearAcceleration.y, imu.linearAcceleration.z,
                    lc.baseAddress,
                    &outBuf, &outLen)
            }
        }
    }
    guard rc == 0, let outBuf else {
        throw TransportError.publishFailed(String(cString: crcl_last_error()))
    }
    defer { crcl_free(outBuf) }
    return Array(UnsafeBufferPointer(start: outBuf, count: outLen))
}

/// Canonical RIHS01 type-hash string for `rosTypeName` (e.g. "sensor_msgs/msg/Imu"),
/// or `nil` if the bundled type support carries no hash (spec risk R2).
package func rclTypeHash(_ rosTypeName: String) -> String? {
    var buf = [CChar](repeating: 0, count: 128)
    let rc = buf.withUnsafeMutableBufferPointer { p in
        crcl_type_hash(rosTypeName, p.baseAddress, p.count)
    }
    return rc == 0 ? String(cString: buf) : nil
}
