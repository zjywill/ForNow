# Step 3.5 - Variables

- Status: `DONE`
- Started: 2026-08-06
- Completed: 2026-08-06
- Evidence: `AN-MATH-004`
- Requirement: `FR-MATH-005`
- Required tests: `UT-MATH-005A` through `UT-MATH-005M`, and `ET-MATH-005`

## Files Changed

- `docs/math/VARIABLES_V1.md`
- `docs/math/CONVERSIONS_V1.md`
- `Packages/ForNowModes/Sources/ForNowModes/Variables.swift`
- `Packages/ForNowModes/Sources/ForNowModes/BasicMath.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/EditorProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/VariableAutocompletePanel.swift`
- `Tests/EditorProjectionSpikeTests/VariableTests.swift`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/02_ARCHITECTURE.md`
- `README.md`

## Behavior Contract

- Contract `fornow-variables-v1` freezes colon assignments, names containing
  spaces, normalized identity, whole-document forward and backward references,
  longest complete matching, and stable source-order results and dependencies.
- A first colon is an assignment candidate. Referenced names are selected;
  otherwise only a right side composed from frozen math, unit/currency, or known
  variable vocabulary becomes a declaration. Other prose retains Basic Math V1
  behavior and does not consume the 128-declaration limit.
- Duplicate normalized names all produce `variable-duplicate-name`; V1 does not
  use nearest-prior shadowing. Cycles, dependency failures, paths deeper than 64,
  invalid declarations, and declarations beyond 128 use stable bounded
  diagnostics.
- Every source version rebuilds and evaluates one immutable graph. Editing a
  declaration recomputes all direct and transitive dependents, and results carry
  unique transitive dependency IDs in declaration source order.
- A conversion assignment stores only its canonical Decimal number. A later
  expression does not inherit its unit, currency, rate date, or stale/cache
  metadata.
- Autocomplete starts after three matching letters or digits, matches unique
  valid names case-insensitively, preserves declaration order, and shows at most
  nine entries. Tab chooses the first entry; keys `1...9` and pointer activation
  choose an exact displayed entry.
- The autocomplete panel and all calculation/diagnostic state are projections.
  A selection validates the expected source and UTF-16 range, performs one
  native AppKit replacement, and registers an isolated explicit Undo action.

## Automated Evidence

- The focused Variables suite passes 19 of 19 tests. It covers every required
  `UT-MATH-005A...M` mapping and `ET-MATH-005`, plus colon-prose resource-limit
  isolation, unreferenced autocomplete declarations, and completion Undo after a
  prior undoable edit, Redo, cancellation before large graph preparation, and
  bounded reference-matcher chunking.
- The complete Editor Projection suite passes 189 of 189 tests, including the
  existing Basic Math and conversion contracts, the 10,000-edit Unicode path,
  stale/cancelled projection handling, AppKit accessibility, and source-only
  editing invariants.
- The complete main application suite passes 66 of 66 tests. The persistence
  suite passes 17 of 17 tests and both real crash durability paths pass. The
  window suite passes 10 of 10 tests.
- The Release performance suite passes 3 of 3 tests. Debug and Release unsigned
  builds, strict Swift formatting, generated-project comparison, Shell and Ruby
  syntax, JSON parsing, iOS documentation validation, traceability generation
  and validation, both traceability fault injections, and `git diff --check`
  pass. Traceability reports 65 of 65 evidence entries, 69 of 69 requirements,
  493 mapped macOS test IDs, and 12 decisions.

## Real Application Evidence

- A current Debug application launched with an isolated `CFFIXED_USER_HOME`.
  One real Math note produced `9` through a forward/transitive dependency,
  `1001` from arithmetic using a stored conversion number, and `1 km` only after
  the source explicitly supplied `m to km`. Editing the base declaration from
  `4` to `5` reactively changed the dependent result from `9` to `11`.
- The native panel exposed accessibility label `Variable autocomplete` and two
  source-ordered candidates. Tab selected `number one`; one Undo restored `num`.
  Key `2` selected `number two`; one Undo again restored `num`. The final Tab
  selection plus a source equals sign produced the accessible result `10`.
- Two duplicate declarations and their reference exposed three
  `variable-duplicate-name` diagnostics. Two cyclic declarations and their
  reference exposed three `variable-cycle` diagnostics. All messages were
  accessible and source-free.
- Activating the stored-conversion arithmetic result copied exactly `1001`; the
  previous clipboard contents were restored. Panel presentation, results,
  dependency state, and diagnostics never entered source.
- SQLite and FTS contained the same exact 284-byte canonical source, with no
  result labels, autocomplete text, or diagnostic codes. `PRAGMA quick_check`
  returned `ok`.
- After a normal Quit and isolated relaunch, Previous Note restored the exact
  source plus accessible results `11`, `1001`, `1 km`, and `10` and the same six
  diagnostics. The relaunched process terminated normally, no ForNow process
  remained, and the isolated directory was removed.

## Exit Criteria

- Changing one declaration updates all dependents: `PASS` in
  `UT-MATH-005B...C` and the isolated real-app `9` to `11` edit.
- Cycles and duplicates have stable diagnostics: `PASS` in `UT-MATH-005D...F`
  and the isolated real-app diagnostic inspection.
- Autocomplete never inserts an unconfirmed value: `PASS` in
  `UT-MATH-005K...M`, `ET-MATH-005`, and the real panel/Tab/number/Undo checks.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. Native AppKit integration tests and real-process
Accessibility inspection cover the implemented Step 3.5 paths without waiving
future signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
