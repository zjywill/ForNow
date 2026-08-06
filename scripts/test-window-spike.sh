#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/bootstrap.sh"
xcodebuild \
  -quiet \
  -project "$ROOT/ForNow.xcodeproj" \
  -scheme WindowSpike \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/DerivedData" \
  test
