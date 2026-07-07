#!/usr/bin/env bash
# Build the real ROS 2 C/C++ stack for Apple slices and assemble an
# xcframework. Two rmw variants (select with RMW_VARIANT):
#   cyclonedds (default) — rcl + rmw_cyclonedds_cpp + rosidl introspection
#                          typesupport -> build/ros2/CRos2Jazzy.xcframework
#   zenoh                — rcl + rmw_zenoh_cpp (no-SHM patch set under
#                          Scripts/ros2/patches/rmw_zenoh) + rosidl fastrtps
#                          typesupport (rmw_zenoh hard-codes it) + prebuilt
#                          zenoh-c staticlib (Rust; needs rustup/cargo on
#                          PATH) -> build/ros2zenoh/CRos2JazzyZenoh.xcframework
# Usage: [RMW_VARIANT=zenoh] Scripts/build-ros2-xcframework.sh maccatalyst iphoneos
set -euo pipefail

# Use BASH_SOURCE (not $0) so ROOT resolves correctly whether the script is
# executed directly or `source`d (e.g. the verification commands that run
# individual functions via `bash -c 'source ...; cross_build ...'`).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RMW_VARIANT="${RMW_VARIANT:-cyclonedds}"
case "$RMW_VARIANT" in
  cyclonedds)
    BUILD="$ROOT/build/ros2"
    XCFW_NAME="CRos2Jazzy"
    RMW_PKG=rmw_cyclonedds_cpp
    TS_C=rosidl_typesupport_introspection_c
    TS_CPP=rosidl_typesupport_introspection_cpp
    META="$ROOT/Scripts/ros2/colcon-defaults.meta"
    ;;
  zenoh)
    BUILD="$ROOT/build/ros2zenoh"
    XCFW_NAME="CRos2JazzyZenoh"
    RMW_PKG=rmw_zenoh_cpp
    # rmw_zenoh_cpp resolves message types through the fastrtps typesupport
    # only (type_support_common.hpp hard-codes the identifier), so the single
    # static typesupport pin flips from introspection to fastrtps. The Swift
    # bridge is unaffected — it resolves handles via the rosidl_typesupport_c
    # dispatcher macros, which statically bind to whichever backend is pinned.
    TS_C=rosidl_typesupport_fastrtps_c
    TS_CPP=rosidl_typesupport_fastrtps_cpp
    META="$ROOT/Scripts/ros2/colcon-defaults-zenoh.meta"
    ;;
  *) echo "RMW_VARIANT must be 'cyclonedds' or 'zenoh'; got '$RMW_VARIANT'" >&2; exit 1 ;;
esac
SRC="$BUILD/src_ws"
# The host generators and the python venv are rmw-agnostic; both variants
# share the cyclonedds tree's copies so the zenoh variant never rebuilds them.
HOST="$ROOT/build/ros2/host_ws"
VENV="$ROOT/build/ros2/venv"
TOOLCHAIN="$ROOT/Scripts/ros2/ios-cmake/ios.toolchain.cmake"
DEPLOY_IOS=16.0
# leetal ios-cmake enforces a Mac Catalyst minimum deployment target of 13.1.
DEPLOY_MAC=13.1
# visionOS versions are 1.x — passing the iOS target (16.0) to the xros /
# xrsimulator slices would be rejected by the visionOS SDK.
DEPLOY_VISIONOS=1.0
# std_srvs + example_interfaces carry the service types the M7 service shim
# registers (SetBool/Trigger/Empty, AddTwoInts); rcl_interfaces (parameter
# services) is already in the closure via rcl. rcl_action carries the action
# server/client API the M8 action shim drives; its typesupport deps
# (action_msgs, unique_identifier_msgs) are already in the closure, and
# example_interfaces brings the Fibonacci action wrapper types.
PKGS_UP_TO=(rcl "$RMW_PKG" rcl_action builtin_interfaces std_msgs geometry_msgs sensor_msgs std_srvs example_interfaces)
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
    if [[ -d "$SRC/$rel" ]]; then touch "$SRC/$rel/COLCON_IGNORE"; fi
  done
  if [[ "$RMW_VARIANT" == zenoh ]]; then
    # The zenoh variant carries no CycloneDDS at all — drop the rmw and the
    # middleware so the slice build never compiles them.
    for rel in ros2/rmw_cyclonedds eclipse-cyclonedds/cyclonedds; do
      if [[ -d "$SRC/$rel" ]]; then touch "$SRC/$rel/COLCON_IGNORE"; fi
    done
  fi
}

