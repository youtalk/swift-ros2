/// Opaque token returned by the three callback-registration methods on
/// `ROS2Node`. The handle is a value type that holds an id — the owning
/// `ParameterStore` retains the closure independently. Callbacks remain
/// active until you explicitly detach them via
/// `ROS2Node.removeParameterCallback(_:)`; dropping the handle does not
/// auto-unregister.
public struct ROS2ParameterCallbackHandle: Sendable, Hashable {
    /// Monotonic id assigned by the owning `ParameterStore`. Internal-
    /// visibility so test code in `@testable import SwiftROS2` can build
    /// handles directly without going through registration.
    let id: UInt64
}
