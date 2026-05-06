/// Opaque token returned by the three callback-registration methods on
/// `ROS2Node`. The caller must keep the handle alive for as long as the
/// callback should remain active — letting it go out of scope detaches
/// the registration on the next store mutation.
///
/// Mirrors rclcpp's `OnSetParametersCallbackHandle::SharedPtr` pattern.
public struct ROS2ParameterCallbackHandle: Sendable, Hashable {
    /// Monotonic id assigned by the owning `ParameterStore`. Internal-
    /// visibility so test code in `@testable import SwiftROS2` can build
    /// handles directly without going through registration.
    let id: UInt64
}
