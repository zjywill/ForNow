# Step 4.3 - AutoPaste

- Status: `DONE`
- Started: 2026-08-06
- Completed: 2026-08-06
- Evidence: `AN-AUTO-001`, `AN-AUTO-002`
- Requirements: `FR-AUTO-001`, `FR-AUTO-002`, `FR-AUTO-003`
- Decision: `FORNOW-DECISION-015`
- Required tests: `UT-AUTO-001`, `IT-AUTO-001`, `UIT-AUTO-001`,
  `UT-AUTO-002A` through `UT-AUTO-002F`, `SOAK-AUTO-001`, and
  `UT-AUTO-003A` through `UT-AUTO-003H`

## Files Changed

- `docs/autopaste/AUTOPASTE_V1.md`
- `docs/decisions/ADR-006_AUTOPASTE_SESSION_AND_CAPTURE.md`
- `App/AutoPasteModel.swift`
- `App/AutoPasteSettingsStore.swift`
- `App/AppDelegate.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/ForNowCommands.swift`
- `App/NoteSessionModel.swift`
- `App/SettingsView.swift`
- `Packages/ForNowModes/Sources/ForNowModes/AutoPaste.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/ClipboardService.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `Tests/EditorProjectionSpikeTests/AutoPasteTests.swift`
- `Tests/ForNowTests/AutoPasteModelTests.swift`
- `UITests/ForNowUITests/LaunchTests.swift`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/00_SOURCE_LEDGER.md`
- `docs/01_PRODUCT_SPEC.md`
- `docs/02_ARCHITECTURE.md`
- `docs/04_TEST_MATRIX.md`
- `docs/traceability.yml`
- `README.md`

## Behavior Contract

- Contract `fornow-autopaste-v1` accepts exact case-insensitive `paste` and
  `paste(<separator>)` source-line commands. Custom separators are literal,
  may be empty, and are limited to 256 UTF-16 code units. Only Return commits a
  command; persisted source never replays it.
- One application-wide session snapshots the destination note ID, display name,
  and capture policy. Navigation does not retarget it. A missing or deleted
  destination stops monitoring instead of recreating a note.
- The production clipboard timer exists only while the status is visible. Start
  records the current change count as a baseline, only later `.string` changes
  are read, and stop clears the timer, callback, tokens, queue, and session.
- CRLF and CR become LF and NUL is removed. The 64-entry FIFO SHA-256 history
  stores no clipboard body. Up to 32 application-owned change counts suppress
  editor copy feedback without persisting text.
- Captures append sequentially to the fixed note and flush before the next
  event. Current-note IME marked text defers the append. Prefix, suffix,
  separator, HTTP/HTTPS link treatment, and UTC ISO 8601 timestamp settings are
  versioned and snapshotted per session.
- Escape, a repeated command, either accessible status button, destination
  deletion/loss, app termination, and append failure cover every stop path.
  The blinking icon respects Reduce Motion.

## Automated Evidence

- `AutoPasteModelTests` passes 8 of 8 tests. It covers all stop reasons, idle
  zero-poll behavior, fixed-target navigation, change-count and content
  deduplication, application-owned copies, repeated command, Escape, destination
  deletion/loss, shutdown, status semantics, and settings persistence.
- The application-layer 1,000-poll test accepts 925 expected unique events,
  rejects 25 same-count polls, 25 recent-content duplicates, and 25 owned-copy
  events, then proves 925 unique final source lines, a matching capture count,
  no owned content, and byte-equal repository content.
- `AutoPasteTests` passes 17 of 17 tests. `SOAK-AUTO-001` accepts 10,000 distinct
  events while retaining exactly 64 hashes. Parser, newline/custom/empty
  delimiter, normalization, affix, link, timestamp, display-name, and hash-body
  privacy fixtures all pass.
- The complete main application suite passes 96 of 96 tests and the complete
  Editor Projection suite passes 261 of 261, with zero failures, expected
  failures, or skips. Persistence passes 18 of 18 plus both crash-fault workers;
  Window passes 11 of 11; Release Performance passes 3 of 3.
- Debug and Release unsigned builds, strict Swift formatting, generated-project
  comparison, traceability generation and validation, both traceability fault
  injections, iOS documentation validation, and `git diff --check` pass.
  Traceability maps 65 of 65 evidence entries, 69 of 69 requirements, 494 test
  IDs, and 15 decisions.

## Real Application Evidence

- A current Debug application ran through LaunchServices with an isolated
  `CFFIXED_USER_HOME`. Submitting `paste` displayed a persistent bottom status
  naming `Real AutoPaste Target`; the count appeared only after accepted events.
- One external `alpha external`, its duplicate, a Markdown link, and a ForNow
  internal copy produced exactly two captures. The duplicate and owned copy did
  not change source or count.
- Navigating to a blank note kept the status target name. Copying
  `beta while viewing another note` appended only to the original destination;
  the visible blank note stayed empty, the status reached three captures, and
  Previous Note restored the appended source.
- Escape removed the status and a later clipboard change was ignored. A custom
  `paste( | )` session produced exact `gamma | delta` source. A repeated command
  and the blinking clipboard button each stopped observation; later pasteboard
  changes did not append.
- Both native icon controls expose `AXRole=AXButton`,
  `AXDescription=Stop AutoPaste`, `AXIdentifier=Stop AutoPaste`, and
  `AXHelp=Stop AutoPaste`. Activating the first control removed the status.
- After normal Quit, the inspected Note and FTS bodies were byte-identical at
  148 bytes, contained only command and captured source, and excluded status,
  count, and button labels. `PRAGMA quick_check` returned `ok`, and no ForNow
  process remained.

## Exit Criteria

- Monitor is inactive when the indicator is absent: `PASS` in startup,
  stop-path, post-stop event, and real-process evidence.
- 1,000 clipboard events create no duplicate or loop: `PASS` with 925 expected
  unique canonical lines and 75 intentionally rejected events.
- Destination deletion stops the session: `PASS` for visible deletion and a
  missing background destination without note recreation.
- Every Step 4.3 task is implemented: `PASS` in the versioned contract, mapped
  automated suites, real AppKit Accessibility interaction, and SQLite/FTS
  inspection.

## Environment Limitation

The `ForNowUITests` target builds, but this host has zero valid Apple Development
identities. The UI runner remained at `waiting for workers to materialize` for
95.231 seconds and was interrupted. Native real-process Accessibility inspection
exercised the same status discovery and stop action without waiving future signed
UI coverage.

## Deferred Manual Evidence

A bounded live recheck still found one online, non-mirrored `Mi Monitor` in
`system_profiler SPDisplaysDataType` and one screen in `NSScreen.screens`.
`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
