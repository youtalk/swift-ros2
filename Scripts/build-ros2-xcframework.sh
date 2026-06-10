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
# visionOS versions are 1.x — passing the iOS target (16.0) to the xros /
# xrsimulator slices would be rejected by the visionOS SDK.
DEPLOY_VISIONOS=1.0
PKGS_UP_TO=(rcl rmw_cyclonedds_cpp builtin_interfaces std_msgs geometry_msgs sensor_msgs)
# C++ test-only / lint vendor packages get dragged into the --packages-up-to
# closure via <test_depend>, but never link into the runtime libraries. They
# build shared libs / executables (e.g. osrf_testing_tools_cpp's malloc
# interposition .dylib) that do not cross-compile to the static iOS/Catalyst
# toolchain. They are leaf test deps, so colcon's --packages-skip drops them
# without breaking the dependents' build closure.
SKIP_TEST_PKGS=(
  osrf_testing_tools_cpp performance_test_fixture
  gtest_vendor gmock_vendor google_benchmark_vendor
  mimick_vendor uncrustify_vendor
)

# Drop COLCON_IGNORE so colcon never discovers these subtrees and treats them
# as external (so dependents don't flag an unmet dependency — unlike
# --packages-skip). These cannot or need not be cross-compiled for a
# CycloneDDS-only, introspection-typesupport ROS 2 build:
#  - iceoryx: cyclonedds's shared-memory transport (POSIX-SHM RouDi daemon);
#    does not cross-compile to iOS, unusable in the app sandbox. CycloneDDS
#    configures fine without it (ENABLE_SHM=OFF).
#  - rmw_fastrtps / rmw_connextdds: rcl pulls every RMW via rmw_implementation's
#    runtime selection, but we use rmw_cyclonedds_cpp only
#    (RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION=ON). The Fast-DDS RMW drags
#    in the Fast-DDS middleware + foonathan_memory_vendor, whose nested
#    ExternalProject build does not cross-compile to iOS.
#  - Fast-DDS (fastrtps) + foonathan_memory_vendor: only reachable via
#    rmw_fastrtps; not needed. (Fast-CDR / rosidl_typesupport_fastrtps stay —
#    the fastrtps *typesupport* only needs fastcdr, which cross-compiles.)
IGNORE_SUBTREES=(
  eclipse-iceoryx/iceoryx
  ros2/rmw_fastrtps
  ros2/rmw_connextdds
  ros2/rosidl_dynamic_typesupport_fastrtps
  eProsima/Fast-DDS
  eProsima/foonathan_memory_vendor
  # noop logging (RCL_LOGGING_IMPLEMENTATION=rcl_logging_noop) makes the
  # default spdlog logging backend unnecessary; drop it and its vendor.
  ros2/rcl_logging/rcl_logging_spdlog
  ros2/spdlog_vendor
  # rosidl_generator_py emits Python C-extension bindings for every message
  # package. Generation is driven by which generators are discoverable in the
  # ament prefix (not by buildtool_depend), so its mere presence in the host
  # tools forces a libpython-linked .dylib per message type — which fails to
  # cross-compile to iOS (links the host's macOS Python framework). We consume
  # ROS 2 from C/C++/Swift only, so drop the Python generator entirely; message
  # packages then generate just the C/C++/introspection typesupports.
  ros2/rosidl_python
)
ignore_unbuildable() {
  local rel
  for rel in "${IGNORE_SUBTREES[@]}"; do
    [[ -d "$SRC/$rel" ]] && touch "$SRC/$rel/COLCON_IGNORE"
  done
}