# CycloneDDS's POSIX ifaddrs backend includes <net/if_media.h> on Apple to
# guess the interface media type. That header ships in the macOS / Mac
# Catalyst SDK but NOT in the iOS device / simulator SDK. Insert an
# __has_include-guarded Apple branch that stubs guess_iftype where the header
# is absent (iOS); Catalyst/macOS keep the real media query. Idempotent.
patch_sources() {
  # Each patch below carries its own existence + already-applied guard so a
  # previously-patched file never short-circuits the later patches.
  local f="$SRC/eclipse-cyclonedds/cyclonedds/src/ddsrt/src/ifaddrs/posix/ifaddrs.c"
  if [[ -f "$f" ]] && ! grep -q "SWIFT_ROS2_IOS_IFTYPE_STUB" "$f"; then
    local tmp; tmp="$(mktemp)"
    awk '
      /^#elif defined\(__APPLE__\) \|\| defined\(__QNXNTO__\)/ && !done {
        print "#elif defined(__APPLE__) && !__has_include(<net/if_media.h>) /* SWIFT_ROS2_IOS_IFTYPE_STUB */"
        print "static enum ddsrt_iftype guess_iftype (const struct ifaddrs *sys_ifa) { (void) sys_ifa; return DDSRT_IFTYPE_UNKNOWN; }"
        done = 1
      }
      { print }
    ' "$f" > "$tmp" && mv "$tmp" "$f"
  fi

  # rcl exports rcl_logging_interface but not the concrete logging
  # implementation it links (RCL_LOGGING_IMPLEMENTATION=rcl_logging_noop,
  # pinned in both colcon-defaults.meta and colcon-defaults-zenoh.meta —
  # the dds and zenoh variants share this patch). With static libraries
  # the implementation target
  # stays in rcl's exported link interface, so the first downstream
  # find_package(rcl) consumer (rcl_action, added in M8) fails with
  # "rcl_logging_noop::rcl_logging_noop ... target was not found". Export the
  # selected implementation alongside the interface so rclConfig.cmake pulls
  # it in via find_dependency. Idempotent.
  local rcl_cmake="$SRC/ros2/rcl/rcl/CMakeLists.txt"
  if [[ -f "$rcl_cmake" ]] && ! grep -q 'ament_export_dependencies(${RCL_LOGGING_IMPLEMENTATION})' "$rcl_cmake"; then
    local tmp2; tmp2="$(mktemp)"
    awk '
      { print }
      /^ament_export_dependencies\(rcl_logging_interface\)$/ && !done {
        print "ament_export_dependencies(${RCL_LOGGING_IMPLEMENTATION})"
        done = 1
      }
    ' "$rcl_cmake" > "$tmp2" && mv "$tmp2" "$rcl_cmake"
  fi
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
  [[ -d "$VENV" ]] && return 0
  python3.11 -m venv "$VENV"
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
  pip install -r "$ROOT/Scripts/ros2/requirements.txt"
}

import_sources() {
  if [[ ! -d "$SRC/ros2/rcl" ]]; then
    mkdir -p "$SRC"
    git clone --depth 1 --branch release-jazzy-20250430 https://github.com/ros2/ros2.git "$BUILD/ros2-meta"
    ( cd "$SRC" && vcs import < "$BUILD/ros2-meta/ros2.repos" )
  fi
  import_zenoh_sources
}

# rmw_zenoh jazzy pin (0.2.9 line) — the commit the no-SHM patch set under
# Scripts/ros2/patches/rmw_zenoh was authored against.
RMW_ZENOH_PIN=fe3553c7c127273280617d3d778859f22c4c3eb7

