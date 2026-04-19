#!/usr/bin/env bash
# Verify Linux native dependencies needed by swift-ros2 are reachable.
#
# - zenoh-pico: compiled by SPM directly from the vendored submodule
#   (vendor/zenoh-pico). No action required by this script.
# - CycloneDDS: provided by the host (e.g. `apt install ros-jazzy-cyclonedds`).
#   Must be discoverable via pkg-config under the name `CycloneDDS`.
#
# After running, consumers set:
#   source /opt/ros/jazzy/setup.bash
#   export PKG_CONFIG_PATH="/opt/ros/jazzy/lib/$(uname -m)-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
#   swift build
set -euo pipefail

case "$(uname -s)" in
    Linux*) ;;
    *) echo "error: $0 is Linux-only (use binaryTarget xcframeworks on Apple)." >&2; exit 1 ;;
esac

command -v pkg-config >/dev/null || { echo "error: pkg-config not found. sudo apt install pkg-config" >&2; exit 1; }

echo "==> verifying CycloneDDS via pkg-config"
if ! pkg-config --exists CycloneDDS 2>/dev/null; then
    echo "CycloneDDS.pc not in default PKG_CONFIG_PATH. Trying /opt/ros/jazzy..."
    export PKG_CONFIG_PATH="/opt/ros/jazzy/lib/$(uname -m)-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
    if ! pkg-config --exists CycloneDDS 2>/dev/null; then
        cat <<MSG >&2

error: CycloneDDS not found via pkg-config.

Install one of:
  - ROS 2 Jazzy:      sudo apt install ros-jazzy-cyclonedds
                      then: source /opt/ros/jazzy/setup.bash
  - Eclipse upstream: sudo apt install libcyclonedds-dev
  - From source:      https://github.com/eclipse-cyclonedds/cyclonedds

Add its .pc location to PKG_CONFIG_PATH before re-running this script.
MSG
        exit 2
    fi
fi
echo "CycloneDDS: $(pkg-config --modversion CycloneDDS)"
echo "  CFLAGS: $(pkg-config --cflags CycloneDDS)"
echo "  LIBS:   $(pkg-config --libs CycloneDDS)"

echo ""
echo "==> bootstrap complete."
echo ""
echo "Before running swift build / swift test:"
echo "  source /opt/ros/jazzy/setup.bash"
echo "  export PKG_CONFIG_PATH=\"/opt/ros/jazzy/lib/$(uname -m)-linux-gnu/pkgconfig:\${PKG_CONFIG_PATH:-}\""
echo "  swift build"
