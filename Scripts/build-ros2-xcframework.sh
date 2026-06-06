#!/usr/bin/env bash
# Build the real ROS 2 (rcl + rmw_cyclonedds_cpp + rosidl introspection)
# C/C++ stack for Apple slices and assemble CRos2Jazzy.xcframework.
# Usage: Scripts/build-ros2-xcframework.sh maccatalyst iphoneos
set -euo pipefail

# Use BASH_SOURCE (not $0) so ROOT resolves correctly whether the script is
# executed directly or `source`d (e.g. the verification commands that run
# individual functions via `bash -c 'source ...; cross_build ...'`).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/ros2"
SRC="$BUILD/src_ws"
HOST="$BUILD/host_ws"
TOOLCHAIN="$ROOT/Scripts/ros2/ios-cmake/ios.toolchain.cmake"
META="$ROOT/Scripts/ros2/colcon-defaults.meta"
DEPLOY_IOS=16.0
DEPLOY_MAC=13.0
PKGS_UP_TO=(rcl rmw_cyclonedds_cpp builtin_interfaces std_msgs geometry_msgs sensor_msgs)

mkdir -p "$BUILD"

setup_venv() {
  [[ -d "$BUILD/venv" ]] && return 0
  python3.11 -m venv "$BUILD/venv"
  # shellcheck disable=SC1091
  source "$BUILD/venv/bin/activate"
  pip install -r "$ROOT/Scripts/ros2/requirements.txt"
}

import_sources() {
  [[ -d "$SRC/ros2/rcl" ]] && return 0
  mkdir -p "$SRC"
  git clone --depth 1 --branch release-jazzy-20250430 https://github.com/ros2/ros2.git "$BUILD/ros2-meta"
  ( cd "$SRC" && vcs import < "$BUILD/ros2-meta/ros2.repos" )
}

build_host_tools() {
  [[ -f "$HOST/install/setup.sh" ]] && return 0
  # shellcheck disable=SC1091
  source "$BUILD/venv/bin/activate"
  colcon --log-base "$HOST/log" build \
    --base-paths "$SRC" \
    --build-base "$HOST/build" --install-base "$HOST/install" \
    --merge-install \
    --packages-up-to rosidl_default_generators rosidl_typesupport_introspection_c \
    --cmake-args -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release
}
