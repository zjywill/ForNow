# Step 4.2 - OCR

- Status: `DONE`
- Started: 2026-08-06
- Completed: 2026-08-06
- Evidence: `AN-OCR-001`, `AN-OCR-002`
- Requirements: `FR-OCR-001`, `FR-OCR-002`, `FR-OCR-003`
- Decision: `FORNOW-DECISION-014`
- Required tests: `UT-OCR-001`, `IT-OCR-001A` through `IT-OCR-001F`,
  `IT-OCR-002`, `ST-OCR-001`, `ST-OCR-002`, `MT-OCR-002`, and
  `ET-OCR-003A` through `ET-OCR-003E`

## Files Changed

- `docs/ocr/OCR_V1.md`
- `docs/decisions/ADR-005_OCR_INPUT_AND_INSERTION.md`
- `App/OCRSettingsStore.swift`
- `App/OCRWorkflowModel.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/SettingsView.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/OCRInsertion.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/OCRService.swift`
- `Tests/EditorProjectionSpikeTests/OCRInsertionTests.swift`
- `Tests/ForNowTests/OCRWorkflowTests.swift`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/00_SOURCE_LEDGER.md`
- `docs/01_PRODUCT_SPEC.md`
- `docs/02_ARCHITECTURE.md`
- `docs/04_TEST_MATRIX.md`
- `docs/traceability.yml`
- `README.md`

## Behavior Contract

- Contract `fornow-ocr-v1` accepts actual PNG, JPEG, and one-frame GIF input.
  AppKit TIFF clipboard transport is normalized to PNG; TIFF files remain
  unsupported. Encoded input is limited to 20 MiB and decoded area to 40 MP.
- Paste captures the selection and image-first precedence. Finder drag/drop
  captures the pointer's source insertion position. File bytes are read under
  bounded security-scoped access, and images are never persisted.
- Local Vision uses accurate recognition, language correction, cancellation,
  and persistent Automatic, System Preferred, or explicit language choices.
  One generation-owned request is active; a replacement invalidates the prior
  completion.
- A source-versioned UTF-16 anchor inserts at the captured range only while it
  remains current. Changed source requires confirmation at the current cursor.
  The final recognized text is one undoable canonical source edit.
- Progress, cancel, errors, confirmation, image bytes, confidence, and Vision
  state remain outside source, SQLite, FTS, clean copy, and Undo history.

## Automated Evidence

- `OCRWorkflowTests` passes 12 of 12 tests. It covers PNG, JPEG, static GIF,
  animated GIF and TIFF rejection, malformed input, byte and pixel limits,
  English, Simplified Chinese, mixed English/CJK, system-preferred mapping, low
  contrast, rotation, empty content, language persistence, stale confirmation,
  and cancellation.
- `OCRInsertionTests` passes 6 of 6 tests. It covers paste selection, Finder-drop
  position, unchanged and changed source versions, exactly one Undo/Redo, and
  canonical recognized source.
- The complete Editor Projection suite passes 244 of 244 tests. The complete
  main application suite passes 88 of 88 tests. Neither suite has failures,
  expected failures, or skips.
- Persistence passes 18 of 18 tests plus both crash-fault workers. The window
  suite passes 11 of 11 tests. Release performance passes 3 of 3 tests, and the
  10,000-note warm FTS first-page p95 is 12.50 ms against the 50 ms bound.
- Debug and Release unsigned builds, strict Swift formatting, generated-project
  comparison, traceability generation and validation, both traceability fault
  injections, and `git diff --check` pass. Traceability maps 65 of 65 evidence
  entries, 69 of 69 requirements, 494 test IDs, and 14 decisions.

## Real Application Evidence

- A current Debug application ran with an isolated application-support home.
  PNG, JPEG, and static GIF clipboard images recognized `PNG LOCAL OCR`,
  `JPEG VISION TEXT`, and `STATIC GIF TEXT`. Progress exposed a busy indicator,
  visible `Recognizing text`, and an independently accessible cancel button.
- Finder drag of the static GIF into the real editor inserted its recognized
  text at the pointer position without activating ForNow. One Undo removed the
  complete drop insertion. The initial PNG insertion also required exactly one
  Undo and one Redo restored it.
- Editing source while a 21.6 MP request was active produced the documented
  stale-position sheet. Confirming inserted at the current cursor rather than
  reusing the old anchor. Malformed PNG displayed a recoverable
  `Text Recognition Failed` sheet and left source unchanged.
- A 40 MP, 3.5 MB JPEG exposed the progress text and accessible cancel control.
  Activating Cancel removed progress and produced no late source insertion.
- Language changed from Automatic to Simplified Chinese, survived quit and
  relaunch, and was restored to Automatic after evidence collection. The
  serialized version-1 setting matched the visible value.
- A 60-sample `lsof` monitor at 50 ms intervals covered recognition by the real
  process and observed no IPv4 or IPv6 socket. Rest-state inspection also found
  no network socket.
- After normal Quit, `Note.body` and its FTS row were byte-identical at 394
  bytes, contained recognized text only, and excluded progress/error strings.
  `PRAGMA quick_check` returned `ok`; no ForNow process remained.

## Exit Criteria

- Network monitor confirms no OCR request: `PASS` in `ST-OCR-001` real-process
  socket monitoring.
- Supported formats, rotation, CJK, mixed content, low contrast, empty images,
  resource bounds, and cancellation have fixtures: `PASS` in focused automated
  suites and real-app PNG/JPEG/GIF evidence.
- Captured position, stale confirmation, cancellation, and one Undo preserve
  canonical source: `PASS` in `ET-OCR-003A...E`, real AppKit interaction, and
  SQLite/FTS inspection.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. Native AppKit integration tests and isolated real-process
Accessibility inspection cover the implemented Step 4.2 paths without waiving
future signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
