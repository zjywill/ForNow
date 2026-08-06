# Step 2.1 - Production Editor Projection

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Evidence: `AN-TXT-001`, `AN-TXT-002`
- Requirements: `FR-EDIT-001`, `FR-EDIT-002`, `FR-EDIT-005`, `FR-EDIT-006`
- Tests: `UT-EDIT-001`, `UT-EDIT-002A` through `UT-EDIT-002F`,
  `ET-EDIT-002`, `ET-EDIT-005A`, `ET-EDIT-006A`, `ET-EDIT-006B`,
  `PT-EDIT-001`

## Files Changed

- `Packages/ForNowEditor/Sources/ForNowEditor/EditorProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionParsing.swift`
- `Packages/ForNowWindowing/Sources/ForNowWindowing/GlobalShortcut.swift`
- `App/ContentView.swift`
- `App/NoteSessionModel.swift`
- `Tests/EditorProjectionSpikeTests/EditorProjectionSpikeTests.swift`
- `Tests/ForNowTests/NoteNavigationTests.swift`
- `PerformanceTests/ForNowPerformanceTests/SmokePerformanceTests.swift`
- `project.yml`
- `scripts/test-performance.sh`
- `docs/02_ARCHITECTURE.md`
- `README.md`

## Behavior Contract

- `NSTextView.string` remains the canonical source. Input callbacks publish the
  new source and source version without parsing synchronously.
- `ProductionProjectionParser` parses in a detached user-initiated task.
  `ProjectionParsePipeline` cancels superseded work and rejects results whose
  request identity or source version is stale, even when a parser ignores
  cooperative cancellation.
- Projection validation discards invalid ranges and emits diagnostics that do
  not include note text. Pipeline telemetry contains counts, versions,
  durations, and decoration totals only.
- Selection uses UTF-16 source coordinates. Selection and vertical scroll
  offset travel through `NoteSessionModel`, the repository draft, navigation,
  and the existing flush path. Restoration tokens prevent repeated SwiftUI
  updates from resetting an active viewport.
- Visible checkbox, link, result, and diagnostic views remain overlays. They are
  exposed beneath one native `AXGroup` named `Editor decorations` and never
  enter source, persistence, or undo history.
- The performance test target is an independent Release XCTest bundle. It does
  not host in or launch `ForNow.app`, avoiding package-product linkage changes
  in the production application.

## Automated Evidence

- Editor projection tests: 19 passed. The randomized Unicode suite completed
  10,000 edits while preserving exact source, source versions, and valid UTF-16
  ranges. Large production parsing cancellation, superseded requests, parser
  version rejection, invalid-range diagnostics, viewport restoration, and the
  native accessibility group all passed.
- Main application tests: 39 passed, including selection and scroll persistence
  across note navigation.
- `PT-EDIT-001` ran 30 Release samples against an exact 50,000-character note:
  p50 `0.001166 ms`, p95 `0.003042 ms`, and worst `0.009833 ms`, below the
  synchronous edit budget of 4 ms. Both performance tests passed in the
  standalone `xctest` runner.
- The performance run used a Mac mini `Mac16,10`, Apple M4, 24 GB memory,
  macOS 26.6 build 25G72, and Xcode 26.6 build 17F113.
- Persistence tests: 17 passed plus both process-kill fault paths. Window tests:
  10 passed. Traceability passed 65/65 evidence, 69/69 requirements, 493 mapped
  test IDs, and fault injection.
- Debug and Release application builds, strict Swift formatting, generated
  project comparison, shell syntax validation, trailing-whitespace scan, and
  `git diff --check` passed. The final unified-log scan contained none of the
  Step 2.1 source fixtures.

## Real Application Evidence

- The current Debug application ran with an isolated `CFFIXED_USER_HOME`; the
  standard user database and preferences were not modified.
- Accessibility applied an exact 50,000-character ordinary note and the editor
  remained focused and queryable. The real window rendered the long note with
  no blank canvas, clipping, or overlay overlap.
- Before leaving the long note, SQLite stored selection `50000/0` and vertical
  scroll offset `25838`. After creating a second note and returning, the editor
  restored the caret at the end, retained the bottom visible range ending at
  character 50,000, and remained focused.
- The real AX tree exposed `Scratchpad` -> `Editor decorations` with three
  adjacent buttons: `Check item`, the original-link description, and
  `Calculation result 42. Copy result`.
- SQLite stored exactly two source bodies of 50,000 and 39 characters, retained
  two matching FTS rows, and returned `PRAGMA quick_check = ok`. The shortened
  link label and rendered `= 42` result were absent from persisted source.
- The app exited through its normal asynchronous shutdown path. The isolated
  application-data directory was removed after exit.

## Exit Criteria

- Randomized editor invariant suite passes 10,000 operations: `PASS`.
- 50,000-character ordinary note remains responsive: `PASS` in the Release
  p95 budget and the real Debug application.
- No parser decoration enters autosave source: `PASS` in editor tests and the
  isolated real SQLite store.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. The production editor paths were exercised in the real
Debug application through macOS Accessibility; this does not waive future
signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