import_zenoh_sources() {
  [[ "$RMW_VARIANT" == zenoh ]] || return 0
  local rz="$SRC/ros2/rmw_zenoh"
  [[ -d "$rz" ]] && return 0
  # rmw_zenoh is not in the jazzy ros2.repos set — clone + pin it explicitly.
  git clone --branch jazzy --single-branch https://github.com/ros2/rmw_zenoh.git "$rz"
  git -C "$rz" checkout "$RMW_ZENOH_PIN"
  # zenoh's shared-memory subsystem hard-fails to compile for target_os=ios
  # and rmw_zenoh_cpp has no no-SHM build mode; the patch set guards every
  # SHM use behind Z_FEATURE_SHARED_MEMORY (absent in our zenoh-c build),
  # makes the library static, and skips the rmw_zenohd executable when
  # cross-compiling.
  local p
  for p in "$ROOT/Scripts/ros2/patches/rmw_zenoh"/*.patch; do
    git -C "$rz" apply "$p"
  done
  # zenoh_cpp_vendor (an ament_vendor cargo wrapper) is replaced by the
  # prebuilt per-slice zenoh-c prefix (build_zenohc). COLCON_IGNORE makes
  # colcon treat it as external, so rmw_zenoh_cpp's
  # find_package(zenoh_cpp_vendor) resolves through CMAKE_PREFIX_PATH to the
  # hand-assembled config instead of driving cargo inside the colcon graph.
  touch "$rz/zenoh_cpp_vendor/COLCON_IGNORE"
}

build_host_tools() {
  [[ -f "$HOST/install/setup.sh" ]] && return 0
  ignore_unbuildable
  patch_sources
  # shellcheck disable=SC1091
  # The venv is shared from the cyclonedds tree (VENV, rmw-agnostic) — NOT
  # $BUILD/venv, which does not exist for the zenoh variant on a clean
  # checkout (the CI zenoh leg builds host tools before any cyclonedds run).
  source "$VENV/bin/activate"
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

# zenoh-c / zenoh-cpp pins from rmw_zenoh jazzy's zenoh_cpp_vendor
# (zenoh-c 1.8.0 + fixes; zenoh-cpp is the header-only C++ API).
ZENOHC_PIN=05bd370343b5161ca9269649b9a914c9c2dc4170
ZENOHCPP_PIN=af381b420cc8837ac7da42c9984594ef8f110e90

zenohc_triple() { case "$1" in
  maccatalyst) echo aarch64-apple-ios-macabi ;;
  macosx)      echo aarch64-apple-darwin ;;
  iphoneos)    echo aarch64-apple-ios ;;
  iphonesimulator) echo aarch64-apple-ios-sim ;;
  *) echo "zenoh variant: no stable Rust std for slice '$1'" >&2; return 1 ;; esac; }

# Cross-build zenoh-c (Rust staticlib) and assemble the CMake prefix that
# satisfies rmw_zenoh_cpp's find_package(zenoh_cpp_vendor / zenohc /
# zenohcxx). The feature set is rmw_zenoh's pin minus shared-memory: zenoh-shm
# gates platform support and compile_error!s for iOS targets, which is exactly
# what the patch set compensates for on the C++ side.
build_zenohc() {  # $1 = slice -> $BUILD/$slice/zenohc-install
  local slice="$1"
  local triple; triple="$(zenohc_triple "$slice")"
  local zc="$BUILD/zenoh-c" zcpp="$BUILD/zenoh-cpp"
  local out="$BUILD/$slice/zenohc-install"
  [[ -f "$out/lib/libzenohc.a" ]] && return 0
  if [[ ! -d "$zc" ]]; then
    git clone https://github.com/eclipse-zenoh/zenoh-c.git "$zc"
    git -C "$zc" checkout "$ZENOHC_PIN"
  fi
  if [[ ! -d "$zcpp" ]]; then
    git clone https://github.com/eclipse-zenoh/zenoh-cpp.git "$zcpp"
    git -C "$zcpp" checkout "$ZENOHCPP_PIN"
  fi
  rustup target add "$triple"
  ( cd "$zc" && cargo build --release -j 4 --target "$triple" \
      --features unstable --features transport_serial )
  rm -rf "$out"
  mkdir -p "$out/lib/cmake" "$out/share/zenoh_cpp_vendor/cmake"
  # cargo's build.rs regenerates the header set (zenoh_configure.h carries the
  # feature macros — Z_FEATURE_SHARED_MEMORY must be absent) into the target
  # dir; zenoh-cpp contributes the header-only C++ API.
  cp -R "$zc/target/$triple/release/include" "$out/include"
  cp -R "$zcpp/include/zenoh" "$out/include/zenoh"
  cp "$zcpp/include/zenoh.hxx" "$out/include/"
  cp "$zc/target/$triple/release/libzenohc.a" "$out/lib/"
  cp -R "$ROOT/Scripts/ros2/zenohc-cmake/zenohc" "$out/lib/cmake/zenohc"
  cp -R "$ROOT/Scripts/ros2/zenohc-cmake/zenohcxx" "$out/lib/cmake/zenohcxx"
  cp "$ROOT/Scripts/ros2/zenohc-cmake/zenoh_cpp_vendor/zenoh_cpp_vendorConfig.cmake" \
     "$out/share/zenoh_cpp_vendor/cmake/"
}

cross_build() {  # $1 = slice, $2... = extra --packages-up-to
  local slice="$1"; shift
  read -r platform deploy < <(slice_platform "$slice")
  local sb="$BUILD/$slice"
  ignore_unbuildable
  patch_sources
  local extra_cmake=()
  if [[ "$RMW_VARIANT" == zenoh ]]; then
    build_zenohc "$slice"
    extra_cmake+=(-DCMAKE_PREFIX_PATH="$sb/zenohc-install")
  fi
  # ament_vendor forwards CMAKE_TOOLCHAIN_FILE to its nested ExternalProject
  # builds (e.g. libyaml) but NOT the toolchain's required PLATFORM var, so the
  # nested cmake bails with "PLATFORM argument not set". The leetal toolchain
  # also reads PLATFORM from ENV{_PLATFORM}, so export it as a real environment
  # variable — it propagates through colcon -> make -> ExternalProject -> cmake.
  export _PLATFORM="$platform"
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
  # colcon-generated setup.sh references unbound vars (COLCON_CURRENT_PREFIX);
  # relax `set -u` only while sourcing it, then restore strict mode.
  set +u
  # shellcheck disable=SC1091
  source "$HOST/install/setup.sh"
  set -u
  STATIC_ROSIDL_TYPESUPPORT_C="$TS_C" \
  STATIC_ROSIDL_TYPESUPPORT_CPP="$TS_CPP" \
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
      -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release \
      ${extra_cmake[@]+"${extra_cmake[@]}"}
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
  # The zenoh variant links the prebuilt Rust staticlib into the merged
  # archive so consumers still link exactly one library.
  if [[ "$RMW_VARIANT" == zenoh ]]; then
    archives+=("$sb/zenohc-install/lib/libzenohc.a")
  fi
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
  local out="$BUILD/$XCFW_NAME.xcframework"
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

# rmw_zenoh_cpp resolves its default session config through the ament index
# at runtime; apps and the local smoke point AMENT_PREFIX_PATH at this mini
# prefix (index marker + the json5 configs).
assemble_zenoh_ament_prefix() {
  [[ "$RMW_VARIANT" == zenoh ]] || return 0
  local ap="$BUILD/ament-prefix"
  mkdir -p "$ap/share/ament_index/resource_index/packages" \
           "$ap/share/rmw_zenoh_cpp/config"
  touch "$ap/share/ament_index/resource_index/packages/rmw_zenoh_cpp"
  cp "$SRC/ros2/rmw_zenoh/rmw_zenoh_cpp/config/"*.json5 \
     "$ap/share/rmw_zenoh_cpp/config/"
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
  assemble_zenoh_ament_prefix
fi
