# Step 1.3 - Navigation, Jump, Promote, Delete

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Evidence: `AN-NAV-002` through `AN-NAV-005`, `AN-NAV-007`
- Requirements: `FR-NOTE-003`, `FR-NOTE-004`, `FR-NOTE-005`
- Tests: `UT-NOTE-003`, `UIT-NOTE-003`, `ET-NOTE-003`, `UT-NOTE-004`,
  `IT-NOTE-004A`, `IT-NOTE-004B`, `UIT-NOTE-005A`, `UIT-NOTE-005B`,
  `IT-NOTE-005`

## Files Changed

- `Packages/ForNowCore/Sources/ForNowCore/NoteNavigation.swift`
- `Packages/ForNowCore/Sources/ForNowCore/LifecycleSettings.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/PersistenceNoteRepository.swift`
- `Packages/ForNowPersistence/Tests/ForNowPersistenceTests/PersistenceSpikeTests.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/EditorNavigation.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `App/NoteSessionModel.swift`
- `App/DeleteConfirmationCoordinator.swift`
- `App/ForNowCommands.swift`
- `App/SettingsView.swift`
- `App/AppEnvironment.swift`
- `App/ForNowApp.swift`
- `App/ContentView.swift`
- `Tests/ForNowTests/NoteNavigationTests.swift`
- `Tests/EditorProjectionSpikeTests/EditorProjectionSpikeTests.swift`
- `docs/02_ARCHITECTURE.md`

## Behavior Contract

- Notes are presented newest to oldest by explicit descending `orderKey`.
  Previous moves older; next moves newer.
- Next beyond the newest durable note creates one transient blank. Previous from
  that blank returns to the newest durable note; repeated boundary operations
  do not create rows.
- Navigation, jump, and promotion prepare the current exact source and flush it
  before switching. A first meaningful edit becomes durable under the same
  UUID even when navigation races the application save task.
- Command-left-bracket and Command-right-bracket navigate. Command-1 jumps to
  newest. Command-Shift-1 promotes with a new monotonic ordering token.
- A 60-point horizontal two-finger gesture threshold uses the same navigation
  path as the commands.
- After navigation, Down/Right enters at source start and Up/Left enters at
  source end before normal caret movement resumes.
- Command-D deletes blank source immediately. Meaningful source uses a
  Cancel-first sheet unless warning suppression is persisted.
- Return activates Cancel, Delete is destructive, suppression is saved only
  after confirmation, and Settings provides Reset Delete Warning.
- Confirmed deletion removes both the note and FTS row. Backup restore remains
  the recovery path.

## Automated Evidence

- Main application tests: 31 passed, 0 failed, 0 skipped.
- `NoteNavigationTests`: 8 passed, including deterministic boundaries, rapid
  source flush, jump/promote, Cancel-first alert, confirmation, suppression,
  reset, and blank deletion.
- Editor projection tests: 14 passed, including horizontal gesture direction
  and one-shot directional cursor entry.
- Persistence tests: 16 passed. `IT-NOTE-004A` closes and reopens the real GRDB
  store with identical IDs and ordering tokens; `IT-NOTE-004B` keeps order keys
  unique under 120 concurrent promotions.
- `IT-NOTE-005` restores deleted rows, bodies, IDs, order, and FTS from a
  verified 100-note backup.
- Window projection remained 10/10. Traceability remained 65/65 evidence,
  69/69 requirements, and 493 mapped test IDs.
- Generated-project comparison, Debug and Release builds, formatting, and
  `git diff --check` passed.
- Signed UI tests are unavailable on this host because it has zero valid Apple
  Development identities; the same real application paths were exercised with
  macOS Accessibility instead.

## Real Application Evidence

- The Debug app exposed Previous Note `Command-[`, Next Note `Command-]`, Newest
  Note `Command-1`, Promote Note `Command-Shift-1`, and Delete Note `Command-D`
  through the real Edit menu.
- Exact sources `FORNOW_STEP13_A_20260804_1039_中文` and
  `FORNOW_STEP13_B_20260804_1039_emoji_📝` persisted as two GRDB/FTS rows.
- Previous/next switched between the exact sources. Promoting the first source
  retained ID `B42EE49E-2343-444E-8C36-A6B2D4915CEF` and moved its `orderKey`
  from 2 to 4, ahead of the second source at 3.
- The deletion sheet exposed `Cancel` before destructive `Delete`. Return
  dismissed the sheet without deleting either row.
- Confirming with Do not ask again deleted the first source. Deleting the
  second source then required no sheet. Reset Delete Warning was enabled in
  Settings and became disabled immediately after reset.
- Cleanup returned the production database and FTS index to `0|0`; SQLite
  `quick_check` returned `ok`.

## Verification Commands

```bash
scripts/format.sh
scripts/test.sh
scripts/test-editor-projection.sh
scripts/test-window-spike.sh
scripts/test-persistence-spike.sh
scripts/test-traceability.sh
scripts/check-generated-project.sh
scripts/build.sh
CONFIGURATION=Release scripts/build.sh
git diff --check
```

## Exit Criteria

- Ordering remains stable across relaunch: `PASS` in real GRDB integration and
  real application exercises.
- Every navigation path commits source first: `PASS` in unit/event tests and
  real application exercises.

## Deferred Manual Evidence

`MT-WIN-004C` remains `PENDING` under the owner-approved Phase 0 continuation
exception and is still required before the 1.0 release gate.
