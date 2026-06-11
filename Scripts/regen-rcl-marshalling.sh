#!/usr/bin/env bash
# Regenerate the native-RCL marshalling (C + Swift) for the M3b/M3c type set,
# the M7 service typesupport registry, the M8 action typesupport registry,
# and the registry-only message entries.
# Run from the repo root. The same invocation backs the ci-rcl drift guard.
set -euo pipefail
TYPES="Imu,Joy,BatteryState,CompressedImage,PointCloud2,MagneticField,FluidPressure,Illuminance,NavSatFix,Range,Temperature"
# M7 (spec section 20.3) service set: the six rcl_interfaces parameter
# services, std_srvs, example_interfaces/AddTwoInts, sensor_msgs/SetCameraInfo,
# and action_msgs/CancelGoal (M8 prep).
SRV_TYPES="rcl_interfaces/srv/DescribeParameters"
SRV_TYPES+=",rcl_interfaces/srv/GetParameterTypes"
SRV_TYPES+=",rcl_interfaces/srv/GetParameters"
SRV_TYPES+=",rcl_interfaces/srv/ListParameters"
SRV_TYPES+=",rcl_interfaces/srv/SetParameters"
SRV_TYPES+=",rcl_interfaces/srv/SetParametersAtomically"
SRV_TYPES+=",std_srvs/srv/Empty"
SRV_TYPES+=",std_srvs/srv/SetBool"
SRV_TYPES+=",std_srvs/srv/Trigger"
SRV_TYPES+=",example_interfaces/srv/AddTwoInts"
SRV_TYPES+=",sensor_msgs/srv/SetCameraInfo"
SRV_TYPES+=",action_msgs/srv/CancelGoal"
# M8 (spec section 20.6) action set: example_interfaces/Fibonacci is the only
# consumer (the in-process loopback gate + the ros2 action send_goal runbook).
ACTION_TYPES="example_interfaces/action/Fibonacci"
# Messages that get a typesupport entry without marshal functions (shapes that
# exceed the flattener; published over the serialized seam instead).
REGISTRY_ONLY_TYPES="rcl_interfaces/msg/ParameterEvent"
# unique_identifier_msgs is required for nested-reference resolution only
# (action_msgs/msg/GoalInfo -> unique_identifier_msgs/UUID).
swift run swift-ros2-gen --emit-rcl-marshalling \
  --input "sensor_msgs=vendor/common_interfaces-jazzy/sensor_msgs@jazzy" \
  --input "std_msgs=vendor/common_interfaces-jazzy/std_msgs@jazzy" \
  --input "geometry_msgs=vendor/common_interfaces-jazzy/geometry_msgs@jazzy" \
  --input "builtin_interfaces=vendor/rcl_interfaces-jazzy/builtin_interfaces@jazzy" \
  --input "rcl_interfaces=vendor/rcl_interfaces-jazzy/rcl_interfaces@jazzy" \
  --input "std_srvs=vendor/common_interfaces-jazzy/std_srvs@jazzy" \
  --input "example_interfaces=vendor/example_interfaces-jazzy@jazzy" \
  --input "action_msgs=vendor/rcl_interfaces-jazzy/action_msgs@jazzy" \
  --input "unique_identifier_msgs=vendor/unique_identifier_msgs@jazzy" \
  --types "$TYPES" \
  --rcl-srv-types "$SRV_TYPES" \
  --rcl-action-types "$ACTION_TYPES" \
  --rcl-registry-only-types "$REGISTRY_ONLY_TYPES" \
  --rcl-c-output Sources/CRclBridge \
  --rcl-swift-output Sources/SwiftROS2RCL/Generated
