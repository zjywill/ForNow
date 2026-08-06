#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"

"$ROOT/scripts/bootstrap.sh"
xcodebuild \
  -quiet \
  -project "$ROOT/ForNow.xcodeproj" \
  -scheme ForNowPerformanceTests \
  -configuration Release \
  -destination "platform=macOS,arch=$ARCH" \
  -derivedDataPath "$ROOT/DerivedData" \
  test
