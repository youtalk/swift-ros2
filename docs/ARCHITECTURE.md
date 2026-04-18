# Architecture

swift-ros2 publishes and subscribes to ROS 2 topics without the rcl/rclcpp stack.
It speaks the wire protocols directly:

- **Zenoh path** (rmw_zenoh_cpp compatible): zenoh-pico C library, wrapped by `CZenohBridge`, exposed to Swift via `SwiftROS2Zenoh` module.
- **DDS path** (rmw_cyclonedds_cpp compatible): CycloneDDS C library, wrapped by `CDDSBridge`, exposed to Swift via `SwiftROS2DDS` module.

Both paths implement `ZenohClientProtocol` / `DDSClientProtocol` which `SwiftROS2Transport`
uses to drive publishers and subscribers. The protocols remain public so callers can
inject mocks for unit testing.

## Target graph

    SwiftROS2 (public API: Context, Node, Publisher, Subscription)
     ├── SwiftROS2Messages
     ├── SwiftROS2Wire
     ├── SwiftROS2Transport
     ├── SwiftROS2Zenoh    ─── CZenohBridge ─── CZenohPico
     └── SwiftROS2DDS      ─── CDDSBridge   ─── CCycloneDDS

In the current Phase 1 build, `CZenohPico` and `CCycloneDDS` are exposed as
`systemLibrary` targets. On Apple platforms, linkage is provided via `pkg-config`
plus locally staged static `.a` libraries (populated by
`Scripts/bootstrap-maccatalyst.sh`). On Linux, they resolve against the
system-installed zenoh-pico / CycloneDDS (or source builds produced by
`Scripts/build-linux-deps.sh`). A platform-specific `binaryTarget` setup can be
documented separately if adopted in Phase 2.