# CycloneDDS's POSIX ifaddrs backend includes <net/if_media.h> on Apple to
# guess the interface media type. That header ships in the macOS / Mac
# Catalyst SDK but NOT in the iOS device / simulator SDK. Insert an
# __has_include-guarded Apple branch that stubs guess_iftype where the header
# is absent (iOS); Catalyst/macOS keep the real media query. Idempotent.
patch_sources() {
  local f="$SRC/eclipse-cyclonedds/cyclonedds/src/ddsrt/src/ifaddrs/posix/ifaddrs.c"
  [[ -f "$f" ]] || return 0
  grep -q "SWIFT_ROS2_IOS_IFTYPE_STUB" "$f" && return 0
  local tmp; tmp="$(mktemp)"
  awk '
    /^#elif defined\(__APPLE__\) \|\| defined\(__QNXNTO__\)/ && !done {
      print "#elif defined(__APPLE__) && !__has_include(<net/if_media.h>) /* SWIFT_ROS2_IOS_IFTYPE_STUB */"
      print "static enum ddsrt_iftype guess_iftype (const struct ifaddrs *sys_ifa) { (void) sys_ifa; return DDSRT_IFTYPE_UNKNOWN; }"
      done = 1
    }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

mkdir -p "$BUILD"

# CMake 4.x removed compatibility with cmake_minimum_required(VERSION < 3.5).
# Some bundled sources still declare old minimums (e.g. libyaml, pulled by
# libyaml_vendor's ExternalProject). CMake honours CMAKE_POLICY_VERSION_MINIMUM
# from the environment, which propagates to every nested cmake invocation
# (colcon -> cmake -> ExternalProject -> inner cmake), unlike a -D on the outer
# command line. Pin it so old projects still configure under CMake 4.x.
export CMAKE_POLICY_VERSION_MINIMUM=3.5

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
  ignore_unbuildable
  patch_sources
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
  xros)        echo "VISIONOS $DEPLOY_VISIONOS" ;;
  xrsimulator) echo "SIMULATOR_VISIONOS $DEPLOY_VISIONOS" ;;
  *) echo "unknown slice: $1" >&2; return 1 ;; esac; }

cross_build() {  # $1 = slice, $2... = extra --packages-up-to
  local slice="$1"; shift
  read -r platform deploy < <(slice_platform "$slice")
  local sb="$BUILD/$slice"
  ignore_unbuildable
  patch_sources
  # ament_vendor forwards CMAKE_TOOLCHAIN_FILE to its nested ExternalProject
  # builds (e.g. libyaml) but NOT the toolchain's required PLATFORM var, so the
  # nested cmake bails with "PLATFORM argument not set". The leetal toolchain
  # also reads PLATFORM from ENV{_PLATFORM}, so export it as a real environment
  # variable — it propagates through colcon -> make -> ExternalProject -> cmake.
  export _PLATFORM="$platform"
  # shellcheck disable=SC1091
  source "$BUILD/venv/bin/activate"
  # colcon-generated setup.sh references unbound vars (COLCON_CURRENT_PREFIX);
  # relax `set -u` only while sourcing it, then restore strict mode.
  set +u
  # shellcheck disable=SC1091
  source "$HOST/install/setup.sh"
  set -u
  STATIC_ROSIDL_TYPESUPPORT_C=rosidl_typesupport_introspection_c \
  STATIC_ROSIDL_TYPESUPPORT_CPP=rosidl_typesupport_introspection_cpp \
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
      -DCMAKE_MAKE_PROGRAM=/usr/bin/make \
      -DFORCE_BUILD_VENDOR_PKG=ON \
      -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release
}

