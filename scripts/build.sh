#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"

"$ROOT/scripts/bootstrap.sh"
xcodebuild \
  -quiet \
  -project "$ROOT/ForNow.xcodeproj" \
  -scheme ForNow \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build
