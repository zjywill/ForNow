# Step 3.2 - List Mode

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-06
- Evidence: `AN-LIST-001` through `AN-LIST-003`
- Requirements: `FR-LIST-001` through `FR-LIST-003`
- Tests: `UT-LIST-001A` through `UT-LIST-001F`, `UT-LIST-002`,
  `ET-LIST-002A`, `ET-LIST-002B`, and `UT-LIST-003A` through
  `UT-LIST-003E`

## Files Changed

- `Packages/ForNowModes/Sources/ForNowModes/ListMode.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/EditorProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditingSession.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ClipboardProjection.swift`
- `App/EditorStateStore.swift`
- `App/ModeSettingsStore.swift`
- `App/ModeSettingsSection.swift`
- `App/AppEnvironment.swift`
- `App/SettingsView.swift`
- `Spikes/EditorProjectionSpike/EditorProjectionSpikeApp.swift`
- `Tests/EditorProjectionSpikeTests/ListModeTests.swift`
- `Tests/ForNowTests/AppEnvironmentTests.swift`
- `Tests/ForNowTests/ModeSettingsAndSlashCommandTests.swift`
- `docs/02_ARCHITECTURE.md`
- `README.md`

## Behavior Contract

- Only a valid canonical List Mode header activates item parsing. Every
  non-empty body content line becomes an item except leading-whitespace `//`
  comments and headings one through three. Blank lines stay meaningful source
  separators; level-four headings and embedded marker text remain ordinary
  items.
- The configured checked marker must be non-empty, whitespace-free, and free of
  control characters. It is recognized only as a whitespace-separated trailing
  marker. Invalid settings are rejected before they can become active.
- List Mode emits no calculation or conversion result decorations. Gutter
  checkboxes are source-free controls whose ranges refer only to canonical
  source, while their accessibility roles and values expose checkbox state.
- Pointer click and focused Space route through the same toggle planner. A
  toggle inserts or removes exactly one marker with one editor replacement and
  one undo group, preserving the current caret or selection through Toggle,
  Undo, and Redo.
- Clean copy removes checked markers only from eligible List Mode items when the
  independent export setting is enabled. It preserves comments, headings, and
  literal marker text. Changing the configured marker reparses presentation and
  export output without rewriting existing note source.
- Editor settings storage version 3 adds checklist-marker omission with
  migration defaults for older payloads. Mode settings persist the checked
  marker separately, validate before save, and restore the last valid payload.

## Automated Evidence

- On 2026-08-06, `scripts/test-editor-projection.sh` passed 112 of 112 tests on
  macOS 26.6. Thirteen focused `ListModeTests` plus the existing
  `ET-LIST-002A` integration fixture cover every required `UT-LIST-*` and
  `ET-LIST-*` ID, including item eligibility, math suppression, custom markers,
  pointer/keyboard parity, native checkbox accessibility, exact source edits,
  clean copy, selection stability, and single-step Undo/Redo.
- On 2026-08-06, `scripts/test.sh` passed 55 of 55 main application tests,
  including settings migration, persistence, invalid-payload fallback, and the
  complete existing application regression suite.
- The implementation run also passed 17 persistence tests, 10 window tests,
  both real SIGKILL durability paths, both Release performance tests, Debug and
  Release builds, strict Swift formatting, generated-project comparison, shell
  syntax validation, traceability generation and fault injection, and
  `git diff --check`.
- Traceability reported 65 of 65 evidence entries, 69 of 69 requirements, 493
  mapped test IDs, and 12 decisions. Signed UI tests remain unavailable because
  this host has no Apple Development identity.

## Real Application Evidence

- A Debug application launched with an isolated `CFFIXED_USER_HOME`. Eligible
  lines showed gutter checkboxes; blank lines, comments, and headings one
  through three did not. `20 + 22 =` produced no result in List Mode.
- Pointer activation and focused Space produced the same exact source marker.
  One Command-Z removed that marker and one Command-Shift-Z restored it while
  preserving the selection. Accessibility exposed native checkbox roles and
  `Checked` or `Unchecked` values.
- Clean copy was exercised both enabled and disabled. A custom `done` marker
  survived complete quit and relaunch. Changing between `done` and `/x` changed
  only which lines were presented as checked; existing source was byte-for-byte
  unchanged.
- SQLite and FTS stored identical canonical source containing the original
  markers and no checkbox presentation state. `PRAGMA quick_check` returned
  `ok`. The standard SQLite, WAL, and SHM files retained their exact pre-run
  hash, size, and modification time, and the standard exported preference
  domain retained its pre-run hash.
- The isolated process was fully terminated, the original input source and
  clipboard were restored, and the isolated evidence directory was removed.

## Exit Criteria

- Pointer and keyboard toggles produce identical source edits: `PASS` in the
  shared planner, AppKit event integration, and real application checks.
- Triggers are omitted from clean copy according to settings: `PASS` for the
  default and custom markers, enabled and disabled omission, and exact source
  preservation.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. `scripts/test-ui.sh` exits with status 2 before build,
as designed. Native AppKit integration tests and real-process accessibility
inspection cover the required behavior without waiving future signed UI
coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
