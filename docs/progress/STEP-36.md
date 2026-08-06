# Step 3.6 - Sum, Average, Count

- Status: `DONE`
- Started: 2026-08-06
- Completed: 2026-08-06
- Evidence: `AN-MATH-002`
- Requirement: `FR-MATH-002`
- Scope decision: `FORNOW-DECISION-002`
- Required tests: `UT-MATH-002A` through `UT-MATH-002J`

## Files Changed

- `docs/math/AGGREGATES_V1.md`
- `Packages/ForNowModes/Sources/ForNowModes/Aggregates.swift`
- `Packages/ForNowModes/Sources/ForNowModes/Resources/Aggregates/numeric-extraction-v1.json`
- `Packages/ForNowEditor/Sources/ForNowEditor/EditorProjection.swift`
- `Tests/EditorProjectionSpikeTests/AggregateTests.swift`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/01_PRODUCT_SPEC.md`
- `docs/02_ARCHITECTURE.md`
- `docs/traceability.yml`
- `README.md`

## Behavior Contract

- Contract `fornow-aggregates-v1` selects only canonical Sum, Average, and Count
  modes, reads the complete body in source order, and emits one result anchored
  after the header. Titles never contribute.
- Sum and Average extract every locale-valid numeric token from eligible lines.
  Text, currency material, brackets, and surrounding punctuation are stripped;
  accepted signs, grouping, decimals, 38-digit precision, empty-input behavior,
  and canonical copy are frozen in the versioned contract and fixture.
- Slash and vulgar fractions reject their complete line with
  `aggregate-fraction-unsupported`. Malformed locale numbers and scientific
  notation reject their complete line with `aggregate-invalid-number`. Other
  valid lines still contribute, and diagnostics remain in stable source order.
- Count includes every non-empty, non-comment body line without interpreting its
  numeric syntax. Fractions, malformed numbers, and text therefore remain Count
  items. Sum of no values is zero; Average with no values is unavailable; empty
  Count is zero.
- Parsing checks cancellation every 32 lines and numeric candidates and rejects
  more than 10,000 body lines or values without emitting a partial result.
- Result buttons, diagnostics, display formatting, copy controls, and
  accessibility labels remain projections. `Note.body`, SQLite, FTS, clean copy,
  and Undo history contain canonical source only.
- `FORNOW-DECISION-002` is now machine-mapped to `FR-MATH-002`. ForNow 1.0
  implements item count but omits Grade Level and Reading Ease until a versioned
  formula and independent fixtures are approved.

## Automated Evidence

- The focused `AggregateTests` suite passes 16 of 16 tests. It maps every
  required `UT-MATH-002A...J` and also covers custom aliases, schema rejection,
  deterministic order, single-line value bounds, body-line bounds, and
  cancellation inside one large line.
- The bundled schema-version-1 golden fixture covers text, currency,
  punctuation, blank lines, comments, malformed numbers, fractions, both
  decimal profiles, and Count eligibility.
- The complete Editor Projection suite passes 205 of 205 tests, including all
  existing Basic Math, conversion, variable, AppKit, source-only, cancellation,
  and 10,000 randomized Unicode edit coverage.
- The complete main application suite passes 66 of 66 tests. The persistence
  suite passes 17 of 17 tests and both crash fault paths pass. The window suite
  passes 10 of 10 tests.
- The Release performance suite passes 3 of 3 tests. Debug and Release unsigned
  builds, strict Swift formatting, Shell and Ruby syntax, JSON parsing, iOS
  documentation validation, traceability generation and validation, both
  traceability fault injections, and `git diff --check` pass.

## Real Application Evidence

- A current Debug application launched with an isolated `CFFIXED_USER_HOME`.
  A Sum note projected accessible result `34` from `$10`, `20`, and `4`, rejected
  `1/2` and malformed `1,23` as separate stable diagnostics, excluded `// 100`,
  and copied canonical `34` when its result button was activated.
- Separate Average and Count notes projected accessible results `20` and `4`.
  Average excluded its comment; Count included ordinary text, `1/2`, and `1,23`
  while excluding its comment. Activating the Count result copied canonical `4`.
- SQLite and FTS contained the same three exact source bodies of 53, 27, and 44
  bytes. No result, accessibility label, or diagnostic code entered source, and
  `PRAGMA quick_check` returned `ok`.
- After a normal Quit and isolated relaunch, Previous Note restored Count `4`,
  Average `20`, and Sum `34` in order. The Sum fraction and invalid-number
  diagnostics also returned with the same accessible messages and stable codes.
- The relaunched process quit normally. The isolated directory was removed, the
  clipboard was empty, and no ForNow process remained.

## Exit Criteria

- Golden fixtures cover text, currency, punctuation, blank, comments, invalid
  numbers, and fractions: `PASS` in `UT-MATH-002I` and strict fixture loading.
- Result order is stable: `PASS` in repeat-evaluation coverage, canonical
  one-result-per-note projection, and Quit/relaunch navigation.
- Aggregate result decoration and copy remain source-only: `PASS` in
  `UT-MATH-002J`, real App accessibility/copy, SQLite, and FTS inspection.
- Reading metrics are explicitly omitted: `PASS` in `FORNOW-DECISION-002`, the
  product spec, architecture, README, walkthrough, and generated traceability.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. Native AppKit integration tests and isolated real-process
Accessibility inspection cover the implemented Step 3.6 paths without waiving
future signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
