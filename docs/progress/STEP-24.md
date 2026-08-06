# Step 2.4 - Simple Markdown And Code

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Evidence: `AN-MD-001`, `AN-CODE-001`
- Requirements: `FR-EDIT-003`, `FR-CLIP-001`, `FR-CMD-004`
- Tests: `UT-EDIT-003A` through `UT-EDIT-003J`, `ET-EDIT-003`,
  `UT-CMD-004A` through `UT-CMD-004D`, and `ET-CMD-004`

## Files Changed

- `Packages/ForNowModes/Sources/ForNowModes/MarkdownParsing.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/MarkdownProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/EditorProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ClipboardProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/LinkProjection.swift`
- `App/EditorStateStore.swift`
- `App/AppEnvironment.swift`
- `App/SettingsView.swift`
- `Tests/EditorProjectionSpikeTests/MarkdownProjectionTests.swift`
- `Tests/EditorProjectionSpikeTests/ClipboardProjectionTests.swift`
- `Tests/ForNowTests/AppEnvironmentTests.swift`
- `docs/02_ARCHITECTURE.md`
- `README.md`

## Behavior Contract

- Only headings one through three, bold, italic, strike, underline, inline code,
  fenced code, and leading-whitespace `//` comments receive presentation.
  Syntax markers remain visible and unsupported Markdown stays ordinary source.
- Inline and fenced code suppress nested Markdown. Backtick and tilde fences use
  matching runs; an unclosed fence owns source through end of note.
- Comment lines do not emit checkbox or calculation decorations. Command-slash
  toggles current or selected complete lines through the first responder as one
  source replacement and one undo action, preserving indentation and CRLF.
- A case-insensitive `code` header accepts an optional language. Missing language
  uses the configured default; an unknown explicit language deterministically
  falls back to plain text.
- Syntax highlighting is adapter-backed and emits source-coordinate ranges only.
  TextKit temporary attributes render all styles without changing text storage,
  persistence, copy output, selection coordinates, or undo history.
- Code notes disable ordinary Markdown and links. Fenced code disables links and
  leading-whitespace stripping only for selections in that range. Raw paste is
  unchanged, and contextual code-note copy returns the complete code body.
- Version-2 editor settings persist default language and highlight theme while
  decoding version-1 link preferences with code defaults. A failed save restores
  the previously published settings.

## Automated Evidence

- Editor projection tests: 73 passed. The 16 Markdown/code tests cover the exact
  grammar, unsupported syntax, UTF-16 ranges, comment/calculation/list
  exclusions, CRLF and trailing-line comment toggling, code headers and aliases,
  closed and unclosed fences, syntax precedence, code copy/paste, source-free
  presentation, and one-step Undo/Redo. All clipboard, link, 10,000-edit Unicode,
  cancellation, IME, and editor regressions also passed.
- Main application tests: 45 passed. Version-1 editor settings migrated without
  losing either link preference, version-2 language/theme values survived a
  reconstructed environment, corrupt payloads fell back to defaults, and a
  store write failure rolled published state back.
- Persistence tests: 17 passed, including `PT-SEARCH-001` at p95 `11.830208 ms`
  and both real SIGKILL durability paths. Window tests: 10 passed.
- `PT-EDIT-001` ran 30 Release samples on a 50,000-character source: p50
  `0.006333 ms`, p95 `0.010125 ms`, and worst `0.024708 ms`, below the 4 ms
  synchronous edit budget. Both complete Release performance tests passed.
- Debug and Release application builds, strict Swift formatting, generated
  project comparison, shell syntax validation, traceability generation and both
  validator fault injections, and `git diff --check` passed. Traceability
  reported 65/65 evidence entries, 69/69 requirements, 493 mapped test IDs, and
  12 decisions.

## Real Application Evidence

- The current Debug application ran twice with an isolated
  `CFFIXED_USER_HOME`. The real editor visibly rendered all supported Markdown
  styles, fenced Swift tokens, and visible source markers; level-four headings,
  quotes, and triple emphasis remained ordinary source.
- Command-slash toggled an indented current line and a three-line selection.
  Command-Z restored each exact original source in one action, and
  Command-Shift-Z restored the current-line comment edit.
- A `code: swift` note highlighted keywords, strings, comments, and numbers while
  its HTTP source produced zero accessible link controls. Normal paste retained
  the two leading spaces in `  print(value)`.
- Settings changed the default language to Python and the theme to Midnight.
  After a complete process quit and relaunch, both pickers retained those values;
  an identifier-free `code` note visibly used Python highlighting and the
  selected theme. The standard preference domain was then restored to its exact
  pre-mutation keys and values.
- The isolated SQLite database returned `PRAGMA quick_check = ok` and stored only
  the two exact source bodies used during the two process runs. It contained no
  style labels, shortened links, syntax colors, or other derived presentation.
- The standard user database, WAL, and SHM were unchanged. Their before/after
  SHA-256 values were respectively
  `7f791e37080510a918e386e37e526663343169a787d7307d68c2abab98764cdd`,
  `d54a791736ca742afa18b8918e1b43b3219cca60e56959ada37e597fcf67fb68`,
  and `fe1550940f12c1440eb12d01e4871fd1b4ab73262e73592e1437fac3b3c07efe`;
  sizes and mtimes were also unchanged.

## Exit Criteria

- Unsupported Markdown remains untouched: `PASS` in parser, integration, and
  real application presentation checks.
- Comment toggling is one undo group: `PASS` for current line, selected lines,
  CRLF, Undo, and Redo.
- Syntax highlighter cannot mutate source: `PASS` in adapter, TextKit, clipboard,
  SQLite, and real application checks.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. `scripts/test-ui.sh` exited with status 2 before build,
as designed. The real process and injected AppKit integration tests cover the
required editor behavior, but this does not waive future signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
