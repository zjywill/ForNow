# Step 5.1 - Quick Export

- Status: `DONE`
- Started: 2026-08-06
- Completed: 2026-08-06
- Evidence: `AN-EXP-001`, `AN-EXP-002`, `AN-EXPORT-003`
- Requirements: `FR-EXP-001`, `FR-EXP-002`, `FR-EXP-003`, `FR-EXP-004`
- Decision: `FORNOW-DECISION-017`
- Required tests: `UT-EXP-001A` through `UT-EXP-001F`, `IT-EXP-002A`
  through `IT-EXP-002H`, `ST-EXP-002`, `UT-EXP-003`, `IT-EXP-003A`
  through `IT-EXP-003F`, `UT-EXP-004A` through `UT-EXP-004J`,
  `IT-EXP-004`, and `ST-EXP-004`

## Files Changed

- `docs/export/QUICK_EXPORT_V1.md`
- `docs/decisions/ADR-008_QUICK_EXPORT_DOCUMENT_AND_DESTINATIONS.md`
- `Packages/ForNowCore/Sources/ForNowCore/Export.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ExportDocumentBuilder.swift`
- `Packages/ForNowIntegrations/Package.swift`
- `Packages/ForNowIntegrations/Package.resolved`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/ApplicationExport.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/CustomURLExport.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/ExportFilenames.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/FileExport.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/URLQueryEncoding.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/ExportFileChooser.swift`
- `App/ExportSettingsSection.swift`
- `App/ExportSettingsStore.swift`
- `App/ForNowCommands.swift`
- `App/SettingsView.swift`
- `Tests/EditorProjectionSpikeTests/ExportDocumentTests.swift`
- `Tests/ForNowTests/QuickExportTests.swift`
- `ForNow.xcodeproj/project.pbxproj`
- `ForNow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- `docs/00_SOURCE_LEDGER.md`
- `docs/01_PRODUCT_SPEC.md`
- `docs/traceability.yml`
- `README.md`

## Behavior Contract

- Every destination receives one immutable `ExportDocument` built from a
  snapshot of canonical `Note.body`. Adapters never read editor decorations or
  write derived text back to Note, SQLite, FTS, selection, or Undo.
- Clean export always removes recognized trailing checklist markers and obeys
  the versioned keyword-omission setting. First-line title extraction retains
  the full cleaned text used by TXT, Markdown, ZIP, and Apple Shortcut input.
- Command-S routes to the configured quick destination. Export All snapshots
  repository order and creates one deterministic UTF-8 text entry per note.
- TXT and Markdown use sibling temporary files and a same-volume atomic commit.
  Existing destinations fail by default and can be replaced only after the
  save panel approves that exact existing path. Every error removes the owned
  temporary file.
- Suggested filename bases preserve Unicode, replace unsafe path characters,
  stay within 180 UTF-8 bytes without splitting an extended grapheme cluster,
  and deterministically suffix duplicate ZIP entry names.
- ZIP output uses the exact reviewed ZIPFoundation 0.9.20 dependency at
  revision `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`.
- Obsidian, Bear, and Apple Notes through Shortcuts have isolated URL builders.
  Query values use strict RFC 3986 percent encoding exactly once, including
  `%2B` for literal plus signs, and Launch Services availability is checked
  before opening.
- Version-1 custom templates allow only the documented productivity schemes,
  `{CONTENT}`, `{TITLE}`, and `{DATE}` placements, a 4,096-byte template, and
  an 8,192-byte rendered URL. Path content applies the frozen ampersand and
  percent compatibility transform; invalid, oversized, or unavailable
  templates perform no external action.

## Automated Evidence

- `ExportDocumentTests` passes 6 of 6 canonical source, keyword, title, URL,
  checklist-marker, Unicode, line-ending, and source-immutability tests.
  `QuickExportTests` passes 30 of 30 file, ZIP, application URL, custom URL,
  settings, Command-S routing, overwrite, cleanup, and failure-preservation
  tests.
- The complete main application suite passes 132 of 132 tests and the complete
  Editor Projection suite passes 273 of 273, with zero failures, expected
  failures, or skips. Persistence passes 18 of 18 plus both crash-fault workers;
  Window passes 11 of 11; ForNowDesign passes 3 of 3.
