# ForNow Units And Currency Contract V1

Contract ID: `fornow-conversions-v1`

This document freezes the Step 3.4 conversion grammar, fixture schema, rate
precedence, and privacy boundary before parser or provider implementation. It
implements `AN-MATH-003`, `FR-MATH-003`, and `FR-MATH-004` without changing
Basic Math grammar `fornow-math-expression-v1`.

## Eligibility

- Conversions are evaluated only on eligible trailing-equals body lines of a
  canonical `math` note.
- Comments and `plain`, `list`, `sum`, `average`, `count`, `code`, and `timer`
  notes emit no conversion result or diagnostic.
- The numeric amount before a source unit or currency is evaluated by Basic Math
  V1. Arithmetic before conversion is valid; arithmetic after a conversion
  target produces `conversion-composition-unsupported`.
- Assignments and variables remain unavailable until Step 3.5.

## Unit Syntax

```text
numeric-expression source-unit ("in" | "to") target-unit =
```

Examples:

```text
1 km in m =
(10 + 5) ft to m =
0 c in f =
```

Both units are mandatory. Matching is case-insensitive after canonical Unicode
composition and whitespace folding. The longest complete alias wins. Unit
categories are distance, area, volume, mass, and temperature. A source and
target from different categories produce `conversion-incompatible-units`.

## Currency Syntax

Explicit codes use three ASCII letters from the currency fixture:

```text
numeric-expression SOURCE in TARGET =
numeric-expression SOURCE to TARGET =
```

Preferences fill one omitted side through these deterministic forms:

- `100 in EUR =` uses the configured primary currency as the source.
- `100 USD =` uses the configured secondary currency as the target.
- `$100 in EUR =` and `100$ in EUR =` use the configured bare primary symbol;
  the actual symbol is user-configurable and matching is exact.
- `$100 =` uses primary as source and secondary as target.
- A bare numeric line such as `100 =` remains Basic Math and is not a currency
  conversion.

The source and target may be equal; the result is the unchanged amount with the
same normal result and rate metadata rules. Currency codes are always copied and
displayed in uppercase.

## Fixture Schema

Unit fixture paths are
`Packages/ForNowModes/Sources/ForNowModes/Resources/Units/v1/<category>.json`.
Each file has this shape:

```json
{
  "schemaVersion": 1,
  "category": "distance",
  "units": [
    {
      "id": "meter",
      "symbol": "m",
      "aliases": ["m", "meter", "meters", "metre", "metres"]
    }
  ]
}
```

The currency fixture path is
`Packages/ForNowModes/Sources/ForNowModes/Resources/Currencies/iso-4217-v1.json`:

```json
{
  "schemaVersion": 1,
  "currencies": [
    {
      "code": "USD",
      "name": "US Dollar",
      "aliases": ["US$"]
    }
  ]
}
```

Fixture validation rejects unsupported versions, missing categories, unknown
unit IDs, duplicate IDs, duplicate normalized aliases, malformed currency
codes, and cross-currency alias collisions. The runtime unit mapping must cover
every fixture unit exactly once through Foundation `Measurement`.

## Rate Precedence

For a source/target currency pair, V1 resolves rates in this order:

1. exact user-defined source-to-target rate;
2. reciprocal of an exact user-defined target-to-source rate;
3. cross-rate from the current provider snapshot;
4. `currency-rates-unavailable` or `currency-rate-missing` diagnostic.

Every custom rate is positive and carries its user-edit timestamp. Custom rates
override cached and remote values. A provider snapshot contains a base code,
positive rates, its rate timestamp, and provenance. One base snapshot can derive
any pair for which both currencies are present.

## Cache And Refresh

- The application loads a local cached snapshot without network access.
- Manual Refresh is an explicit network action and may run while automatic
  refresh is disabled.
- Daily refresh is disabled by default. Enabling it permits one automatic
  attempt only when at least 24 hours have elapsed since the previous automatic
  attempt. The attempt timestamp is recorded before the request, so failures do
  not cause an automatic retry loop. A backward clock change does not refresh.
- A remote failure falls back to a compatible cached snapshot. No cache produces
  a clear unavailable diagnostic.
- A cached rate is stale when its rate timestamp is at least 24 hours older than
  evaluation time. Stale cached rates remain usable and are labeled explicitly.

## Output

- Unit display is `<formatted-number> <fixture-symbol>`.
- Currency display is `<formatted-number> <TARGET>` followed by one status:
  `custom YYYY-MM-DD`, `rate YYYY-MM-DD`, `cached YYYY-MM-DD`, or
  `stale cache YYYY-MM-DD`. Dates are UTC Gregorian dates.
- `canonicalValue` remains the locale-independent ungrouped numeric value.
- `copiedText` is `<canonicalValue> <canonical-unit-symbol-or-currency-code>` and
  never includes cache, age, or provider text.
- Result accessibility announces the complete expression, formatted result,
  unit or currency, and rate state. Diagnostics announce their error state and
  stable code.
- Results, rate metadata, and diagnostics never enter source, SQLite, FTS, clean
  export, selection coordinates, or undo history.

## Privacy And Bounds

- `CurrencyRateProvider` accepts only a validated base `CurrencyCode`; its API
  has no note-text parameter.
- The selected remote provider uses one fixed HTTPS endpoint. Requests contain
  no note text in URL, query, headers, or body.
- Currency rate responses are size bounded, structurally validated, and reject
  missing, duplicate, zero, negative, or non-finite rates.
- Unit conversion is entirely local. Currency conversion is deterministic and
  offline when a custom rate or cached snapshot is available.

## Diagnostics

Step 3.4 adds these stable codes:

- `conversion-unknown-source-unit`
- `conversion-unknown-target-unit`
- `conversion-incompatible-units`
- `conversion-composition-unsupported`
- `conversion-overflow`
- `currency-unknown-code`
- `currency-rates-unavailable`
- `currency-rate-missing`
- `currency-invalid-rate`

All diagnostic ranges use UTF-16 source coordinates and leave unrelated valid
lines and canonical source unchanged.
