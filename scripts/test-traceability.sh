#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-traceability.swift"
TRACE="$ROOT/docs/traceability.yml"
TEMP_DIR="$(mktemp -d)"

"$ROOT/scripts/generate-traceability.rb" --check
"$VALIDATOR"

UNKNOWN_EVIDENCE="$TEMP_DIR/unknown-evidence.yml"
ruby -rjson -e '
  data = JSON.parse(File.read(ARGV[0]))
  first = data.fetch("requirements").keys.sort.first
  data.fetch("requirements").fetch(first).fetch("evidence") << "AN-INVALID-999"
  File.write(ARGV[1], JSON.pretty_generate(data))
' "$TRACE" "$UNKNOWN_EVIDENCE"
if TRACEABILITY_FILE="$UNKNOWN_EVIDENCE" "$VALIDATOR" >/dev/null 2>&1; then
  echo "validator accepted an unknown evidence ID" >&2
  exit 1
fi

ORPHAN_REQUIREMENT="$TEMP_DIR/orphan-requirement.yml"
ruby -rjson -e '
  data = JSON.parse(File.read(ARGV[0]))
  first = data.fetch("requirements").keys.sort.first
  data.fetch("requirements").fetch(first)["tests"] = []
  File.write(ARGV[1], JSON.pretty_generate(data))
' "$TRACE" "$ORPHAN_REQUIREMENT"
if TRACEABILITY_FILE="$ORPHAN_REQUIREMENT" "$VALIDATOR" >/dev/null 2>&1; then
  echo "validator accepted a requirement without tests" >&2
  exit 1
fi

echo "traceability fault injection: PASS"
