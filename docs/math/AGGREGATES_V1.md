# ForNow Aggregate Modes V1

Grammar ID: `fornow-aggregates-v1`

This document freezes the Step 3.6 contract for `AN-MATH-002` and
`FR-MATH-002`. Aggregate evaluation reads the complete canonical note but only
emits derived results and diagnostics.

## Eligibility and Order

- The first line must resolve through `ModeHeaderParser` to canonical mode ID
  `sum`, `average`, or `count`. Custom aliases retain the canonical behavior.
- The optional header title is never input. The single aggregate result is
  anchored after the header source range.
- Body lines are visited in source order. Results and diagnostics are stable for
  identical source, settings, and locale.
- A line whose horizontally trimmed source is empty or starts with `//` is
  excluded from all aggregate input.

## Sum and Average Extraction

- Every valid numeric token on an eligible line is a value. Text, currency
  symbols or codes, brackets, and surrounding punctuation are separators and
  are stripped without joining separated digits.
- ASCII `+` and `-`, plus Unicode minus `−`, are signs only when adjacent to the
  numeric token. Parentheses have no accounting-negative meaning in V1.
- The active `periodDecimal` or `commaDecimal` profile is identical to Basic
  Math V1. Grouping must contain exactly three digits per group. A token is at
  most 38 digits, matching Foundation `Decimal` precision.
- A single active decimal separator may lead a token (`.5` or `,5`). Trailing
  periods and commas are punctuation. Scientific notation is not supported.
- A line may contain multiple values. Average divides the checked Decimal sum by
  the number of accepted values, not by the number of lines.
- A line with no numeric token is ignored. Sum of no values is `0`; Average with
  no values produces `aggregate-no-values` and no result.

## Rejection and Isolation

- Slash fractions (`1/2`, `1 / 2`, or fraction slash `1⁄2`) and Unicode vulgar
  fractions are rejected with `aggregate-fraction-unsupported`. The complete
  line is excluded so a fraction can never become two values.
- A malformed locale number or scientific notation produces
  `aggregate-invalid-number`. The complete line is excluded; later valid lines
  still contribute.
- Decimal overflow produces `aggregate-overflow` and no aggregate result.
- Parsing is cancellable every 32 body lines and numeric candidates. V1 accepts
  at most 10,000 body lines and 10,000 Sum/Average values; exceeding either bound produces
  `aggregate-resource-limit` and no partial result.

## Count

- Count includes every body line whose horizontally trimmed source is non-empty
  and does not start with `//`.
- Count does not interpret numbers. Text, malformed numbers, and fractions are
  ordinary eligible items and do not produce numeric diagnostics.
- An empty Count note produces `0`.

## Projection and Scope

- Canonical Decimal text is copied; display rounding and grouping follow the
  existing Math settings without changing the copied value.
- Results, diagnostics, and accessibility controls are projections. They never
  enter `Note.body`, SQLite, FTS, clean copy, or Undo history.
- `FORNOW-DECISION-002` limits ForNow 1.0 Count to item count. Grade Level and
  Reading Ease remain omitted until a versioned formula and independent fixture
  are approved.

## Golden Fixture

`Resources/Aggregates/numeric-extraction-v1.json` is schema version 1 and covers
text, currency, punctuation, blank lines, comments, malformed numbers,
fractions, both decimal profiles, and Count eligibility.
