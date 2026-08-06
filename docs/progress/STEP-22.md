# Step 2.2 - Copy And Paste

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Evidence: `AN-CLIP-001` through `AN-CLIP-003`
- Requirements: `FR-CLIP-001` through `FR-CLIP-004`
- Tests: `UT-CLIP-001A` through `UT-CLIP-001E`, `ET-CLIP-001`,
  `UT-CLIP-002A` through `UT-CLIP-002F`, `UT-CLIP-003A` through
  `UT-CLIP-003J`, `ET-CLIP-003`, `UT-CLIP-004`, and `ET-CLIP-004`

## Files Changed

- `Packages/ForNowEditor/Sources/ForNowEditor/ClipboardProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditingSession.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `App/PasteSettingsStore.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/SettingsView.swift`
- `App/ForNowCommands.swift`
- `Tests/EditorProjectionSpikeTests/ClipboardProjectionTests.swift`
- `Tests/EditorProjectionSpikeTests/EditorProjectionSpikeTests.swift`
- `Tests/ForNowTests/AppEnvironmentTests.swift`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/02_ARCHITECTURE.md`
- `README.md`

## Behavior Contract

- Copy priority is non-empty selection, inline-code content, fenced-code body,
  clicked result or link canonical source, then the clean whole-note export.
  A source selection also wins over an adornment copy button.
- Whole-note export omits only configured mode/control syntax, preserves the
  optional title after a mode header, retains complete URLs, and leaves other
  user-authored whitespace unchanged.
- Paste decoding prefers a plain string, then HTML, then RTF. Rich style is
  discarded. Attributed and Markdown links become a full URL or `label (URL)`.
- Normal paste normalizes CRLF and CR to LF, then applies five independent
  settings for leading whitespace, list numbers, bullets, Markdown, and empty
  lines. Raw paste performs decoding and line-ending normalization only.
- Every normal or raw paste enters the text system as one replacement and one
  undo action. A detached editor uses a local undo manager; an installed editor
  continues to use the window undo manager.
- Command-Shift-V routes `pasteRaw:` through the first responder. Contextual
  Copy and both paste actions explicitly participate in menu validation so
  AppKit cannot suppress the no-selection or unsupported-payload paths.
- Empty or binary-only content never enters source. The editor presents a
  fixed, source-free `Paste Failed` message for unsupported or unreadable text.
- `PasteSettings` uses a separate versioned UserDefaults payload. Production,
  preview, and test composition inject persistent or in-memory stores, and
  startup loads settings before the window creates its editor.

## Automated Evidence

- Editor projection tests: 44 passed. This includes 25 clipboard tests, all
  mapped `FR-CLIP-*` IDs, Safari and Chrome HTML, Notes and Word RTF, Excel and
  Numbers tabs, terminal and IDE indentation, Markdown, Unicode, CRLF, empty
  and binary-only payloads, and normal/raw single-step Undo and Redo.
- The existing editor regression set still completed 10,000 randomized Unicode
  edits, large-note cancellation, viewport restoration, marked text, and
  decoration accessibility checks.
- Main application tests: 41 passed, including versioned paste-setting
  round-trip, startup loading, update persistence, and corrupt-payload fallback.
- Persistence tests: 17 passed plus both process-kill fault paths. Window tests:
  10 passed. Traceability passed 65/65 evidence, 69/69 requirements, 493 mapped
  test IDs, and fault injection.
- `PT-EDIT-001` ran 30 Release samples: p50 `0.000875 ms`, p95 `0.002167 ms`,
  and worst `0.008084 ms`, below the 4 ms synchronous edit budget. Both Release
  performance tests passed.
- Debug and Release application builds, strict Swift formatting, generated
  project comparison, shell syntax validation, `git diff --check`, and unified
  log source-canary inspection passed.

## Real Application Evidence

- The current Debug application ran with an isolated `CFFIXED_USER_HOME`; the
  standard user database and preferences were not modified. The standard
  database retained SHA-256
  `7f791e37080510a918e386e37e526663343169a787d7307d68c2abab98764cdd`,
  mtime `1785820437`, and size `77824` bytes before and after the run.
- Command-V transformed a Unicode CRLF fixture into three LF lines, removed
  indentation, list markers, Markdown, and blank lines, and retained the smart
  link destination. One Command-Z removed the complete paste and one Redo
  restored it.
- Command-Shift-V retained a tab, number, bullet, Markdown, blank line, and link
  syntax while normalizing line endings. Its Undo and Redo each covered the
  complete operation.
- Whole-note Command-C returned `Title` and `Body` without the `plain:` header
  or trailing `/x`. Inline-code Command-C returned `swift test`; selecting the
  complete source took priority and returned the exact source.
- The real settings window exposed five independent checkboxes. Disabling only
  leading-whitespace removal preserved two source spaces while Markdown removal
  stayed active, and the `0, 1, 1, 1, 1` state survived a full app relaunch.
- HTML-only paste produced readable text with
  `Live Guide (https://example.com/live)`. A PNG-only pasteboard kept Paste enabled and
  displayed a sheet titled `Paste Failed` with the fixed unsupported-text
  message.
- The isolated SQLite store retained only transformed source strings and
  returned `PRAGMA quick_check = ok`. Unified logs contained no Step 2.2 source
  canary, the process exited normally, and the pre-test pasteboard
  representations were restored.

## Exit Criteria

- Every transform can be independently enabled or disabled: `PASS` in unit,
  store, settings-window, and cross-relaunch checks.
- Raw paste bypasses every optional transform: `PASS` in unit, editor, and real
  Command-Shift-V checks.
- Source and clipboard tests cover Unicode and CRLF: `PASS` in unit and real
  application checks.
- Every paste is one undo group: `PASS` for normal and raw paste in editor tests
  and the real application.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. `scripts/test-ui.sh` exited with status 2 before build,
as designed. The production clipboard paths were exercised in the real Debug
application through macOS Accessibility; this does not waive future signed UI
coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
