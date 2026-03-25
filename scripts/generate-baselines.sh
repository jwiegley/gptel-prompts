#!/usr/bin/env bash
set -euo pipefail

# Generate fresh coverage and benchmark baselines.
# Run this after writing or updating tests.
# Usage: scripts/generate-baselines.sh

cd "$(git rev-parse --show-toplevel)"

echo "=== Generating coverage baseline ==="
rm -f .coverage-baseline
scripts/check-coverage.sh
echo ""

echo "=== Generating benchmark baseline ==="
rm -f .bench-baseline
scripts/check-benchmark.sh
echo ""

echo "Done. Commit .coverage-baseline and .bench-baseline to track regressions."
