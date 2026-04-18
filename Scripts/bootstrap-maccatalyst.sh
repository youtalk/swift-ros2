#!/usr/bin/env bash
# Bootstrap Vendor/ with pre-built CycloneDDS + zenoh-pico static libs
# from the parent Conduit checkout. Used during Phase 1 so `swift build`
# and `swift test` can compile + link before xcframeworks are published
# in Phase 2. Safe to re-run.
#
# Produces:
#   Vendor/include/            — zenoh-pico + cyclonedds headers
#   Vendor/maccatalyst-arm64/  — libs for Mac Catalyst (xcodebuild)
#   Vendor/macos-arm64/        — libs for native macOS (swift test)
#   Vendor/pkgconfig/*.pc      — pkg-config files pointing at macos-arm64
#                                (swift test default). Override Libs:
#                                manually if you need a different slice.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONDUIT="${CONDUIT:-$ROOT/../..}"
CONDUIT_DEPS="${CONDUIT_DEPS:-$CONDUIT/deps}"

require() {
    local path="$1" hint="$2"
    if [ ! -f "$path" ]; then
        echo "error: $path not found. $hint" >&2
        exit 1
    fi
}

mkdir -p "$ROOT/Vendor/include" "$ROOT/Vendor/maccatalyst-arm64" \
         "$ROOT/Vendor/macos-arm64" "$ROOT/Vendor/pkgconfig"

# Mac Catalyst libs
require "$CONDUIT_DEPS/maccatalyst/libzenohpico.a" \
    "Build via: SDK=maccatalyst bash $CONDUIT/scripts/build_deps.sh"
require "$CONDUIT_DEPS/maccatalyst/libddsc.a" \
    "Build via: SDK=maccatalyst bash $CONDUIT/scripts/build_cyclonedds.sh"
cp "$CONDUIT_DEPS/maccatalyst/libzenohpico.a" "$ROOT/Vendor/maccatalyst-arm64/"
cp "$CONDUIT_DEPS/maccatalyst/libddsc.a"      "$ROOT/Vendor/maccatalyst-arm64/"

# Native macOS libs (for swift test). These come from out-of-tree CMake
# builds Conduit performs when running the native macOS-arm64 scheme.
require "$CONDUIT_DEPS/zenoh-pico/build-macos-arm64/lib/libzenohpico.a" \
    "Build via: (cd $CONDUIT_DEPS/zenoh-pico && mkdir -p build-macos-arm64 && \
cd build-macos-arm64 && cmake .. -DBUILD_SHARED_LIBS=OFF -DZ_FEATURE_LINK_TCP=1 \
-DZ_FEATURE_LIVELINESS=1 && cmake --build .)"
require "$CONDUIT_DEPS/cyclonedds/build-macos-arm64/lib/libddsc.a" \
    "Build via: (cd $CONDUIT_DEPS/cyclonedds && mkdir -p build-macos-arm64 && \
cd build-macos-arm64 && cmake .. -DBUILD_SHARED_LIBS=OFF -DBUILD_EXAMPLES=OFF \
-DBUILD_TESTING=OFF -DENABLE_SSL=OFF -DENABLE_SECURITY=OFF && cmake --build .)"
cp "$CONDUIT_DEPS/zenoh-pico/build-macos-arm64/lib/libzenohpico.a" "$ROOT/Vendor/macos-arm64/"
cp "$CONDUIT_DEPS/cyclonedds/build-macos-arm64/lib/libddsc.a"      "$ROOT/Vendor/macos-arm64/"

# Headers (same content across slices)
rm -rf "$ROOT/Vendor/include/zenoh-pico" "$ROOT/Vendor/include/dds" "$ROOT/Vendor/include/ddsc"
cp -R "$CONDUIT_DEPS/include/zenoh-pico" "$ROOT/Vendor/include/"
cp    "$CONDUIT_DEPS/include/zenoh-pico.h" "$ROOT/Vendor/include/"
cp -R "$CONDUIT_DEPS/include/dds"   "$ROOT/Vendor/include/"
cp -R "$CONDUIT_DEPS/include/ddsc"  "$ROOT/Vendor/include/"

# pkg-config files default to macos-arm64 (what `swift test` links).
# For xcodebuild/iOS builds the xcframework (Phase 2) replaces this.
cat > "$ROOT/Vendor/pkgconfig/ZenohPico.pc" <<'EOF'
prefix=${pcfiledir}/../..
Name: ZenohPico
Description: zenoh-pico (local bootstrap .a for macOS-arm64)
Version: 1.1.0
Cflags: -I${prefix}/Vendor/include
Libs: -L${prefix}/Vendor/macos-arm64 -lzenohpico
EOF

cat > "$ROOT/Vendor/pkgconfig/CycloneDDS.pc" <<'EOF'
prefix=${pcfiledir}/../..
Name: CycloneDDS
Description: Eclipse Cyclone DDS (local bootstrap .a for macOS-arm64)
Version: 0.10.5
Cflags: -I${prefix}/Vendor/include
Libs: -L${prefix}/Vendor/macos-arm64 -lddsc
EOF

echo "Bootstrap complete. Export PKG_CONFIG_PATH=$ROOT/Vendor/pkgconfig before 'swift build' / 'swift test'."
