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
# leetal ios-cmake enforces a Mac Catalyst minimum deployment target of 13.1.
DEPLOY_MAC=13.1
PKGS_UP_TO=(rcl rmw_cyclonedds_cpp builtin_interfaces std_msgs geometry_msgs sensor_msgs)
# C++ test-only / lint vendor packages get dragged into the --packages-up-to
# closure via <test_depend>, but never link into the runtime libraries. They
# build shared libs / executables (e.g. osrf_testing_tools_cpp's malloc
# interposition .dylib) that do not cross-compile to the static iOS/Catalyst
# toolchain. colcon has no "skip test deps" flag, so skip them explicitly.
SKIP_TEST_PKGS=(
  osrf_testing_tools_cpp performance_test_fixture
  gtest_vendor gmock_vendor google_benchmark_vendor
  mimick_vendor uncrustify_vendor
)

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

slice_platform() { case "$1" in
  maccatalyst) echo "MAC_CATALYST_ARM64 $DEPLOY_MAC" ;;
  macosx)      echo "MAC_ARM64 $DEPLOY_MAC" ;;
  iphoneos)    echo "OS64 $DEPLOY_IOS" ;;
  iphonesimulator) echo "SIMULATORARM64 $DEPLOY_IOS" ;;
  xros)        echo "VISIONOS $DEPLOY_IOS" ;;
  xrsimulator) echo "SIMULATOR_VISIONOS $DEPLOY_IOS" ;;
  *) echo "unknown slice: $1" >&2; return 1 ;; esac; }

cross_build() {  # $1 = slice, $2... = extra --packages-up-to
  local slice="$1"; shift
  read -r platform deploy < <(slice_platform "$slice")
  local sb="$BUILD/$slice"
  # shellcheck disable=SC1091
  source "$BUILD/venv/bin/activate"
  # colcon-generated setup.sh references unbound vars (COLCON_CURRENT_PREFIX);
  # relax `set -u` only while sourcing it, then restore strict mode.
  set +u
  # shellcheck disable=SC1091
  source "$HOST/install/setup.sh"
  set -u
  STATIC_ROSIDL_TYPESUPPORT_C=rosidl_typesupport_introspection_c \
  colcon --log-base "$sb/log" build \
    --base-paths "$SRC" \
    --build-base "$sb/build" --install-base "$sb/install" \
    --merge-install \
    --metas "$META" \
    --packages-up-to "$@" \
    --packages-skip "${SKIP_TEST_PKGS[@]}" \
    --cmake-args \
      -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
      -DPLATFORM="$platform" -DDEPLOYMENT_TARGET="$deploy" \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release
}
