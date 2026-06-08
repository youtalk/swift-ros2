// RclTypedPublishable.swift
// A message that can be published via the real-rcl typed path (rcl_publish over
// a marshalled rosidl C struct), instead of the byte-oriented serialized seam.
//
// C-free on purpose: this protocol lives in SwiftROS2Transport so ROS2Publisher
// (SwiftROS2) and RclTransportPublisher (here) can both refer to it. The actual
// conformances are emitted into the gated SwiftROS2RCL target (which imports
// CRclBridge) — a type is typed-publishable iff SwiftROS2RCL is linked AND a
// conformance exists for it. Types without a conformance (AudioData,
// CompressedPointCloud2, anything on Zenoh/wire-DDS) fall back to the byte seam.

/// A message whose Swift value can be marshalled into its rosidl C struct and
/// published through `rcl_publish` by an `RclTransportPublisher`.
package protocol RclTypedPublishable: Sendable {
    /// Marshal `self` into its C struct and publish it through `handle`.
    /// Implemented in SwiftROS2RCL (imports CRclBridge); the body downcasts
    /// `handle` to the concrete publisher box and calls the per-type C marshaller.
    func rclTypedPublish(into handle: any RclPublisherHandle) throws
}
