# Step 3.1 - Keyword And Slash Command System

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Evidence: `AN-CMD-001` through `AN-CMD-003`, `AN-REV-001`
- Requirements: `FR-CMD-001` through `FR-CMD-003`
- Tests: `UT-CMD-001A` through `UT-CMD-001G`, `UT-CMD-002A` through
  `UT-CMD-002G`, `UT-CMD-003`, `UIT-CMD-003`, `ET-CMD-002`, and `MT-CMD-003`

## Files Changed

- `Packages/ForNowModes/Sources/ForNowModes/ModeCommandSystem.swift`
- `Packages/ForNowModes/Sources/ForNowModes/SourceParser.swift`
- `Packages/ForNowModes/Sources/ForNowModes/MarkdownParsing.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/SlashCommandEditing.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/EditorProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionParsing.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/MarkdownProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/LinkProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ClipboardProjection.swift`
- `App/ModeSettingsStore.swift`
- `App/ModeSettingsSection.swift`
- `App/SlashCommandModel.swift`
- `App/SlashCommandPanel.swift`
- `App/AppEnvironment.swift`
- `App/NoteSessionModel.swift`
- `App/ContentView.swift`
- `App/SettingsView.swift`
- `Tests/EditorProjectionSpikeTests/ModeCommandTests.swift`
- `Tests/ForNowTests/ModeSettingsAndSlashCommandTests.swift`
- `project.yml`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/02_ARCHITECTURE.md`
- `README.md`

## Behavior Contract

- Stable canonical IDs are independent from aliases. Versioned settings define
  all aliases and exactly one main slash alias for each of the eight modes.
  Normalization is case-insensitive and canonically composed; invalid versions,
  missing or duplicate modes, malformed aliases, duplicate aliases, collisions,
  and invalid main aliases fail explicitly before persistence.
- The generic first-line parser returns canonical identity, matched alias,
  optional title, and exact UTF-16 alias, header, and body ranges. Custom code
  aliases feed syntax presentation, link suppression, code-context paste and
  copy, and clean export through that same canonical identity.
- The global switch disables header interpretation and slash presentation
  without rewriting source. Loading mode settings before the note session starts
  updates meaningful-content classification without masquerading as editor input
  or preventing an existing note from loading.
- Slash is eligible at an empty line start or at the alias start of an existing
  first-line header. The typed slash and query remain model-only; only selecting
  a command mutates source. Invoking from a later empty line creates a canonical
  first-line header, while changing a header replaces only its alias and
  preserves the optional title.
- Up, Down, Tab, Return, Escape, Backspace, printable filtering, and visible
  number keys route through the editor. Insertion and replacement each use one
  expected-source edit, one `NSTextView` replacement, and one undo group.
- The compact picker remains inside the main window, scrolls eight commands,
  uses SF Symbols, exposes its filter, row labels, selected trait, and position
  values to accessibility, and owns a command-picker auto-hide suspension.
  Search, find/replace, Settings, window transitions, app resignation, settings
  changes, and shutdown dismiss it and release the suspension.
- Settings edits aliases and main aliases, restores defaults, validates before
  save, shows conflicts without replacing the active registry, and persists the
  last valid versioned payload across process launches.

## Automated Evidence

- Main application tests: 55 passed. The seven mode/settings tests cover
  versioned round trips, invalid-payload fallback, conflict rejection before
  writing, keyword-only meaningful-content behavior, startup loading without a
  false editor revision, number selection and accessible selection state,
  source-free filtering and Escape, disabled keywords, and real
  `NSTextView.keyDown` routing through Return and Undo.
- Editor projection tests: 99 passed. The 19 mode-command tests cover all
  canonical IDs and validation failures, case-insensitive aliases, UTF-16 title
  and body ranges, first-line restrictions, plain-mode fallback, custom code
  identity across projection/copy/paste/export, disabled-header export,
  deterministic slash eligibility and filtering, generic header presentation,
  and one-operation insert/replace Undo and Redo. All prior projection,
  Markdown, link, clipboard, IME, cancellation, and 10,000-edit Unicode tests
  also passed.
- Persistence tests: 17 passed with `PT-SEARCH-001` p95 `15.980625 ms`, plus
  both real SIGKILL durability paths. Window tests: 10 passed.
- Both complete Release performance tests passed. A focused final
  `PT-EDIT-001` run measured 30 samples on a 50,000-character source: p50
  `0.006625 ms`, p95 `0.020958 ms`, and worst `0.049209 ms`, below the 4 ms
  synchronous edit budget.
- Debug and Release application builds, strict Swift formatting, generated
  project comparison, shell syntax validation, traceability generation and both
  validator fault injections, and `git diff --check` passed. Traceability
  reported 65/65 evidence entries, 69/69 requirements, 493 mapped test IDs, and
  12 decisions.

## Real Application Evidence

- The current Debug application ran with an isolated `CFFIXED_USER_HOME`.
  Typing `/` at an empty source opened eight commands without changing the text
  area. Filtering to `av` left source empty and exposed one selected result;
  Escape removed the menu with source and undo history unchanged.
- Down selected row 2, Up returned to row 1, and number 7 inserted `code`.
  Filtering to `ma` and pressing Return inserted `math`. One Command-Z restored
  empty source and one Command-Shift-Z reapplied the complete insertion.
- Replacing `math: Budget` with `list: Budget` preserved the title and body.
  One Undo restored the complete original and one Redo reapplied the replacement.
  Invoking from the empty second line of `ordinary\n\nbody` inserted
  `timer\n` at source start; one Undo restored the exact original.
- Settings added `calculate` to Math and made it the main alias. After a complete
  quit and relaunch, the fields still showed `math, calculate` and main alias
  `calculate`; filtering to `cal` inserted `calculate` and one Undo removed it.
  An attempted `list, math` collision displayed `Keyword settings error: math
  is assigned to both List and Math.` A later full relaunch loaded `list`, never
  the invalid draft, while retaining the valid custom Math settings.
- Disabling keyword interpretation kept `calculate: Budget\n1 + 1` byte for
  byte unchanged. Slash then entered ordinary `/` source with no picker, and
  one Undo restored the exact apparent header. Re-enabling the setting restored
  the picker without rewriting the note.
- Command-F and Command-Shift-F each dismissed an open slash picker before
  presenting their own field. Opening Settings, toggling the window out and back,
  and resigning the application to Finder also removed the picker. The shown
  window returned without stale menu state.
- Raw macOS Accessibility reported identifier `Slash command menu`; every row
  exposed its display name and main alias, the selected row exposed the selected
  trait and `Selected, 1 of 8`, and the remaining rows exposed their positions.
  At the 620 by 280 minimum content configuration, the 301 by 252 picker was
  wholly contained in the 620 by 303 AX window frame including its title bar,
  with all eight scroll rows present and an 8-point bottom margin.
- After filtering `av` against `calculate: E2E\nbody 123`, the editor source
  stayed exact. A graceful quit flushed one identical `note.body` and
  `note_fts.body`; neither contained `/`, `av`, menu labels, selected state, or
  other presentation data. `PRAGMA quick_check` returned `ok`.
- The standard database, WAL, SHM, and preference domain retained their exact
  pre-run SHA-256/stat or exported values. The original input source was
  restored, no ForNow process remained, and the isolated evidence directory was
  removed.

## Exit Criteria

- Aliases never change stored canonical mode identity unexpectedly: `PASS` in
  registry validation, generic parsing, custom-code projection, clean export,
  Settings conflict/relaunch, disabled-keyword, and real SQLite checks.
- Command insertion and replacement each form one undo group: `PASS` in engine
  integration, real Return/number selection, header replacement, later-line
  insertion, Command-Z, and Command-Shift-Z checks.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. `scripts/test-ui.sh` exited with status 2 before build,
as designed. The real process, raw macOS Accessibility inspection, and injected
AppKit integration tests cover the required behavior without waiving future
signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
