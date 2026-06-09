import CRclBridge
import Foundation

/// Canonical RIHS01 type-hash string for `rosTypeName` (e.g. "sensor_msgs/msg/Imu"),
/// or `nil` if the bundled type support carries no hash (spec risk R2).
package func rclTypeHash(_ rosTypeName: String) -> String? {
    var buf = [CChar](repeating: 0, count: 128)
    let rc = buf.withUnsafeMutableBufferPointer { p in
        crcl_type_hash(rosTypeName, p.baseAddress, p.count)
    }
    return rc == 0 ? String(cString: buf) : nil
}
