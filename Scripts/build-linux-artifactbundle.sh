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
        cmake -S "$ROOT/vendor/cyclonedds" -B "$WORK" \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_SHARED_LIBS=OFF \
            -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
            -DCMAKE_INSTALL_PREFIX="$WORK/install" \
            -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
            -DBUILD_EXAMPLES=OFF \
            -DBUILD_TESTING=OFF \
            -DBUILD_DDSPERF=OFF \
            -DBUILD_IDLC=OFF \
            -DENABLE_SSL=OFF \
            -DENABLE_SECURITY=OFF \
            -DENABLE_SHM=OFF \
            -DENABLE_LTO=OFF \
            -DENABLE_QOS_PROVIDER=OFF \
            -DENABLE_LIFESPAN=ON \
            -DENABLE_DEADLINE_MISSED=ON \
            -DENABLE_TYPE_DISCOVERY=OFF \
            -DENABLE_TOPIC_DISCOVERY=OFF
        cmake --build "$WORK" --parallel "$(nproc)"
        cmake --install "$WORK"

        # Static library
        cp "$WORK/install/lib/libddsc.a" "$OUT/$TRIPLE/lib/"

        # Public headers (from install step)
        cp -r "$WORK/install/include/." "$OUT/$TRIPLE/include/"

        # Internal headers consumed by Sources/CDDSBridge.
        # The copy list is verified in L3.2 by grepping CDDSBridge sources.
        mkdir -p "$OUT/$TRIPLE/include/dds/ddsi" "$OUT/$TRIPLE/include/dds/ddsrt"
        cp "$ROOT/vendor/cyclonedds/src/core/ddsi/include/dds/ddsi/ddsi_sertype.h" "$OUT/$TRIPLE/include/dds/ddsi/"
        cp "$ROOT/vendor/cyclonedds/src/core/ddsi/include/dds/ddsi/ddsi_serdata.h" "$OUT/$TRIPLE/include/dds/ddsi/"
        cp "$ROOT/vendor/cyclonedds/src/core/ddsi/include/dds/ddsi/q_radmin.h"      "$OUT/$TRIPLE/include/dds/ddsi/"
        cp "$ROOT/vendor/cyclonedds/src/ddsrt/include/dds/ddsrt/heap.h"             "$OUT/$TRIPLE/include/dds/ddsrt/"
        cp "$ROOT/vendor/cyclonedds/src/ddsrt/include/dds/ddsrt/md5.h"              "$OUT/$TRIPLE/include/dds/ddsrt/"

        # Verify the copied internal headers cover every #include used by
        # CDDSBridge. Fails the build if CDDSBridge grows a new internal
        # include without updating the copy list above.
        REQUIRED_HEADERS=$(grep -rhoE '#include[[:space:]]+["<]dds/(ddsi|ddsrt)/[^">]+[">]' \
            "$ROOT/Sources/CDDSBridge/" | sed -E 's/.*["<](dds[^">]+)[">].*/\1/' | sort -u)
        for h in $REQUIRED_HEADERS; do
            if [[ ! -f "$OUT/$TRIPLE/include/$h" ]]; then
                echo "error: CDDSBridge includes <$h> but it is not in the bundle." >&2
                echo "Update the internal header copy list in Scripts/build-linux-artifactbundle.sh." >&2
                exit 1
            fi
        done
        echo "==> verified: all $(echo "$REQUIRED_HEADERS" | wc -w) CDDSBridge internal includes are bundled"
        ;;
esac

echo "==> done: $OUT/$TRIPLE/lib/$(ls "$OUT/$TRIPLE/lib")"
