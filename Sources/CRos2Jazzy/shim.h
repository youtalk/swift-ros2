#pragma once
// Linux-only systemLibrary shim for the CRos2Jazzy module. It gathers the core
// rcl / rmw / rcutils / rosidl / rcl_action headers that CRclBridge includes
// textually. On Linux these resolve from the ament prefix include dirs injected
// onto CRclBridge (and the C smoke executables) by Package.swift; on Apple this
// file is unused — the CRos2Jazzy xcframework ships its own synthesized module
// and headers.
//
// Nothing in the package `import`s the CRos2Jazzy module from Swift, and the C
// bridges reach rcl through plain `#include` (resolved by their own -I flags),
// so on Linux this module is declared-but-never-compiled — the same shape as
// the Windows CCycloneDDS systemLibrary. Extra headers here are harmless.
#include <rcl/rcl.h>
#include <rcl/publisher.h>
#include <rcl/subscription.h>
#include <rcl/client.h>
#include <rcl/service.h>
#include <rcl/graph.h>
#include <rcl/guard_condition.h>
#include <rcl/wait.h>
#include <rcl/time.h>
#include <rcl/error_handling.h>
#include <rcl_action/rcl_action.h>
#include <rmw/rmw.h>
#include <rmw/types.h>
#include <rmw/qos_profiles.h>
#include <rmw/serialized_message.h>
#include <rcutils/allocator.h>
#include <rosidl_runtime_c/message_type_support_struct.h>
#include <rosidl_runtime_c/service_type_support_struct.h>
#include <rosidl_runtime_c/action_type_support_struct.h>
#include <rosidl_runtime_c/string_functions.h>
#include <rosidl_runtime_c/primitives_sequence_functions.h>
#include <rosidl_runtime_c/type_hash.h>
