# ``SwiftROS2``

Native Swift client for ROS 2 over Zenoh or DDS, no `rcl`/`rclcpp`.

## Overview

SwiftROS2 publishes and subscribes to ROS 2 topics directly at the wire level
on iOS, iPadOS, macOS (including Mac Catalyst), visionOS, Linux (x86_64,
aarch64), Windows (x86_64), and Android (arm64-v8a, x86_64). It speaks two
transports natively:

- **Zenoh** — interoperates with `rmw_zenoh_cpp`. Ships on every supported platform.
- **DDS** — interoperates with `rmw_cyclonedds_cpp`. Apple platforms, Linux, and Windows (Android still pending).

## Topics

### Getting started

- <doc:GettingStartedZenoh>
- <doc:GettingStartedDDS>

### Reference

- <doc:WireFormat>

### Core types

- ``ROS2Context``
- ``ROS2Node``
- ``ROS2Publisher``
- ``ROS2Subscription``
- ``QoSProfile``
