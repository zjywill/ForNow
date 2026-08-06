# Step 0.2 - Freeze Evidence And Requirement Traceability

- Status: `DONE`
- Started: 2026-08-03
- Completed: 2026-08-03
- Evidence reviewed: all `AN-*` entries and `06_MANUAL_WALKTHROUGH.md`
- Requirements implemented: traceability controls for all macOS `FR-*`

## Files Changed

- `docs/traceability.yml`
- `docs/OPEN_QUESTIONS.md`
- `scripts/generate-traceability.rb`
- `scripts/validate-traceability.swift`
- `scripts/test-traceability.sh`
- `.github/workflows/ci.yml`

## Commands Run

- `scripts/generate-traceability.rb`
- `scripts/generate-traceability.rb --check`
- `scripts/validate-traceability.swift`
- `scripts/test-traceability.sh`
- `scripts/validate-ios-docs.rb`
- `scripts/test.sh`
- `xcrun swift-format lint --strict scripts/validate-traceability.swift`
- `ruby -c scripts/generate-traceability.rb`
- `bash -n scripts/test-traceability.sh`
- `git diff --check`

## Automated Test Results

- Generation check: passed.
- macOS traceability validation: passed with 65/65 evidence entries, 69/69
  requirements, 493 expanded test IDs, and 12 defined decisions.
- Unknown evidence injection: rejected as expected.
- Requirement-without-tests injection: rejected as expected.
- Existing iOS documentation validation: passed with 21/21 requirements.
- Application smoke unit test: passed after documentation/tooling changes.

## Manual Test Results

- Every evidence entry has at least one HTTPS source URL from the official
  source set or the ledger's named press-review source.
- Requirement classifications reviewed: 61 parity, 6 product-decision, and 2
  cross-cutting product-quality requirements.
- Release classifications reviewed: 63 macOS 1.0 and 6 post-1.0 requirements.
- No requirement has an empty test list.

## Deviations And Open Questions

- `docs/traceability.yml` uses JSON syntax, which is a valid YAML 1.2 subset.
  This lets the required Swift validator use Foundation `JSONDecoder` without
  adding a YAML runtime dependency to the application or toolchain.
