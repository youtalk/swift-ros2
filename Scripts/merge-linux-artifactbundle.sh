#!/usr/bin/env bash
# Merge per-triple staging directories (produced by build-linux-artifactbundle.sh)
# into a single .artifactbundle, emit info.json, zip, and emit the .checksum.
#
# Usage: Scripts/merge-linux-artifactbundle.sh <package> <staging-root> <out-dir>
#   <package>: 'zenoh-pico' | 'cyclonedds'
#   <staging-root>: directory containing one subdirectory per triple
#                   (e.g. staging/x86_64-unknown-linux-gnu/, staging/aarch64-unknown-linux-gnu/)
#   <out-dir>: directory to place the final .artifactbundle.zip + .checksum
set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <zenoh-pico|cyclonedds> <staging-root> <out-dir>" >&2
    exit 1
fi

PKG="$1"
STAGING="$2"
OUT="$3"

case "$PKG" in
    zenoh-pico)  FRAMEWORK="CZenohPico"  ; LIB="libzenohpico.a" ;;
    cyclonedds)  FRAMEWORK="CCycloneDDS" ; LIB="libddsc.a"      ;;
    *) echo "error: unknown package '$PKG'" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=0.5.0    # bumped per release; overridden by SWIFT_ROS2_VERSION env if set
VERSION="${SWIFT_ROS2_VERSION:-$VERSION}"

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
STAGING="$(cd "$STAGING" && pwd)"

BUNDLE="$OUT/${FRAMEWORK}-linux.artifactbundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/${FRAMEWORK}-${VERSION}-linux" "$BUNDLE/include"

# L1 finding: SwiftPM resolves staticLibraryMetadata.headerPaths relative to
# the bundle root, not the variant path. Share headers across triples in a
# single include/ at bundle root. Variant path points at the .a file itself.
COPIED_INCLUDE=0
VARIANTS_JSON=""
for triple_dir in "$STAGING"/*/; do
    triple=$(basename "$triple_dir")
    dest="$BUNDLE/${FRAMEWORK}-${VERSION}-linux/$triple/lib"
    mkdir -p "$dest"
    cp "$triple_dir/lib/$LIB" "$dest/"

    if [[ $COPIED_INCLUDE -eq 0 ]]; then
        cp -r "$triple_dir/include/." "$BUNDLE/include/"
        COPIED_INCLUDE=1
    fi

    [[ -n "$VARIANTS_JSON" ]] && VARIANTS_JSON+=","
    VARIANTS_JSON+=$(cat <<VAR
        {
          "path": "${FRAMEWORK}-${VERSION}-linux/$triple/lib/$LIB",
          "supportedTriples": ["$triple"],
          "staticLibraryMetadata": {
            "headerPaths": ["include"]
          }
        }
VAR
)
done

cat > "$BUNDLE/info.json" <<JSON
{
  "schemaVersion": "1.0",
  "artifacts": {
    "$FRAMEWORK": {
      "type": "staticLibrary",
      "version": "$VERSION",
      "variants": [
$VARIANTS_JSON
      ]
    }
  }
}
JSON

echo "==> bundle assembled: $BUNDLE"
find "$BUNDLE" -type f | head -20 || true

echo "==> zipping"
(cd "$OUT" && rm -f "${FRAMEWORK}-linux.artifactbundle.zip" && zip -r -q "${FRAMEWORK}-linux.artifactbundle.zip" "$(basename "$BUNDLE")")

echo "==> computing checksum"
swift package --package-path "$ROOT" compute-checksum "$OUT/${FRAMEWORK}-linux.artifactbundle.zip" \
    > "$OUT/${FRAMEWORK}-linux.artifactbundle.zip.checksum"

echo ""
echo "done:"
echo "  $BUNDLE"
echo "  $OUT/${FRAMEWORK}-linux.artifactbundle.zip ($(du -h "$OUT/${FRAMEWORK}-linux.artifactbundle.zip" | awk '{print $1}'))"
echo "  $OUT/${FRAMEWORK}-linux.artifactbundle.zip.checksum ($(cat "$OUT/${FRAMEWORK}-linux.artifactbundle.zip.checksum"))"
