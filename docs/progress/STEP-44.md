# Step 4.4 - Appearance And Settings

- Status: `DONE`
- Started: 2026-08-06
- Completed: 2026-08-06
- Evidence: `AN-UI-001`, `AN-NOTE-SET-001`, `AN-REV-002`
- Requirements: `FR-UI-001`, `FR-UI-002`, `FR-UI-003`, `FR-EDIT-007`,
  `FR-NOTE-009`
- Decision: `FORNOW-DECISION-016`
- ADR: `ADR-007`

## Files Changed

- `docs/appearance/APPEARANCE_V1.md`
- `docs/decisions/ADR-007_APPEARANCE_AND_SETTINGS_PRESENTATION.md`
- `Packages/ForNowDesign/Sources/ForNowDesign/Appearance.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/PaperBackgroundView.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `App/AppearanceSettingsStore.swift`
- `App/QuickActionSettings.swift`
- `App/QuickActionSettingsSection.swift`
- `App/SettingsView.swift`
- `App/ForNowCommands.swift`
- `App/AppEnvironment.swift`
- `Tests/ForNowTests/AppearanceAndShortcutSettingsTests.swift`
- `Tests/EditorProjectionSpikeTests/AppearanceProjectionTests.swift`
- `Packages/ForNowDesign/Tests/ForNowDesignTests/AppearanceTests.swift`
- `UITests/ForNowUITests/LaunchTests.swift`
- `docs/00_SOURCE_LEDGER.md`
- `docs/01_PRODUCT_SPEC.md`
- `docs/02_ARCHITECTURE.md`
- `docs/traceability.yml`
- `README.md`

## Behavior Contract

- Contract `fornow-appearance-v1` uses four semantic built-in themes. Light and
  dark selections persist independently, and every primary, secondary, and
  control text pair meets a WCAG contrast ratio of at least 4.5.
- Blank, lined, dotted, small-grid, and large-grid paper are independent from
  theme. Subtle, clear, and bold visibility are explicit values. List mode uses
  separate lined and non-lined spacing settings.
- XS, S, M, L, and XL are stable system-font sizes. Double size multiplies the
  selected value by two. Command-minus and Command-plus step and clamp without
  creating an Undo entry.
- Native material is optional on macOS 15 or newer. Background opacity is
  clamped to `0...90`; mismatched theme appearance requires confirmation;
  Reduce Transparency restores a solid canvas and Increase Contrast strengthens
  marks and adds a border.
- Natural, LTR, and RTL are source-free paragraph presentation. Natural RTL list
  items place their checkbox in the right gutter while retaining the original
  UTF-16 source range.
- Appearance, paper, material, type, direction, shortcut controls, and
  diagnostics never enter `Note.body`, parser input, SQLite, FTS, clean copy,
  source revision, or Undo.
- Quick-action shortcuts are a complete versioned map. Drafts validate live for
  duplicates, reserved commands, missing modifiers, and the registered global
  invocation. Save is disabled while invalid. Startup repairs an independently
  persisted conflict without replacing the working global invocation.

## Automated Evidence

- `ForNowDesignTests` passes 3 of 3 theme, contrast, paper/material policy, and
  text-size tests. `AppearanceAndShortcutSettingsTests` passes 6 of 6 migration,
  persistence, zoom, validation, rollback, and startup-reconciliation tests.
- `AppearanceProjectionTests` passes 6 of 6 tests using real AppKit views and an
  `NSWindow`. It covers source/Undo invariance, theme and size updates, five
  distinct paper renders, independent list spacing, source transitions into and
  out of List Mode, and a natural RTL checkbox in the right gutter.
- The complete main application suite passes 102 of 102 tests and the complete
  Editor Projection suite passes 267 of 267, with zero failures, expected
  failures, or skips. Persistence passes 18 of 18 plus both crash-fault workers;
  Window passes 11 of 11; Release Performance passes 3 of 3.
- The first Release performance run exposed a Step 4.4 regression:
  `PT-EDIT-001` measured `10.114167 ms` p95, and a focused repeat measured
  `9.759208 ms` against the `<4 ms` budget. Appearance had synchronously
  reapplied a full-document temporary paragraph style after every edit. The
  editor now reapplies it only when source enters or exits List Mode. The final
  30-sample run measured `0.045209 ms` p50, `0.060292 ms` p95, and
  `0.076166 ms` worst; the 1,000-line math p95 was `61.573625 ms`.
- Debug and Release unsigned builds, strict Swift formatting, generated-project
  comparison, traceability generation and validation, both traceability fault
  injections, iOS documentation validation, and `git diff --check` pass.
  Traceability maps 65 of 65 evidence entries, 69 of 69 requirements, 494 test
  IDs, and 16 decisions.

## Real Application Evidence

- A current Debug application ran through LaunchServices with the production
  repository and an isolated `CFFIXED_USER_HOME`. System keyboard events entered
  exact source `list\nappearance source exact\nrtl source`; opening Settings
  moved focus and committed the binding before appearance interaction.
- The real Settings window selected lined paper, XL, and double size. Closing it
  left the Accessibility editor value byte-for-byte unchanged. A normal Quit
  flushed one Note and one FTS row. Both were the same 39 bytes with hex
  `6c6973740a617070656172616e636520736f757263652065786163740a72746c20736f75726365`,
  and `PRAGMA quick_check` returned `ok`.
- `CFFIXED_USER_HOME` isolates the production database but not Core Foundation
  preferences on this host. The evidence run therefore restored the user's
  observed pre-run appearance values (`Blank`, `M`, double size off) through the
  same Settings UI, restored the original Simplified Chinese input source, quit
  normally, and left no ForNow process running.
- Real UI inspection confirmed lined paper at XL double size, small-grid native
  translucency at 42 percent, Command-minus/plus size changes, a mismatch
  confirmation sheet, natural Persian RTL checkbox placement, and unchanged
  source throughout. Supporting images are in `docs/progress/assets/`:
  `step-44-lined-double-size.png`, `step-44-grid-translucency.png`,
  `step-44-theme-mismatch-warning.png`, `step-44-shortcut-settings.png`, and
  `step-44-shortcut-conflict.png`.
- The quick-action form contains every key field inside the 640-point Settings
  window and no longer exposes a visible repeated `Key` label. An Option-A
  New Note draft immediately displayed its global-invocation conflict, disabled
  Save, and left the active New Note menu binding at Command-N.

## Exit Criteria

- All themes pass contrast checks: `PASS` for every defined semantic pair in
  `UT-UI-001`.
- Longest setting labels fit supported window sizes: `PASS` in the real
  640-point Settings window and the mapped `UIT-UI-003` geometry assertions.
- Settings cannot make global invocation unreachable: `PASS` for draft/save,
  global replacement, persistence failure, and startup repair paths.
- Every Step 4.4 task is implemented: `PASS` in the frozen contract, mapped
  automated suites, real Accessibility interaction, and SQLite/FTS inspection.

## Environment Limitation

`./scripts/test-ui.sh` exits with status 2 before starting the runner because
this host has zero valid Apple Development signing identities on macOS 26. The
message is `UI tests require an Apple Development signing identity on macOS
26.` Native AppKit integration tests and real-process Accessibility inspection
cover the implemented paths without claiming that the signed UI runner passed.

## Deferred Manual Evidence

A bounded live recheck found one online, non-mirrored `Mi Monitor` in
`system_profiler SPDisplaysDataType` and `NSScreen.screens.count == 1`.
`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
