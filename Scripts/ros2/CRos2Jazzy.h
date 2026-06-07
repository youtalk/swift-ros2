// Umbrella header for the CRos2Jazzy module.
//
// Using an umbrella *header* (not `umbrella "."`) means Clang only compiles
// the headers reachable from here, not every file installed in the headers
// directory. ROS 2 / CycloneDDS install platform-specific and C++ headers
// (e.g. rcutils/stdatomic_helper/win32/stdatomic.h -> <Windows.h>, fastcdr
// C++ headers) that do not compile in a macOS/iOS C module build; an umbrella
// directory would try to compile all of them. The rcl C API reachable from
// <rcl/rcl.h> is self-contained C, so this stays clean.
//
// Extend this list as the native-rcl backend grows (M1+): add the per-message
// introspection typesupport handle headers the publisher needs.
#include <rcl/rcl.h>
#include <rcl/error_handling.h>
#include <rcl/publisher.h>
#include <rmw/rmw.h>
#include <rosidl_runtime_c/message_type_support_struct.h>
// M1: sensor_msgs/Imu typesupport declaration (rosidl_typesupport_c symbol).
#include <sensor_msgs/msg/imu.h>
