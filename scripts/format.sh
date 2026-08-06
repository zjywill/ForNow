#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---lint}"
PATHS=(App Packages Tests UITests PerformanceTests)

cd "$ROOT"
if [[ "$MODE" == "--fix" ]]; then
  xcrun swift-format format --in-place --recursive "${PATHS[@]}"
else
  xcrun swift-format lint --strict --recursive "${PATHS[@]}"
fi
