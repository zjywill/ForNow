# Step 2.5 - Find And Replace

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Evidence: `AN-NAV-006`
- Requirement: `FR-NOTE-008`
- Tests: `UT-NOTE-008A` through `UT-NOTE-008G` and `ET-NOTE-008`

## Files Changed

- `Packages/ForNowEditor/Sources/ForNowEditor/FindReplace.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `App/FindReplaceCommandField.swift`
- `App/FindReplaceModel.swift`
- `App/FindReplacePanel.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/ForNowCommands.swift`
- `Tests/EditorProjectionSpikeTests/FindReplaceTests.swift`
- `Tests/ForNowTests/FindReplaceModelTests.swift`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/02_ARCHITECTURE.md`
- `README.md`

## Behavior Contract

- Command-Shift-F opens an in-window find/replace panel and focuses its native
  find field. Cross-note Command-F search and current-note find/replace dismiss
  each other and cannot hold overlapping auto-hide suspension tokens.
- Find reads only the live current-note source. Contains, whole word, line
  prefix, line suffix, and regular expression return UTF-16 source ranges;
  derived Markdown, code, link, checkbox, and result decorations are not
  searchable or replaceable.
- Case sensitivity is independent of mode. Whole-word boundaries treat Unicode
  letters, numbers, and underscore as word characters. Prefix and suffix modes
  exclude CR, LF, and CRLF terminators from their comparisons.
- Regular expressions are compiled before a replacement plan is created.
  Invalid expressions clear selection, show a source-free error, disable
  replacement, and never mutate source. Foundation enumerates zero-length
  matches finitely; the application does not advance its own regex cursor.
- Replace Current checks the expected source before one bounded edit and then
  advances past the inserted text, including when the replacement still
  contains the query. Replace All applies source ranges in reverse to one
  snapshot and submits exactly one full-source `NSTextView` replacement, so one
  Undo and one Redo cover the complete operation.
- Opening the panel temporarily expands all link overlays through the existing
  projection policy. Closing, hiding, or shutting down removes only that
  temporary expansion and restores automatic shortening plus any persisted
  note-scoped manual expansion state. Neither state nor visible link labels
  enter `Note.body`.
- Enter and Shift-Enter navigate next/previous from the find field. Tab reveals
  and focuses replacement. Enter and Shift-Enter perform Replace and Replace All
  from replacement. Escape closes the panel and returns control to the editor.

## Automated Evidence

- Editor projection tests: 80 passed. The six new engine tests cover independent
  case sensitivity, Unicode whole-word boundaries, LF and CRLF line anchors,
  regex validation before mutation, finite zero-length matches, and emoji/CJK
  UTF-16 replacement planning. `ET-NOTE-008` proves Replace All is one
  undoable, redoable source-only edit. All prior projection, Markdown, link,
  clipboard, cancellation, IME, and 10,000-edit Unicode regressions passed.
- Main application tests: 48 passed. Native field routing covers Tab, Enter,
  Shift-Enter, and Escape roles. Model tests cover navigation wrapping,
  Replace All and Undo, invalid-regex immutability, temporary link restoration,
  and advancing beyond a replacement that still matches the query.
- Persistence tests: 17 passed, with `PT-SEARCH-001` p95 `12.514542 ms`, plus
  both real SIGKILL durability paths. Window tests: 10 passed.
- Both complete Release performance tests passed. A focused rerun of
  `PT-EDIT-001` measured 30 samples on a 50,000-character source: p50
  `0.005125 ms`, p95 `0.009625 ms`, and worst `0.025333 ms`, below the 4 ms
  synchronous edit budget.
- Debug and Release application builds, strict Swift formatting, generated
  project comparison, shell syntax validation, traceability generation and both
  validator fault injections, and `git diff --check` passed. Traceability
  reported 65/65 evidence entries, 69/69 requirements, 493 mapped test IDs, and
  12 decisions.

## Real Application Evidence

- The current Debug application ran with a dedicated `CFFIXED_USER_HOME` at the
  minimum 620-point main-window width. The panel fit inside the window without
  clipped fields, buttons, status, options, or overlapping controls.
- Contains found three `dog` substrings and whole word found only the two
  standalone values. Case-insensitive `alpha` found `Alpha` and `alpha`, while
  case-sensitive input found one. Line prefix and suffix each found the exact
  anchored line, and `item-[0-9]+` found both regex values.
- The invalid `(` expression displayed `Invalid regular expression.`, disabled
  navigation and replacement, and Shift-Enter left the editor source byte for
  byte unchanged.
- Search-field Enter moved from `1 of 3` to `2 of 3`; Shift-Enter returned to
  `1 of 3`. Tab exposed and focused replacement. Replacement-field Enter
  changed only the selected match and reported `Replaced 1`; Escape removed the
  panel. One editor Undo restored it and one Redo reapplied it.
- Replacement-field Shift-Enter changed both remaining matches and reported
  `Replaced 2`. After dismissal, one Command-Z restored both changes together
  and one Command-Shift-Z reapplied both, proving the complete Replace All was
  one undo group in the real app.
- With automatic shortening enabled for the check, the closed editor displayed
  `example.com/...`; opening find/replace displayed the complete
  `https://example.com/very/long/path`; Escape restored `example.com/...`.
  The original disabled-shortening preference was restored before exit.
- After a full process quit and relaunch with the same isolated home, navigating
  to the prior note returned the exact replaced source. `PRAGMA quick_check`
  returned `ok`; the single `note.body` and its FTS body were identical and
  contained the original URL, never the shortened label or panel state.
- The standard database, WAL, and SHM retained their exact pre-run SHA-256,
  size, and mtime values. Standard preferences retained the exact three pre-run
  keys and values.

## Exit Criteria

- Replace All is one undo group: `PASS` in engine integration, model, real
  Command-Z, and real Command-Shift-Z checks.
- Zero-length regex matches cannot loop forever: `PASS` with four finite
  start/end matches across two lines and one complete replacement plan.
- Invalid regex never changes source: `PASS` in engine, model, and real
  replacement-field Shift-Enter checks.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. `scripts/test-ui.sh` exited with status 2 before build,
as designed. The real process, accessibility-driven controls, screenshots, and
injected AppKit integration tests cover the required behavior without waiving
future signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
