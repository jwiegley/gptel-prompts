#!/usr/bin/env bash
set -euo pipefail

# Check benchmark results against baseline (5% regression threshold).
# Usage: scripts/check-benchmark.sh

BASELINE_FILE=".bench-baseline"

RESULTS=$(emacs --batch -L . -L test \
  -l gptel-prompts-bench \
  --eval "(gptel-prompts-bench-report)" 2>/dev/null)

echo "Benchmark results:"
echo "$RESULTS"

if [ -f "$BASELINE_FILE" ]; then
  FAIL=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name=$(echo "$line" | awk '{print $1}')
    time=$(echo "$line" | awk '{print $2}')
    baseline_time=$(grep "^$name " "$BASELINE_FILE" | awk '{print $2}')
    if [ -n "$baseline_time" ]; then
      exceeded=$(awk -v t="$time" -v b="$baseline_time" \
        'BEGIN { print (t > b * 1.05) ? "1" : "0" }')
      if [ "$exceeded" = "1" ]; then
        echo "FAIL: $name regressed from ${baseline_time}s to ${time}s (>5%)"
        FAIL=1
      fi
    fi
  done <<< "$RESULTS"
  if [ "$FAIL" -eq 1 ]; then
    exit 1
  fi
  echo "OK: All benchmarks within 5% of baseline"
else
  echo "No baseline found. Saving current results as baseline."
  echo "$RESULTS" > "$BASELINE_FILE"
fi
