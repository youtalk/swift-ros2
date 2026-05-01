#!/usr/bin/env bash
# coverage-gate.sh
# Compare per-target line coverage against the declared minimums in
# Scripts/coverage-thresholds.txt and exit non-zero on any breach.
#
# Reads `xcrun llvm-cov report -summary-only` output on stdin or as the
# first positional file argument. Output is the report itself (passed
# through) plus a final pass/fail summary on stderr.
#
# Usage:
#   xcrun llvm-cov report ... -summary-only | Scripts/coverage-gate.sh
#   Scripts/coverage-gate.sh path/to/coverage-summary.txt

set -euo pipefail

THRESHOLDS_FILE="$(dirname "$0")/coverage-thresholds.txt"

if [[ ! -f "$THRESHOLDS_FILE" ]]; then
  echo "ERROR: thresholds file not found at $THRESHOLDS_FILE" >&2
  exit 2
fi

# Read the report — argument-or-stdin.
if [[ $# -ge 1 ]]; then
  REPORT="$(cat "$1")"
else
  REPORT="$(cat)"
fi

# Echo the report so CI users can still see it.
echo "$REPORT"

# Parse thresholds into parallel arrays (bash 3.2 compatible — no declare -A).
THRESHOLD_KEYS=()
THRESHOLD_VALS=()
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
  key=$(echo "$key" | tr -d '[:space:]')
  value=$(echo "$value" | tr -d '[:space:]')
  THRESHOLD_KEYS+=("$key")
  THRESHOLD_VALS+=("$value")
done < "$THRESHOLDS_FILE"

# Helper: look up threshold for a target name; prints empty string if absent.
threshold_for() {
  local name="$1"
  local i
  for i in "${!THRESHOLD_KEYS[@]}"; do
    if [[ "${THRESHOLD_KEYS[$i]}" == "$name" ]]; then
      echo "${THRESHOLD_VALS[$i]}"
      return
    fi
  done
}

# llvm-cov -summary-only emits one line per source file plus a TOTAL line.
# With -ignore-filename-regex stripping the leading path, filenames appear as
# <Target>/File.swift (e.g. SwiftROS2CDR/CDREncoder.swift). We aggregate
# per-target by the first path component. Coverage values shown by llvm-cov
# in summary mode are the rightmost percentage column; for line coverage that
# column matches the "Lines: %" header. We rely on the layout being:
#
#   Filename  Regions Missed Cover  Functions Missed Cover  Lines Missed Cover  Branches Missed Cover
#
# and pick columns from the right to stay robust across llvm-cov versions.

# Per-target totals and covered counts (parallel arrays keyed by index in
# THRESHOLD_KEYS so we reuse the already-parsed list).
TARGET_TOTAL=()
TARGET_COVERED=()
for i in "${!THRESHOLD_KEYS[@]}"; do
  TARGET_TOTAL+=(0)
  TARGET_COVERED+=(0)
done

HAS_BRANCHES=$(echo "$REPORT" | head -1 | grep -c "Branches" || true)

while IFS= read -r line; do
  case "$line" in
    Filename*|---*|TOTAL*|"") continue ;;
  esac
  # Lines appear as <Target>/File.swift ... — must contain a slash in field 1.
  filename=$(echo "$line" | awk '{print $1}')
  case "$filename" in
    */*) ;;
    *) continue ;;
  esac

  # Parse target = first path segment (SwiftROS2CDR from SwiftROS2CDR/CDREncoder.swift).
  target=$(echo "$filename" | awk -F/ '{print $1}')
  [[ -z "$target" ]] && continue

  # Find index of this target in our threshold list; skip if not gated.
  idx=-1
  for i in "${!THRESHOLD_KEYS[@]}"; do
    if [[ "${THRESHOLD_KEYS[$i]}" == "$target" ]]; then
      idx=$i
      break
    fi
  done
  [[ "$idx" -eq -1 ]] && continue

  if [[ "$HAS_BRANCHES" -ge 1 ]]; then
    total=$(echo "$line" | awk '{print $(NF-5)}')
    missed=$(echo "$line" | awk '{print $(NF-4)}')
  else
    total=$(echo "$line" | awk '{print $(NF-2)}')
    missed=$(echo "$line" | awk '{print $(NF-1)}')
  fi

  # Defensive: total must be a non-negative integer.
  [[ ! "$total" =~ ^[0-9]+$ ]] && continue
  [[ ! "$missed" =~ ^[0-9]+$ ]] && continue

  TARGET_TOTAL[$idx]=$(( TARGET_TOTAL[$idx] + total ))
  TARGET_COVERED[$idx]=$(( TARGET_COVERED[$idx] + total - missed ))
done <<< "$REPORT"

echo
echo "=== Coverage gate ==="
exit_code=0
for i in "${!THRESHOLD_KEYS[@]}"; do
  target="${THRESHOLD_KEYS[$i]}"
  total="${TARGET_TOTAL[$i]}"
  covered="${TARGET_COVERED[$i]}"
  threshold="${THRESHOLD_VALS[$i]}"
  if [[ "$total" -eq 0 ]]; then
    printf "FAIL  %-22s no source lines counted (target absent from report?)\n" "$target" >&2
    exit_code=1
    continue
  fi
  # Compute percentage as integer with one-decimal precision (covered*1000 / total).
  pct_x10=$(( covered * 1000 / total ))
  pct_int=$(( pct_x10 / 10 ))
  pct_dec=$(( pct_x10 % 10 ))
  if [[ "$pct_int" -ge "$threshold" ]]; then
    printf "PASS  %-22s %d.%d%% >= %s%%\n" "$target" "$pct_int" "$pct_dec" "$threshold"
  else
    printf "FAIL  %-22s %d.%d%% < %s%%\n" "$target" "$pct_int" "$pct_dec" "$threshold" >&2
    exit_code=1
  fi
done

exit "$exit_code"
