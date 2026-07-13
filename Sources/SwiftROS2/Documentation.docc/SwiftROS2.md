# ``SwiftROS2``

Native Swift client for ROS 2 over Zenoh, DDS, or the real `rcl` stack.

## Overview

SwiftROS2 publishes and subscribes to ROS 2 topics on iOS, iPadOS, macOS
(including Mac Catalyst), visionOS, Linux (x86_64, aarch64), Windows (x86_64),
and Android (arm64-v8a, x86_64). One public API fronts two backends:

- **Wire path** — pure-Swift XCDR v1 codec plus Zenoh / DDS wire codecs, with
  no `rcl`/`rclcpp` dependency. Speaks **Zenoh** (interoperates with
  `rmw_zenoh_cpp`, ships on every supported platform) and **DDS**
  (interoperates with `rmw_cyclonedds_cpp` on Apple platforms, Linux, and
  Windows; Android still pending).
- **RCL backend** — the real `rcl` + rmw stack, opt-in at build time via
  `SWIFT_ROS2_ENABLE_RCL=1`. On Apple platforms the rmw is baked into a
  prebuilt xcframework per build variant (`SWIFT_ROS2_RCL_RMW`); on Linux the
  library links the system ROS 2 install and selects the rmw at runtime from
  the transport type — `.zenoh` runs `rmw_zenoh_cpp`, `.dds` / `.rcl` run
  `rmw_cyclonedds_cpp`. The rmw choice is process-global on Linux, so one
  process serves one rmw at a time. Not available on Windows or Android.

The backend is selected per context through `TransportConfig` — the node,
publisher, subscription, service, action, and parameter APIs below are
identical on both.

## Topics

### Getting started

- <doc:GettingStartedZenoh>
- <doc:GettingStartedDDS>

### Reference

- <doc:WireFormat>
- <doc:Actions>

### Core types

- ``ROS2Context``
- ``ROS2Node``
- ``ROS2NodeOptions``
- ``ROS2Publisher``
- ``ROS2Subscription``
- ``QoSProfile``

### Services

- ``ROS2Service``
- ``ROS2Client``
- ``ServiceError``

### Actions

- ``ROS2ActionServer``
- ``ROS2ActionClient``
- ``ActionGoalHandle``
- ``ActionServerHandler``
- ``ActionResult``
- ``ActionGoalStatus``
- ``GoalResponse``
- ``CancelResponse``
- ``ActionError``

### Parameters

- ``ROS2Parameter``
- ``ROS2ParameterValue``
- ``ROS2ParameterType``
- ``ROS2ParameterDescriptor``
- ``ROS2ParameterClient``
- ``ROS2ParameterCallbackHandle``
- ``ROS2ParameterConvertible``
- ``ROS2ParameterError``
- ``ROS2SetParametersResult``
- ``ROS2ListParametersResult``
