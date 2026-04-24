#!/usr/bin/env bash
# Discover swift-ros2 test executables built for Android x86_64, push
# them plus the Swift Android runtime to the running emulator via adb,
# run each under LD_LIBRARY_PATH, and exit non-zero on any failure.
#
# Run this inside reactivecircus/android-emulator-runner@v2's `script:`
# block after `swift build --build-tests --swift-sdk
# x86_64-unknown-linux-android28`.
set -euo pipefail

BUILD_DIR=".build/x86_64-unknown-linux-android28/debug"
# Hard-coded device-side path. Avoid interpolating it into adb shell
# strings — the device shell parses what we send, so paths with shell
# metacharacters would silently misbehave. If you need to change the
# path, change it here AND in the single-quoted device commands below.
REMOTE_DIR="/data/local/tmp/swift-ros2-tests"

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "ERROR: $BUILD_DIR does not exist. Build with --build-tests first." >&2
  exit 2
fi

# Locate the Swift Android runtime that the test binaries dynamically
# link against. Without these .so files on the device, every test
# launch fails with an opaque dlopen error — fail fast here instead.
if ! SWIFT_SDK_ROOT="$(swift sdk configuration show x86_64-unknown-linux-android28 2>/dev/null | awk -F': ' '/sdkRootPath/ {print $2}')"; then
  echo "ERROR: 'swift sdk configuration show x86_64-unknown-linux-android28' failed. Is the Swift Android SDK installed?" >&2
  exit 2
fi
if [[ -z "${SWIFT_SDK_ROOT:-}" ]]; then
  echo "ERROR: Swift SDK configuration did not report an sdkRootPath for x86_64-unknown-linux-android28." >&2
  exit 2
fi
SWIFT_RUNTIME_DIR="$SWIFT_SDK_ROOT/usr/lib/swift/android"
if [[ ! -d "$SWIFT_RUNTIME_DIR" ]]; then
  echo "ERROR: Swift Android runtime directory not found at $SWIFT_RUNTIME_DIR." >&2
  exit 2
fi

# Reset device-side workspace. Device path is single-quoted so the
# shell-on-device sees the literal /data/local/tmp/... string regardless
# of host-side variable expansion concerns.
adb shell 'rm -rf /data/local/tmp/swift-ros2-tests && mkdir -p /data/local/tmp/swift-ros2-tests/swift-runtime'

adb push "$SWIFT_RUNTIME_DIR/." "$REMOTE_DIR/swift-runtime/" >/dev/null

# Push test binaries. XCTest bundles on Linux/Android ship as plain
# executables under .build/<triple>/debug/<Name>PackageTests.xctest.
shopt -s nullglob
PUSHED=()
for BIN in "$BUILD_DIR"/*PackageTests.xctest "$BUILD_DIR"/*Tests.xctest; do
  [[ -f "$BIN" && -x "$BIN" ]] || continue
  BASENAME="$(basename "$BIN")"
  adb push "$BIN" "$REMOTE_DIR/$BASENAME" >/dev/null
  PUSHED+=("$BASENAME")
done

if (( ${#PUSHED[@]} == 0 )); then
  echo "ERROR: no *.xctest test binaries found under $BUILD_DIR" >&2
  exit 2
fi

# Run each test binary on the emulator; collect failures.
# The device-side command is single-quoted so $BASENAME is interpolated
# host-side once and the device shell sees a fully-resolved string.
# We hard-code the device paths instead of interpolating $REMOTE_DIR
# into the device command line.
FAILED=()
for BIN in "${PUSHED[@]}"; do
  echo "::group::Running $BIN"
  if adb shell "chmod +x '/data/local/tmp/swift-ros2-tests/${BIN}' && cd /data/local/tmp/swift-ros2-tests && LD_LIBRARY_PATH=/data/local/tmp/swift-ros2-tests/swift-runtime './${BIN}'"; then
    :
  else
    FAILED+=("$BIN")
  fi
  echo "::endgroup::"
done

if (( ${#FAILED[@]} > 0 )); then
  echo "FAILED test binaries: ${FAILED[*]}" >&2
  exit 1
fi

echo "All test binaries passed."
