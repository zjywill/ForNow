#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODEGEN_VERSION="2.45.4"
XCODEGEN_SHA256="090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef"
TOOL_ROOT="$ROOT/.build/tools/xcodegen/$XCODEGEN_VERSION"
ARCHIVE="$TOOL_ROOT/xcodegen.zip"
XCODEGEN="$TOOL_ROOT/xcodegen/bin/xcodegen"

if [[ ! -x "$XCODEGEN" ]]; then
  mkdir -p "$TOOL_ROOT"
  curl --fail --location --silent --show-error \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip" \
    --output "$ARCHIVE"
  echo "$XCODEGEN_SHA256  $ARCHIVE" | shasum -a 256 --check
  ditto -x -k "$ARCHIVE" "$TOOL_ROOT"
fi

cd "$ROOT"
"$XCODEGEN" generate --spec project.yml
xcodebuild -quiet -resolvePackageDependencies -project ForNow.xcodeproj -scheme ForNow
