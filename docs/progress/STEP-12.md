# Step 1.2 - Durable And Transient Notes

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Evidence: `AN-NAV-003`, `AN-NAV-004`, `AN-NOTE-SET-001`
- Requirements: `FR-NOTE-001`, `FR-NOTE-002`, `FR-NOTE-009`
- Tests: `UT-NOTE-001`, `IT-NOTE-001`, `UT-NOTE-002A` through
  `UT-NOTE-002F`, `IT-NOTE-002`, `UT-NOTE-009A` through `UT-NOTE-009F`,
  `IT-NOTE-009`

## Files Changed

- `Packages/ForNowCore/Sources/ForNowCore/Dependencies.swift`
- `Packages/ForNowCore/Sources/ForNowCore/LifecycleSettings.swift`
- `Packages/ForNowCore/Sources/ForNowCore/Note.swift`
- `Packages/ForNowCore/Sources/ForNowCore/NoteLifecycle.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/DebouncedNoteSaver.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/PersistenceNoteRepository.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/PersistenceStore.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `App/AppDelegate.swift`
- `App/AppEnvironment.swift`
- `App/AppLifecycleLogging.swift`
- `App/ContentView.swift`
- `App/LifecycleSettingsStore.swift`
- `App/NoteSessionModel.swift`
- `Tests/EditorProjectionSpikeTests/EditorProjectionSpikeTests.swift`
- `Tests/ForNowTests/AppEnvironmentTests.swift`
- `Tests/ForNowTests/NoteLifecycleTests.swift`
- `docs/02_ARCHITECTURE.md`

## Behavior Contract

- Empty source, whitespace/newline-only source, and a valid mode keyword with no
  title or body remain transient and create no row.
- A mode title, mode body, invalid keyword, URL, CJK text, emoji, and other
  committed source are meaningful.
- AppKit reports `hasMarkedText()` with every source change. Marked IME source
  stays in memory; committing the composition makes it eligible for persistence.
- The transient UUID becomes the stable durable UUID on the first meaningful
  edit. Persistence always receives exact source, never a projection.
- Undoing to blank cancels a pending save. Leaving deletes any row already
  published for the now-empty note.
- An editor change arriving before repository startup wins over launch loading
  and is persisted under a fresh transient UUID.
- Lifecycle settings are versioned. Last-window-close time is stored under a
  separate key. Reopen thresholds are inclusive.
- Note count is always maintained and is exposed only when its preference is
  enabled.

## Automated Evidence

- `NoteLifecycleTests`: 16 passed, 0 failed, 0 skipped.
- Main application tests: 23 passed, 0 failed, 0 skipped.
- All `UT-NOTE-002A...F` classifications pass, including IME and undo-to-blank.
- `IT-NOTE-002` passes with both the in-memory repository and real GRDB.
- The GRDB test persists exact English/CJK/emoji/URL source, then removes both
  the pending draft and row after undo-to-blank.
- All launch, `always`, 3-minute, 30-minute, 1-hour, 1-day, and `never`
  thresholds pass at just-below and exact boundaries.
- UserDefaults settings and the independently keyed close timestamp survive a
  new store instance.
- Input delivered before asynchronous repository loading remains exact.
- The editor spike's marked-text test now verifies the real source callback
  reports provisional and committed states.
- Editor projection remained 12/12, window spike remained 10/10, and
  persistence remained 15/15 plus both process-kill fault gates.
- Traceability remained 65/65 evidence, 69/69 requirements, and 493 mapped test
  IDs. Debug and Release builds, generated-project comparison, formatting, and
  `git diff --check` passed.

## Real Application Evidence

- The generated Debug app launched with the integrated AppKit editor focused.
- Accessibility set `FORNOW_E2E_20260804_1018_中文`; the editor immediately read
  back the exact value.
- After the debounce and again after normal Quit, SQLite contained the exact
  source under stable ID `178ACEDE-BA20-4437-8C90-4670AA49AE01`.
- Lifecycle logs showed `note_session_prepared` and `repository_flushed` before
  any service teardown.
- The uniquely identified test note and its FTS row were removed afterward;
  both tables returned to zero rows.

## Verification Commands

```bash
scripts/format.sh --fix
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

- No abandoned blank rows: `PASS` in the in-memory and real-GRDB paths.
- No source is lost when a transient note becomes durable: `PASS` in automated
  tests and the real application/SQLite exercise.

## Deferred Manual Evidence

`MT-WIN-004C` remains `PENDING` under the owner-approved Phase 0 continuation
exception and is still required before the 1.0 release gate.
