#!/usr/bin/env bash
# Regenerate the native-RCL marshalling (C + Swift) for the M3b/M3c type set.
# Run from the repo root. The same invocation backs the ci-rcl drift guard.
set -euo pipefail
TYPES="Imu,Joy,BatteryState,CompressedImage,PointCloud2,MagneticField,FluidPressure,Illuminance,NavSatFix,Range,Temperature"
swift run swift-ros2-gen --emit-rcl-marshalling \
  --input "sensor_msgs=vendor/common_interfaces-jazzy/sensor_msgs@jazzy" \
  --input "std_msgs=vendor/common_interfaces-jazzy/std_msgs@jazzy" \
  --input "geometry_msgs=vendor/common_interfaces-jazzy/geometry_msgs@jazzy" \
  --input "builtin_interfaces=vendor/rcl_interfaces-jazzy/builtin_interfaces@jazzy" \
  --types "$TYPES" \
  --rcl-c-output Sources/CRclBridge \
  --rcl-swift-output Sources/SwiftROS2RCL/Generated