merge_slice() {  # $1 = slice -> build/ros2/<slice>/merged/{librclros.a,include}
  # Separate `local` statements: `local a=$1 b=$BUILD/$a` expands $a before it
  # is localized, which trips `set -u` ("a: unbound variable").
  local slice="$1"
  local sb="$BUILD/$slice"
  local out="$sb/merged"
  rm -rf "$out"; mkdir -p "$out"
  # Merge all static archives into one. install/lib/*.a are the ament packages;
  # install/opt/*/lib/*.a are vendor packages whose ament_vendor build installs
  # into a private opt prefix (e.g. libyaml from libyaml_vendor) — both are
  # needed or the static link leaves undefined symbols.
  #
  # Use `libtool -static` directly on the archives rather than `ar x` + re-pack.
  # CycloneDDS's libddsc.a contains duplicate member names (random.c.o,
  # time.c.o, ... — a generic and a platform variant); `ar x` overwrites them
  # on disk, silently dropping the object that defines symbols like
  # _ddsrt_random. libtool merges archives while preserving duplicate members.
  local archives=()
  local a
  shopt -s nullglob
  for a in "$sb/install/lib/"*.a "$sb/install/opt/"*/lib/*.a; do archives+=("$a"); done
  shopt -u nullglob
  libtool -static -o "$out/librclros.a" "${archives[@]}"
  cp -R "$sb/install/include" "$out/include"
  # ROS 2 installs headers doubled: include/<pkg>/<pkg>/foo.h, consumed as
  # <pkg/foo.h>. An xcframework exposes a single headers dir as one search
  # path, so collapse the doubled level (include/<pkg>/<pkg>/* ->
  # include/<pkg>/*) so <pkg/foo.h> resolves. Non-doubled trees (CycloneDDS
  # dds/ddsc, idl, fastcdr) are already at the right level and left as-is.
  local p name
  for p in "$out/include"/*/; do
    name="$(basename "$p")"
    if [[ -d "$p$name" ]]; then
      ( shopt -s dotglob nullglob; mv "$p$name"/* "$p" )
      rmdir "$p$name" 2>/dev/null || true
    fi
  done
  # Keep only C headers. The umbrella module is consumed from C (the rcl C
  # API: rcl/rmw/rcutils/rosidl_runtime_c are all .h). C++ headers (.hpp:
  # rosidl_runtime_cpp, rcpputils, message C++ builders, fastcdr) pull
  # <algorithm> etc. and break the module when built in C mode; they are not
  # needed for the C publish path, so drop them.
  find "$out/include" -type f ! -name '*.h' -delete
  # Drop the fastrtps typesupport from the public umbrella: fastcdr ships C++
  # under a .h extension (Cdr.h includes <array>) and every message package's
  # per-type *__rosidl_typesupport_fastrtps_c.h pulls fastcdr/Cdr.h — both
  # break the C umbrella module. The publish path uses the introspection
  # typesupport only; the fastrtps typesupport objects stay in librclros.a as
  # harmless dead weight (nothing references them), just not in the headers.
  rm -rf "$out/include/fastcdr" \
         "$out/include/rosidl_typesupport_fastrtps_c" \
         "$out/include/rosidl_typesupport_fastrtps_cpp"
  find "$out/include" -name '*rosidl_typesupport_fastrtps*' -delete
  # CycloneDDS internal/tooling headers (dds/, ddsc/, idl/, idlc/) are not part
  # of the rcl C API — rmw_cyclonedds installs no public header and nothing
  # else includes <dds/...>; CycloneDDS is consumed only at link time (libddsc
  # in librclros.a). Their internal headers reference iceoryx (the disabled SHM
  # transport) and don't self-compile under the umbrella, so drop them.
  rm -rf "$out/include/dds" "$out/include/ddsc" \
         "$out/include/idl" "$out/include/idlc"
  find "$out/include" -type d -empty -delete
}

assemble_xcframework() {  # $@ = slices
  local out="$BUILD/CRos2Jazzy.xcframework"
  rm -rf "$out"
  local args=()
  local slice m
  for slice in "$@"; do
    m="$BUILD/$slice/merged"
    cp "$ROOT/Scripts/ros2/module.modulemap" "$m/include/module.modulemap"
    cp "$ROOT/Scripts/ros2/CRos2Jazzy.h" "$m/include/CRos2Jazzy.h"
    args+=(-library "$m/librclros.a" -headers "$m/include")
  done
  xcodebuild -create-xcframework "${args[@]}" -output "$out"
}

# Top-level dispatch when invoked directly (not sourced) with slice args.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_venv
  import_sources
  build_host_tools
  for slice in "$@"; do
    cross_build "$slice" "${PKGS_UP_TO[@]}"
    merge_slice "$slice"
  done
  assemble_xcframework "$@"
fi
