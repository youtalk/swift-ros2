#!/usr/bin/env bash
# Verify a system ROS 2 install is usable for the Linux RCL build. Mirrors
# build-linux-deps.sh (which verifies pkg-config resolves CycloneDDS): this
# is the single source of truth Package.swift and CI both consult for
# "is the ROS 2 install complete enough to build against?"
#
# ROS2_RCL_PREFIX is a COLON-SEPARATED list of ament-overlay-style prefixes,
# e.g. "/home/user/ros2_mz5_overlay:/opt/ros/jazzy" (overlay first, base
# distro last — same ordering ament's own setup.bash chaining produces).
# A required library passes if it is found under lib/ in ANY listed prefix;
# it only fails if it is missing from every prefix. Defaults to a single
# prefix, /opt/ros/${ROS_DISTRO:-jazzy}, when unset.
#
# This script does NOT source setup.bash itself and does NOT emit -I/-L/-l
# flags — Package.swift computes those itself from ROS2_RCL_PREFIX.
set -euo pipefail

IFS=':' read -r -a PREFIXES <<< "${ROS2_RCL_PREFIX:-/opt/ros/${ROS_DISTRO:-jazzy}}"

for prefix in "${PREFIXES[@]}"; do
  if [[ ! -d "$prefix/include" || ! -d "$prefix/lib" ]]; then
    echo "error: ROS 2 prefix '$prefix' has no include/ or lib/. Source /opt/ros/<distro>/setup.bash or fix ROS2_RCL_PREFIX." >&2
    exit 1
  fi
done

# Libraries the CRclBridge marshal/srv/action registries + rcl stack link
# against. (Confirmed in MZ5 Task 1 against ROS 2 Jazzy.)
#
# Each message package also needs its __rosidl_generator_c library: the
# marshal registries reference the package's __init/__create/__destroy
# symbols, which live in generator_c, not typesupport_c. The linker won't
# pull generator_c transitively via DT_NEEDED, and ld.gold rejects
# --copy-dt-needed-entries, so Package.swift links both libs explicitly for
# every message package — this list must verify both to stay the single
# source of truth for "does the install have everything the link needs."
REQUIRED_LIBS=(rcl rmw rmw_implementation rcutils rcl_action \
  rosidl_runtime_c rosidl_typesupport_c rosidl_typesupport_introspection_c \
  action_msgs__rosidl_typesupport_c geometry_msgs__rosidl_typesupport_c \
  sensor_msgs__rosidl_typesupport_c std_msgs__rosidl_typesupport_c \
  std_srvs__rosidl_typesupport_c tf2_msgs__rosidl_typesupport_c \
  builtin_interfaces__rosidl_typesupport_c rcl_interfaces__rosidl_typesupport_c \
  example_interfaces__rosidl_typesupport_c audio_common_msgs__rosidl_typesupport_c \
  point_cloud_interfaces__rosidl_typesupport_c \
  action_msgs__rosidl_generator_c geometry_msgs__rosidl_generator_c \
  sensor_msgs__rosidl_generator_c std_msgs__rosidl_generator_c \
  std_srvs__rosidl_generator_c tf2_msgs__rosidl_generator_c \
  builtin_interfaces__rosidl_generator_c rcl_interfaces__rosidl_generator_c \
  example_interfaces__rosidl_generator_c audio_common_msgs__rosidl_generator_c \
  point_cloud_interfaces__rosidl_generator_c)

missing=()
for lib in "${REQUIRED_LIBS[@]}"; do
  found=0
  for prefix in "${PREFIXES[@]}"; do
    if ls "$prefix"/lib/"lib${lib}".so >/dev/null 2>&1; then
      found=1
      break
    fi
  done
  (( found )) || missing+=("$lib")
done

if (( ${#missing[@]} )); then
  echo "error: missing ROS 2 libraries under any of: ${PREFIXES[*]}" >&2
  echo "  missing: ${missing[*]}" >&2
  echo "install the matching ros-<distro>-* packages (see MZ5 plan Task 1 Step 1)." >&2
  echo "note: audio_common_msgs and point_cloud_interfaces are often not part of a" >&2
  echo "  stock /opt/ros/<distro> install — if they live in a separate overlay" >&2
  echo "  workspace, add that overlay's install prefix to ROS2_RCL_PREFIX (colon-" >&2
  echo "  separated, e.g. \"\$HOME/ros2_mz5_ws/install:/opt/ros/jazzy\")." >&2
  exit 1
fi

echo "OK: ROS 2 RCL prefixes resolve (${#REQUIRED_LIBS[@]} libs verified across ${#PREFIXES[@]} prefix(es): ${PREFIXES[*]})."