- Release Performance passes 3 of 3. `PT-EDIT-001` measured 30 samples at
  `0.048958 ms` p50, `0.064208 ms` p95, and `0.124583 ms` worst. The 1,000-line
  math run measured `48.010875 ms` p95 and worst.
- Debug and Release unsigned builds, strict Swift formatting, generated-project
  comparison, traceability generation and validation, both traceability fault
  injections, iOS documentation validation, and `git diff --check` pass.
  Traceability maps 65 of 65 evidence entries, 69 of 69 requirements, 494 test
  IDs, and 17 decisions.

## Real Application Evidence

- A current Debug application launched through LaunchServices with an isolated
  `CFFIXED_USER_HOME` and `HOME`. The source used combining Unicode, CJK, emoji,
  URL query delimiters, a recognized List Mode header, and a trailing checked
  marker:

  ```text
  list: Quick Export: 中文 é 🚀 & 100%
  first item /x
  second + item
  https://example.com/a?x=1&y=2
  ```

- Command-S saved the default Plain Text destination. The visible Export
  Settings section changed the quick destination to Markdown, saved it, and a
  second Command-S produced Markdown. Both files were 91-byte UTF-8 documents
  without a byte-order mark and were byte-identical. They retained the title
  line and exact URL while omitting `list:` and the eligible trailing `/x`.
- Export All saved a 420-byte deflated ZIP with two UTF-8 entries. Extraction
  through the platform archive tool produced `Second note- αβ.txt` with its two
  exact source lines and `Quick Export- 中文 é 🚀 & 100%.txt` with the exact
  same clean text as the single-file exports. No `.fornow-*` or other temporary
  file remained beside any destination.
- After normal Quit, SQLite contained two Notes and FTS contained two matching
  rows. Both mismatch queries returned zero; `PRAGMA integrity_check` and
  `PRAGMA quick_check` returned `ok`. The first persisted body still contained
  its exact `list:` header and trailing `/x`, proving export did not rewrite the
  source.
- The 640-by-852-point Settings window exposed the complete 600-by-157-point
  Export section. Accessibility geometry placed the picker, both toggles,
  diagnostic, and 150-by-24-point save button inside the section and window;
  the Plain Text diagnostic read `A save location will be requested.`
- The test instance quit normally and left no ForNow process. The shared
  CFPreferences export key, save-panel directory, window frames, and lifecycle
  timestamp touched by the evidence run were restored to their observed
  pre-run state.
- Obsidian, Bear, Apple Shortcuts, and custom URLs were intentionally not opened
  during manual evidence. Recording-opener tests prove availability-before-open,
  exact rendered URLs, failure behavior, and zero open calls for invalid,
  oversized, or unavailable destinations without causing third-party actions.

## Exit Criteria

- Every adapter consumes the same canonical document: `PASS` in the shared
  destination protocol, six builder tests, 30 adapter tests, and real TXT,
  Markdown, and ZIP output.
- Failures preserve source: `PASS` for write, open, missing-handler, invalid,
  oversized, cancellation, and settings rollback paths, plus exact real Note
  and FTS parity after export.
- Invalid or oversized custom templates produce no external action: `PASS` in
  all component, allowlist, placeholder, 4 KiB, 8 KiB, and opener-gating tests.
- File output round-trips UTF-8 and unsafe filename characters: `PASS` for
  combining Unicode, CJK, emoji, RTL, bounded sanitization, duplicates, both
  file formats, ZIP entries, and the real App output.
- Every Step 5.1 task is implemented: `PASS` in the frozen contract, accepted
  decision, mapped automated suites, real save panels, Settings interaction,
  platform ZIP extraction, and SQLite/FTS inspection.

## Environment Limitation

- The host still has zero valid Apple Development signing identities, so the
  signed `ForNowUITests` runner is unavailable. Native AppKit integration tests
  and real-process Accessibility interaction cover the Step 5.1 paths without
  claiming that the signed runner passed.
- A `screencapture` attempt showed macOS's cross-application data-access shield
  for ChatGPT. No permission was granted and no shielded screenshot was kept;
  control labels, values, dimensions, containment, and actions were verified
  directly through Accessibility instead.

## Deferred Manual Evidence

Physical simultaneous dual-display coverage `MT-WIN-004C` remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
