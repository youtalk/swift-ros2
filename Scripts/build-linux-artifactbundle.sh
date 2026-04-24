#!/usr/bin/env bash
# Build a single-triple staging directory for a Linux .artifactbundle.
# The merge step (Scripts/merge-linux-artifactbundle.sh) combines per-triple
# staging directories into the final bundle.
#
# Usage: Scripts/build-linux-artifactbundle.sh <package> <triple> <out-dir>
#   <package>: 'zenoh-pico' | 'cyclonedds'
#   <triple>:  'x86_64-unknown-linux-gnu' | 'aarch64-unknown-linux-gnu'
#   <out-dir>: staging directory to populate (contents: <triple>/{lib,include})
#
# Expects to run inside an Ubuntu 22.04 environment (glibc 2.35) so the
# resulting static library is forward-compatible with newer distros.
set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <zenoh-pico|cyclonedds> <triple> <out-dir>" >&2
    exit 1
fi

PKG="$1"
TRIPLE="$2"
OUT="$3"

case "$PKG" in
    zenoh-pico|cyclonedds) ;;
    *) echo "error: unknown package '$PKG'" >&2; exit 1 ;;
esac

case "$TRIPLE" in
    x86_64-unknown-linux-gnu|aarch64-unknown-linux-gnu) ;;
    *) echo "error: unsupported triple '$TRIPLE'" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
mkdir -p "$OUT/$TRIPLE/lib" "$OUT/$TRIPLE/include"

WORK="$ROOT/.build/linux-bundle/$PKG-$TRIPLE"
rm -rf "$WORK"
mkdir -p "$WORK"

echo "==> staging $PKG for $TRIPLE into $OUT/$TRIPLE"

case "$PKG" in
    zenoh-pico)
        # L1 finding: zenoh-pico's CMake install puts libzenohpico.a under
        # <install>/lib/, so use the CMake install tree, not the build root.
        cmake -S "$ROOT/vendor/zenoh-pico" -B "$WORK" \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_SHARED_LIBS=OFF \
            -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
            -DCMAKE_INSTALL_PREFIX="$WORK/install" \
            -DZENOH_DEBUG=0 \
            -DZ_FEATURE_LINK_TCP=1 \
            -DZ_FEATURE_LIVELINESS=1
        cmake --build "$WORK" --parallel "$(nproc)"
        cmake --install "$WORK"
        cp "$WORK/install/lib/libzenohpico.a" "$OUT/$TRIPLE/lib/"
        cp -r "$ROOT/vendor/zenoh-pico/include/." "$OUT/$TRIPLE/include/"
        ;;
    cyclonedds)
        echo "error: cyclonedds support added in L3" >&2
        exit 1
        ;;
esac

echo "==> done: $OUT/$TRIPLE/lib/$(ls "$OUT/$TRIPLE/lib")"
