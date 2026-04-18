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

`CZenohPico` and `CCycloneDDS` are binaryTargets on Apple platforms and
system-library / source targets on Linux.
