#!/usr/bin/env bash
# Bootstrap Vendor/ with pre-built CycloneDDS + zenoh-pico static libs
# from the parent Conduit checkout (deps/maccatalyst). Used during Phase 1
# so `swift build` can compile the Swift layer before xcframeworks are
# published in Phase 2. Safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONDUIT_DEPS="${CONDUIT_DEPS:-$ROOT/../../deps}"

if [ ! -f "$CONDUIT_DEPS/maccatalyst/libzenohpico.a" ]; then
    echo "error: $CONDUIT_DEPS/maccatalyst/libzenohpico.a not found." >&2
    echo "Build Conduit deps first: SDK=maccatalyst bash $CONDUIT_DEPS/../scripts/build_deps.sh" >&2
    exit 1
fi

mkdir -p "$ROOT/Vendor/maccatalyst-arm64" "$ROOT/Vendor/include" "$ROOT/Vendor/pkgconfig"

cp "$CONDUIT_DEPS/maccatalyst/libzenohpico.a" "$ROOT/Vendor/maccatalyst-arm64/"
cp "$CONDUIT_DEPS/maccatalyst/libddsc.a" "$ROOT/Vendor/maccatalyst-arm64/"
cp -R "$CONDUIT_DEPS/include/zenoh-pico" "$ROOT/Vendor/include/"
cp "$CONDUIT_DEPS/include/zenoh-pico.h" "$ROOT/Vendor/include/"
cp -R "$CONDUIT_DEPS/include/dds" "$ROOT/Vendor/include/"
cp -R "$CONDUIT_DEPS/include/ddsc" "$ROOT/Vendor/include/"

cat > "$ROOT/Vendor/pkgconfig/ZenohPico.pc" <<'EOF'
prefix=${pcfiledir}/../..
Name: ZenohPico
Description: zenoh-pico (local bootstrap .a for macCatalyst-arm64)
Version: 1.1.0
Cflags: -I${prefix}/Vendor/include
Libs: -L${prefix}/Vendor/maccatalyst-arm64 -lzenohpico
EOF

cat > "$ROOT/Vendor/pkgconfig/CycloneDDS.pc" <<'EOF'
prefix=${pcfiledir}/../..
Name: CycloneDDS
Description: Eclipse Cyclone DDS (local bootstrap .a for macCatalyst-arm64)
Version: 0.10.5
Cflags: -I${prefix}/Vendor/include
Libs: -L${prefix}/Vendor/maccatalyst-arm64 -lddsc
EOF

echo "Bootstrap complete. Export PKG_CONFIG_PATH=$ROOT/Vendor/pkgconfig before 'swift build'."
