# Step 3.3 - Basic Math

- Status: `DONE`
- Started: 2026-08-06
- Completed: 2026-08-06
- Evidence: `AN-MATH-001`
- Requirement: `FR-MATH-001`
- Required tests: `UT-MATH-001A` through `UT-MATH-001Z` and `PT-MATH-001`
- Early interaction coverage: `ET-MATH-006A`

## Files Changed

- `docs/math/GRAMMAR_V1.md`
- `Packages/ForNowModes/Sources/ForNowModes/BasicMath.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/EditorProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionParsing.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditingSession.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `App/MathSettingsStore.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/SettingsView.swift`
- `Tests/EditorProjectionSpikeTests/BasicMathTests.swift`
- `Tests/ForNowTests/MathSettingsTests.swift`
- `PerformanceTests/ForNowPerformanceTests/SmokePerformanceTests.swift`
- `project.yml`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/02_ARCHITECTURE.md`
- `README.md`

## Behavior Contract

- Grammar `fornow-math-expression-v1` is frozen before parser implementation.
  Only body lines of a canonical `math` note with one trailing equals sign are
  eligible. Comments and every other mode emit no Basic Math results or
  diagnostics.
- The lexer and AST support deterministic precedence for documented unary and
  binary operators, parentheses, percentages, factorial and double factorial,
  square and cube roots, logarithms, ceiling, and floor. Unknown descriptive
  words and punctuation may separate tokens but cannot silently join operands.
- Period-decimal and comma-decimal profiles parse locale-specific decimal and
  grouping separators. Space-separated thousands produce a stable diagnostic.
  Parsing is bounded to 512 tokens and 64 levels, and factorial operands are
  bounded to 1,000.
- Ordinary arithmetic and integral powers use checked `Decimal` operations.
  Only roots, logarithms, and non-integral powers use a finite, bounded `Double`
  bridge. No `eval`, JavaScript, LLM, network request, or `NSExpression` is used.
- Canonical copy values are ungrouped and locale-independent. Display rounding
  uses zero through seven maximum fractional digits with half-even rounding;
  thousands grouping is independent. Versioned settings validate before save,
  survive relaunch, reject malformed payloads, and roll back published state on
  write failure.
- Results and diagnostics are source-free, source-versioned editor projections.
  A result appears after the existing trailing equals sign without duplicating
  it. Accessibility announces expression, display result, error state, and
  stable diagnostic code. With no selection, result activation copies the
  canonical value; the established non-empty source-selection priority remains
  unchanged.

## Automated Evidence

- The focused `BasicMathTests` suite passes 29 of 29 tests. The golden fixture
  covers every grammar family, both decimal profiles, formatting settings,
  stable diagnostics, UTF-16 ranges, projection mapping, canonical copy, and
  native AppKit result/diagnostic accessibility.
- The complete Editor Projection suite passes 141 of 141 tests on macOS 26.6.
- The complete main application suite passes 58 of 58 tests, including three
  Math settings round-trip, invalid-payload/value, and save-rollback tests.
- The persistence suite passes 17 of 17 tests and both real SIGKILL durability
  paths pass. The window suite passes 10 of 10 tests.
- The Release performance suite passes 3 of 3 tests. `PT-MATH-001` parses 1,000
  documented expressions for 10 samples at p95 `45.761208 ms`, below its
  `<250 ms` budget.
- Debug and Release builds, strict Swift formatting, generated-project
  comparison, Shell and Ruby syntax, iOS documentation validation, traceability
  generation and validation, both traceability fault injections, and
  `git diff --check` pass. Traceability reports 65 of 65 evidence entries, 69 of
  69 requirements, 493 mapped macOS test IDs, and 12 decisions.

## Real Application Evidence

- A Debug application launched with an isolated `CFFIXED_USER_HOME`. One real
  Math note produced accessible results for precedence, percentage-of,
  factorial, square root, and logarithm syntax, while division by zero exposed
  `math-division-by-zero` and its source-free error message. Visible result
  titles did not repeat the source equals sign.
- Result digits `5` with grouping disabled survived a complete Quit and relaunch;
  `12345.678912` displayed as `12345.67891`. Result digits `0` with grouping
  enabled then survived a second complete Quit and relaunch and displayed the
  same source value as `12,346`. Clicking that formatted result copied canonical
  `12345.678912`.
- SQLite and FTS each contained the same single 78-byte canonical source and no
  derived `14`, `100`, `120`, `12,346`, calculation label, or diagnostic text.
  `PRAGMA quick_check` returned `ok`.
- The isolated process was fully terminated. Its math settings did not appear in
  the standard preference domain, the clipboard was restored after result-copy
  checks, and the isolated evidence directory was removed.

## Exit Criteria

- Golden fixture covers every documented syntax family: `PASS` in
  `UT-MATH-001A` through `UT-MATH-001Z`.
- Invalid input produces diagnostics and never modifies source: `PASS` in parser,
  projection, native AppKit, SQLite, and FTS checks.
- No `eval`, JavaScript, or LLM is used: `PASS` by implementation inspection and
  architecture boundary plus complete repository gates.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. Native AppKit integration tests and real-process
Accessibility inspection cover the implemented Step 3.3 paths without waiving
future signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
