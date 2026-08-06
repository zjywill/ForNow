#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! security find-identity -v -p codesigning | grep -q '"Apple Development'; then
  echo "UI tests require an Apple Development signing identity on macOS 26." >&2
  exit 2
fi

"$ROOT/scripts/bootstrap.sh"
xcodebuild \
  -quiet \
  -project "$ROOT/ForNow.xcodeproj" \
  -scheme ForNowUITests \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/DerivedData" \
  test
