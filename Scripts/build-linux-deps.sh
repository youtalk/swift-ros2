#!/usr/bin/env bash
# Prepare Linux native dependencies for swift-ros2.
#
# - zenoh-pico: build from the vendored submodule into .build/linux-deps/
# - CycloneDDS: verified via pkg-config (provided by the host package,
#   e.g. `apt install ros-jazzy-cyclonedds` for ROS 2 Jazzy).
#
# After running, consumers set:
#   source /opt/ros/jazzy/setup.bash
#   export PKG_CONFIG_PATH="$PWD/.build/linux-deps/lib/pkgconfig:/opt/ros/jazzy/lib/$(uname -m)-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
#   swift build
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/.build/linux-deps"

case "$(uname -s)" in
    Linux*) ;;
    *) echo "error: $0 is Linux-only (use binaryTarget xcframeworks on Apple)." >&2; exit 1 ;;
esac

command -v cmake >/dev/null || { echo "error: cmake not found"; exit 1; }
command -v pkg-config >/dev/null || { echo "error: pkg-config not found"; exit 1; }

mkdir -p "$BUILD"

echo "==> building zenoh-pico (static) into $BUILD"
cd "$ROOT/vendor/zenoh-pico"
rm -rf build-linux
mkdir build-linux
cd build-linux
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DZ_FEATURE_LINK_TCP=1 \
    -DZ_FEATURE_LIVELINESS=1 \
    -DCMAKE_INSTALL_PREFIX="$BUILD"
cmake --build . --config Release -- -j"$(nproc)"
cmake --install .

cat > "$BUILD/lib/pkgconfig/ZenohPico.pc" <<EOF
prefix=$BUILD
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: ZenohPico
Description: Zenoh client library, pico version (swift-ros2 vendored build)
Version: 1.1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lzenohpico
EOF

echo ""
echo "==> verifying CycloneDDS via pkg-config"
if ! pkg-config --exists CycloneDDS 2>/dev/null; then
    echo "CycloneDDS.pc not in default PKG_CONFIG_PATH. Trying /opt/ros/jazzy..."
    export PKG_CONFIG_PATH="/opt/ros/jazzy/lib/$(uname -m)-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
    if ! pkg-config --exists CycloneDDS 2>/dev/null; then
        cat <<MSG >&2

error: CycloneDDS not found via pkg-config.

Install one of:
  - ROS 2 Jazzy package: sudo apt install ros-jazzy-cyclonedds
    then: source /opt/ros/jazzy/setup.bash
  - Eclipse upstream:   sudo apt install libcyclonedds-dev
  - From source:        https://github.com/eclipse-cyclonedds/cyclonedds

Add its .pc location to PKG_CONFIG_PATH before re-running this script.
MSG
        exit 2
    fi
fi
echo "CycloneDDS:"
pkg-config --cflags --libs CycloneDDS

echo ""
echo "==> bootstrap complete."
echo ""
echo "Before running swift build / swift test:"
echo "  source /opt/ros/jazzy/setup.bash"
echo "  export PKG_CONFIG_PATH=\"$BUILD/lib/pkgconfig:/opt/ros/jazzy/lib/$(uname -m)-linux-gnu/pkgconfig:\${PKG_CONFIG_PATH:-}\""
echo "  swift build"
