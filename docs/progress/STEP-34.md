# Step 3.4 - Units And Currency

- Status: `DONE`
- Started: 2026-08-06
- Completed: 2026-08-06
- Evidence: `AN-MATH-003`
- Requirements: `FR-MATH-003`, `FR-MATH-004`
- Required tests: `UT-MATH-003A` through `UT-MATH-003N`, `UT-MATH-004A`
  through `UT-MATH-004N`, `IT-MATH-004`, and `ST-MATH-004`

## Files Changed

- `docs/math/CONVERSIONS_V1.md`
- `Packages/ForNowCore/Sources/ForNowCore/CurrencyRates.swift`
- `Packages/ForNowModes/Sources/ForNowModes/Conversions.swift`
- `Packages/ForNowModes/Sources/ForNowModes/Resources/Units/v1/*.json`
- `Packages/ForNowModes/Sources/ForNowModes/Resources/Currencies/iso-4217-v1.json`
- `Packages/ForNowModes/Sources/ForNowModes/BasicMath.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/CurrencyRateProvider.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/EditorProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionParsing.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ClipboardProjection.swift`
- `App/CurrencyRateRefreshCoordinator.swift`
- `App/MathSettingsStore.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/SettingsView.swift`
- `Tests/EditorProjectionSpikeTests/ConversionTests.swift`
- `Tests/ForNowTests/CurrencyRateTests.swift`
- `Tests/ForNowTests/MathSettingsTests.swift`
- `project.yml`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/02_ARCHITECTURE.md`
- `README.md`

## Behavior Contract

- Contract `fornow-conversions-v1` freezes `in`/`to`, five unit categories,
  versioned fixture schemas, ISO currencies, omission rules, custom/provider
  precedence, rate-state labels, canonical copy, stable diagnostics, and bounds.
- Unit fixtures map every documented distance, area, volume, mass, and
  temperature ID to Foundation `Measurement`. Strict loading rejects missing or
  wrong-version fixtures, category mismatches, duplicate IDs and normalized
  aliases, malformed currencies, cross-currency alias collisions, and missing
  runtime mappings.
- Arithmetic before a source unit or currency is evaluated by the frozen Basic
  Math V1 engine. Arithmetic after a target is rejected. Incompatible dimensions
  and unknown sources or targets produce bounded, source-free diagnostics.
- Explicit currency codes, configured primary symbol, primary-source omission,
  and secondary-target omission are deterministic. Rate precedence is direct
  custom, inverse custom, then provider cross-rate. A cache exactly 24 hours old
  is stale; display includes the rate date/state while copy omits metadata.
- `MathSettings` version 2 preserves the Step 3.3 formatting fields and adds
  primary/secondary currencies, primary symbol, opt-in automatic refresh, and
  validated custom rates. Version 1 migrates with explicit defaults.
- Automatic refresh is disabled by default and limited to one attempted request
  per rolling 24 hours. Manual refresh remains explicit. Cancellation cannot
  silently fall back to a cached success.
- ECB traffic is a body-free GET to one fixed HTTPS endpoint. The response is
  streamed under a hard size bound and parsed with external entities disabled;
  note text never enters the rate-provider API.

## Automated Evidence

- The focused conversion suite passes 29 of 29 tests. It covers all required
  `UT-MATH-003A...N` and `UT-MATH-004A...M` mappings plus invalid snapshots and
  native AppKit accessibility/copy behavior. `UT-MATH-004N` is covered in the
  main application suite by the fixed-request privacy test.
- The complete Editor Projection suite passes 170 of 170 tests, including the
  existing 10,000-edit Unicode mapping path and cancellation coverage.
- The complete main application suite passes 66 of 66 tests, including v1-to-v2
  migration, every v2 settings field and custom-rate round-trip, invalid and
  duplicate custom-rate rejection, cache restart, offline fallback, request
  throttling, response bounds, XML validation, and cancellation semantics.
- The persistence suite passes 17 of 17 tests and both real SIGKILL durability
  paths pass. The window suite passes 10 of 10 tests.
- The Release performance suite passes 3 of 3 tests. Debug and Release unsigned
  builds, strict Swift formatting, generated-project comparison, Shell and Ruby
  syntax, JSON parsing, iOS documentation validation, traceability generation
  and validation, both traceability fault injections, and `git diff --check`
  pass. Traceability reports 65 of 65 evidence entries, 69 of 69 requirements,
  493 mapped macOS test IDs, and 12 decisions.

## Real Application Evidence

- A Debug application launched with an isolated `CFFIXED_USER_HOME`. One real
  Math note produced accessible `4.572 m`, `10000 m²`,
  `80 EUR · custom 2001-01-01`, and `20 EUR · custom 2001-01-01` results.
  Incompatible units, arithmetic after a target, and an unknown currency exposed
  `conversion-incompatible-units`, `conversion-composition-unsupported`, and
  `currency-unknown-code`.
- Clicking the currency result copied exactly `80 EUR`, without its custom-rate
  metadata. The previous clipboard value was restored after the check.
- After a normal Quit and isolated relaunch, navigation restored the exact
  eight-line source plus the same four accessible results and three diagnostics.
  SQLite and FTS contained the same 103-byte canonical source and no result,
  rate-state label, or diagnostic code. `PRAGMA quick_check` returned `ok`. The
  relaunched process was fully terminated and its isolated directory removed.

## Exit Criteria

- All fixture aliases resolve deterministically: `PASS` in
  `UT-MATH-003A...N` and strict fixture fault coverage.
- Network-off tests pass: `PASS` for disabled/unavailable rates, custom rates,
  compatible cached fallback, stale labels, and cancellation behavior.
- Note text is never included in a rate request: `PASS` in `UT-MATH-004N`; the
  provider accepts only a currency base, and the real SQLite/FTS source remains
  undecorated.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. Native AppKit integration tests and real-process
Accessibility inspection cover the implemented Step 3.4 paths without waiving
future signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
