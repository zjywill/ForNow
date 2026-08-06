# Step 0.3 - Editor Projection Spike

- Status: `DONE`
- Started: 2026-08-03
- Completed: 2026-08-03
- Evidence reviewed: `AN-TXT-001`, `AN-TXT-003`, `AN-CLIP-001`,
  `AN-LIST-002`, `AN-MATH-001`
- Requirements: `FR-EDIT-001`, `FR-EDIT-002`, `FR-EDIT-004`,
  `FR-EDIT-005`, `FR-EDIT-006`
- Tests: `UT-EDIT-001`, `UT-EDIT-002A` through `UT-EDIT-002F`,
  `UT-EDIT-004A` through `UT-EDIT-004L`, `ET-EDIT-005A` through
  `ET-EDIT-005H`, `ET-EDIT-006A` through `ET-EDIT-006G`

## Files Changed

- `Packages/ForNowEditor/`
- `Spikes/EditorProjectionSpike/`
- `Tests/EditorProjectionSpikeTests/`
- `docs/decisions/ADR-001_EDITOR_DECORATIONS.md`
- `docs/progress/assets/editor-projection-spike.png`
- `project.yml`
- `scripts/test-editor-projection.sh`

## Commands Run

```bash
scripts/format.sh --fix
scripts/format.sh
scripts/test-editor-projection.sh
xcodebuild -quiet -project ForNow.xcodeproj \
  -scheme EditorProjectionSpike \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build
open -n DerivedData/Build/Products/Debug/EditorProjectionSpike.app
screencapture -x -l 361 \
  docs/progress/assets/editor-projection-spike.png
scripts/test-traceability.sh
scripts/check-generated-project.sh
scripts/test.sh
git diff --check
```

## Automated Test Results

- `EditorProjectionSpikeTests`: 12 tests passed.
- UTF-16 round trips passed for ASCII, Chinese, Emoji, composed accents,
  multiline text, and Arabic.
- Multiline copy returned the exact source range.
- Edits before, inside, and after decorated source survived three undo and
  three redo operations.
- Actual `NSTextView.setMarkedText` retained marked state until `unmarkText`.
- Duplicate URLs retained exact source and stable display suffixes.
- 500 randomized Unicode edits preserved source, projection version, range,
  and selection-bound invariants.
- Traceability validation passed with 65/65 evidence entries, 69/69 macOS
  requirements, 493 mapped test IDs, and 12 defined decisions.
- Main `ForNowTests` smoke test and generated-project check passed.
- Formatting and `git diff --check` passed.

## Manual Test Results

- Inspected `docs/progress/assets/editor-projection-spike.png` at 1744 x 1464.
  Checkbox, fake calculation result, duplicate shortened links, Chinese, Emoji,
  and composed-accent fixtures rendered without overlap or clipping.
- Clicking the checkbox changed only `[ ]` to `[x]`. Command-Z restored `[ ]`;
  Command-Shift-Z restored `[x]`.
- Clicking a shortened link copied the exact source URL
  `https://example.com/a/very/long/path/to/source`.
- Clicking the calculation result copied canonical value `42`.
- Accessibility inspection exposed the checkbox, both links, and result as
  labeled buttons within the source text area.
- The text area's accessibility value remained source-only; display text and
  result characters did not enter it.

## Deviations And Open Questions

- A first screenshot attempt captured a still-running older spike process.
  All spike processes were terminated, the latest binary was launched once,
  and window ID 361 was queried immediately before the final capture.
- Running `scripts/test.sh` concurrently with
  `scripts/check-generated-project.sh` caused a transient SwiftPM resolution
  failure because both regenerate `ForNow.xcodeproj`. Both commands passed when
  rerun serially; project-mutating gates must remain serial.
- The accepted strategy is overlay adornments anchored to TextKit 2 source
  ranges. Attachment-backed rendering remains forbidden; custom layout
  fragments remain a targeted fallback for geometry-changing decorations.
