# Step 2.3 - Links

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Evidence: `AN-TXT-003`
- Requirement: `FR-EDIT-004`
- Tests: `UT-EDIT-004A` through `UT-EDIT-004L` and `ET-EDIT-004`

## Files Changed

- `Packages/ForNowEditor/Sources/ForNowEditor/LinkProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/EditorProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionParsing.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `App/EditorStateStore.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/SettingsView.swift`
- `Tests/EditorProjectionSpikeTests/LinkProjectionTests.swift`
- `Tests/ForNowTests/AppEnvironmentTests.swift`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/02_ARCHITECTURE.md`
- `README.md`

## Behavior Contract

- `NSDataDetector` candidates pass a second structural validator. Only exact
  HTTP/HTTPS source with a non-empty host can become a link or open action;
  whitespace, control characters, malformed values, and all other schemes are
  rejected.
- Link detection remains in the cancellable source-version projection path.
  `code` mode disables links for the whole note; backtick and tilde fenced code
  is excluded, including an unclosed fence through end of source.
- A deterministic label uses host, optional port, and `/...` when a path,
  query, or fragment exists. Repeated exact URLs use one-based source order and
  retain `· n` in both shortened and expanded views.
- The overlay yields while the caret is at either URL boundary or inside it,
  and while a selection intersects it. It appears only after the caret or
  selection leaves the URL.
- Link identity is the SHA-256 digest of exact URL bytes plus occurrence index.
  Manual expansion is scoped by note UUID and stored outside source as only
  note UUIDs, digests, and indexes; UserDefaults never receives plaintext URLs
  from this state store.
- Click and Command-click revalidate and open the exact URL.
  Command-Shift-click toggles expanded state without a source edit or undo
  entry. The context menu copies the exact URL.
- Automatic shortening and all hyperlink features are independent versioned
  settings. Turning shortening off retains link opening and full-URL overlays;
  turning all features off removes detection, presentation, and interaction
  while preserving source.

## Automated Evidence

- Editor projection tests: 57 passed. The 13 new link tests cover HTTP/HTTPS
  exact-source detection, caret boundaries, deterministic labels, duplicate
  identity after unrelated edits, full and shortened suffixes, display toggle,
  exact copy/open, both settings, code mode, fenced code, malformed input, and
  malicious schemes. The existing 10,000-edit Unicode property test and all
  clipboard/editor regressions also passed.
- Main application tests: 43 passed. The new application test reconstructs
  versioned stores across environment restarts, verifies independent setting
  persistence, toggles note-scoped expanded state twice, and confirms the
  persisted state payload contains no plaintext URL. Corrupt editor-setting
  and expanded-state payloads fall back to defaults.
- Persistence tests: 17 passed, plus the flushed-edit and interrupted-backup
  SIGKILL fault paths. Window tests: 10 passed.
- Traceability passed 65/65 evidence entries, 69/69 requirements, 493 mapped
  test IDs, generated-source comparison, and both validator fault injections.
- `PT-EDIT-001` ran 30 Release samples: p50 `0.000834 ms`, p95 `0.002125 ms`,
  and worst `0.008542 ms`, below the 4 ms synchronous edit budget. Both Release
  performance tests passed.
- Debug and Release application builds, strict Swift formatting, generated
  project comparison, shell syntax validation, and `git diff --check` passed.

## Real Application Evidence

- The current Debug application ran with an isolated `CFFIXED_USER_HOME`; the
  standard user database was unchanged. After the run, its SHA-256 remained
  `7f791e37080510a918e386e37e526663343169a787d7307d68c2abab98764cdd`,
  mtime `1785820437`, and size `77824` bytes. Standard ForNow preferences were
  restored to their exact pre-run keys and values.
- With the caret at the end of the second duplicate URL, only the first
  shortened overlay was present. Moving the caret outside produced
  `example.com/...` and `example.com/... · 2`.
- A real link activation opened the default browser. The injected AppKit
  integration test separately asserted that normal and Command-click pass the
  exact percent-encoded URL after validation and that invalid values never
  reach the opener.
- The settings window exposed two independent checkboxes. Turning automatic
  shortening off immediately produced full-URL overlays and retained the
  second link's `· 2` suffix. Turning all hyperlink features off removed both
  overlays; restoring it brought them back without changing source.
- A `code: swift` note exposed zero link controls. A fenced-code fixture exposed
  only the URL outside the fence, never the URL inside it.
- The isolated SQLite store returned `PRAGMA quick_check = ok` and contained
  exactly the two full source URLs. Neither shortened labels nor the duplicate
  suffix entered the stored body. Unified logs contained none of the URL source
  fixture.

## Exit Criteria

- Source URL round-trips exactly: `PASS` in parser, copy, open, container,
  persistence, and real SQLite checks.
- Duplicate labels remain stable after unrelated edits: `PASS` for identity,
  source order, shortened display, expanded display, and real App rendering.
- Malicious or invalid schemes do not open: `PASS` in parser and injected
  AppKit opener tests.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities; `scripts/test-ui.sh` exited with status 2 before build,
as designed. Accessibility cannot attach mouse modifier flags to `AXPress`, so
the real process covered plain activation while Command-click and
Command-Shift-click were exercised in the AppKit integration test. This does
not waive future signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
