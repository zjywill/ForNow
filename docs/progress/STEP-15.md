# Step 1.5 - Alpha Search

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Evidence: `AN-NAV-006`
- Requirement: `FR-NOTE-007`
- Tests: `UT-NOTE-007`, `IT-NOTE-007`, `UIT-NOTE-007`, `PT-SEARCH-001`

## Files Changed

- `Packages/ForNowCore/Sources/ForNowCore/Dependencies.swift`
- `Packages/ForNowCore/Sources/ForNowCore/Note.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/PersistenceNoteRepository.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/PersistenceStore.swift`
- `Packages/ForNowPersistence/Tests/ForNowPersistenceTests/PersistenceSpikeTests.swift`
- `Packages/ForNowWindowing/Sources/ForNowWindowing/WindowCoordinator.swift`
- `Packages/ForNowWindowing/Sources/ForNowWindowing/WindowVisibilityStateMachine.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/ForNowCommands.swift`
- `App/NoteSessionModel.swift`
- `App/NoteSearchModel.swift`
- `App/NoteSearchOverlay.swift`
- `App/NoteSearchCommandField.swift`
- `App/NoteSearchAccessibilityView.swift`
- `Tests/ForNowTests/NoteSearchTests.swift`
- `docs/02_ARCHITECTURE.md`

## Behavior Contract

- Command-F presents a command-palette-style overlay in the existing main
  window and focuses its native search field without another click.
- Opening search commits marked text, reads live `NSTextView.string`, prepares
  the current note, and awaits repository flush before returning results.
- Empty input covers every active row in descending working order. Ordinary
  nonempty input uses FTS5; queries containing CJK scalars use deterministic
  literal matching.
- Results load in 50-note pages. Persistence bounds callers to 200 rows and
  reads one look-ahead row to report `hasMore`.
- Query changes cancel the prior task. Generation and normalized-query checks
  prevent a late result from replacing a newer query.
- Each row displays a bounded first-line title, context excerpt, and modified
  date. Duplicate titles remain distinguishable.
- Up and Down clamp selection to valid results. Enter promotes and opens through
  the same `promoteAndOpen(noteID:)` operation as Command-Shift-1. Escape closes
  search and restores Scratchpad focus.
- Search holds an owned command-picker auto-hide suspension until dismissal.
- Every result exposes a native accessibility button label containing title,
  context, and modified time; the current result exposes value `Selected`.

## Automated Evidence

- Main application tests: 38 passed, 0 failed, 0 skipped in the latest search
  integration run.
- `UT-NOTE-007` covers empty-query pagination, arrow bounds, cancellation of a
  superseded query, duplicate-title context, VoiceOver descriptions, and exact
  live marked-text preparation.
- `UIT-NOTE-007` edits immediately before opening search, verifies the source is
  flushed, activates the matching result, preserves its UUID, and verifies that
  it becomes first in repository order.
- Persistence tests: 17 passed. `IT-NOTE-007` covers empty and FTS pages and
  note/FTS deletion parity.
- `PT-SEARCH-001` seeded 10,000 real GRDB/FTS rows, warmed the index, and measured
  a final 20-sample first-page p95 of 11.474083 ms against the 50 ms exit budget.
- Editor projection tests passed 14/14, window tests passed 10/10, and
  persistence tests passed 17/17. Traceability passed 65/65 evidence, 69/69
  requirements, and 493 mapped test IDs.
- Formatting, generated-project comparison, Debug and Release builds, and
  `git diff --check` passed. Unified-log and application-data scans contained no
  Step 1.3, Step 1.4, Step 1.5, or end-to-end source fixtures.
- Signed UI tests remain unavailable on this host because it has zero valid
  Apple Development identities. The same paths were exercised in the real
  Debug application through macOS Accessibility.

## Real Application Evidence

- Command-F appeared in the real Edit menu and focused the search field. Empty
  input displayed all persisted notes in working order.
- Fixtures `FORNOW_STEP15_ALPHA_20260804_context_keyboard`,
  `FORNOW_STEP15_TARGET_20260804_context_keyboard`, and
  `FORNOW_STEP15_BETA_20260804_context_keyboard` showed distinct first-line and
  context presentations.
- Down selected target ID `BE81D9D9-0A1B-4F94-96CB-2C54DCDBB196`. Enter closed
  search, restored focused Scratchpad with exact target source, retained that
  UUID, and promoted its `orderKey` from 9 to 11.
- Query `target` returned only the target fixture. Escape closed the overlay and
  restored the focused editor.
- The real AX tree exposed each result as `AXButton`. Its description contained
  title, context, and exact modified time; the active row value was `Selected`.
- Traditional Dropdown at its 360 by 280 minimum retained a fully visible search
  field, two complete rows, and a scrollable result region without overlap.
- Standard 620 by 540 mode, dropdown defaults 560 by 560, and the original input
  source were restored. Both possible application data roots were cleaned to
  zero note and FTS rows with `PRAGMA quick_check = ok`.

## Exit Criteria

- 10,000-note warm first page under 50 ms: `PASS` at 11.474083 ms p95.
- Enter uses the same promotion transaction as the editor command: `PASS` in
  shared-method unit coverage and the real application UUID/order exercise.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
