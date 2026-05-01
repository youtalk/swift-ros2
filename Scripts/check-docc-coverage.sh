#!/usr/bin/env bash
# check-docc-coverage.sh
# Fail when any public Swift declaration in Sources/ lacks a /// comment
# on the immediately preceding line. Exempts re-export-only files and
# generated stubs.

set -euo pipefail

cd "$(dirname "$0")/.."

declare -a EXEMPT_FILES=(
  "Sources/SwiftROS2/Exports.swift"
)

is_exempt() {
  for f in "${EXEMPT_FILES[@]}"; do
    [[ "$1" == "$f" ]] && return 0
  done
  return 1
}

violations=0

while IFS= read -r file; do
  if is_exempt "$file"; then continue; fi
  awk -v file="$file" '
    /^public (final |class |struct |protocol |enum |typealias |func |let |var |actor )/ {
      if (prev !~ /^\/\/\//) {
        print file ":" NR ": " $0
        bad++
      }
    }
    { prev = $0 }
    END { exit (bad > 0 ? 1 : 0) }
  ' "$file" || violations=$((violations + 1))
done < <(find Sources -name "*.swift" -type f)

if [[ "$violations" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: $violations file(s) had public declarations without /// comments." >&2
  exit 1
fi

echo "OK: every public declaration in Sources/ has a /// comment."
