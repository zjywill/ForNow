# ForNow Basic Math Grammar V1

Grammar ID: `fornow-math-expression-v1`

This document freezes the Step 3.3 parser contract before implementation. It
implements `AN-MATH-001` and `FR-MATH-001`; later unit, currency, variable, and
aggregate phases extend the pipeline after this grammar instead of changing its
meaning.

## Eligibility

- A note must resolve to canonical mode ID `math` through `ModeHeaderParser`.
- Only body lines are considered. The header and its optional title are never
  part of an expression.
- Leading-whitespace `//` comment lines are ignored.
- Ignoring trailing horizontal whitespace, a line must end in one `=`. The
  equals sign requests evaluation and remains canonical source.
- An empty expression before `=` produces `math-empty-expression`.
- List, sum, average, count, code, timer, and plain notes do not emit Basic Math
  results or diagnostics. Aggregate modes reuse the evaluator in Step 3.6.

## Locale

V1 has two deterministic interpretation profiles:

| Profile | Decimal | Grouping | Examples |
|---|---:|---:|---|
| `periodDecimal` | `.` | `,` | `1,000.25`, `.5` |
| `commaDecimal` | `,` | `.` | `1.000,25`, `,5` |

Grouping must contain exactly three digits per group. A space or tab between
digits is never a grouping separator; input such as `1 000,25` produces
`math-spaced-thousands-unsupported`. Source interpretation never guesses a
third separator profile.

## Lexical Rules

The lexer scans UTF-16 source ranges and emits the longest valid token.

- Numbers follow the active locale table above.
- Operators are `+`, `-`, `*`, `x`, `X`, `/`, `÷`, `^`, and `**`.
- Grouping tokens are `(` and `)`.
- Postfix tokens are `%`, `!`, and `!!`; `!!` wins longest-match.
- Prefix root tokens are `√` and `∛`.
- Case-insensitive words `sqrt`, `log`, `log2`, `ceil`, and `floor` are
  functions and require parentheses.
- The case-insensitive word `of` is an operator only after a percentage value.
- Other words, currency symbols, and punctuation are separators and are
  stripped as documented. Stripping cannot make adjacent numeric operands
  valid; `10 apples 20 =` is an error, not `1020` or `30`.
- At least one numeric token and one complete expression are required.

## EBNF

```text
expression     = additive ;
additive       = multiplicative, { ("+" | "-"), multiplicative } ;
multiplicative = unary, { ("*" | "x" | "X" | "/" | "÷" | "of"), unary } ;
unary          = ("+" | "-"), unary | power ;
power          = postfix, [ ("^" | "**"), unary ] ;
postfix        = primary, [ "%" ], [ "!" | "!!" ] ;
primary        = number
               | "(", expression, ")"
               | ("√" | "∛"), unary
               | function, "(", expression, ")" ;
function       = "sqrt" | "log" | "log2" | "ceil" | "floor" ;
```

Power is right associative. Power binds more tightly than unary signs, so
`-2^2` is `-(2^2)` and `2^-2` is valid. Postfix operators bind before power.
Implicit multiplication is not supported.

## Evaluation

- Literal, unary, additive, multiplicative, division, integral power, percent,
  and factorial operations use Foundation `Decimal` operations.
- Division by zero produces `math-division-by-zero`.
- `value%` evaluates to `value / 100` in multiplicative contexts.
- `base + value%` and `base - value%` apply the percentage to `base`; therefore
  `100 + 15% = 115`.
- `value% of base` is multiplication of the percentage ratio by `base`;
  therefore `50% of 200 = 100`.
- `!` is factorial and `!!` is double factorial. Operands must be non-negative
  integers no greater than 1,000; Decimal overflow still terminates evaluation
  earlier with `math-overflow`.
- `sqrt` and `√` reject negative values. `∛` preserves the sign.
- `log` is base 10 and `log2` is base 2; both require a positive argument.
- `ceil` and `floor` return integral Decimal values.
- Non-integral powers and roots/logarithms use a bounded `Double` bridge, reject
  non-finite input or output, and convert the finite result back to Decimal.
- Every Decimal operation checks calculation status. Overflow, underflow,
  divide-by-zero, and invalid results never produce a decoration.

The parser limits one line to 512 tokens and 64 nested expressions. Exceeding a
limit produces `math-resource-limit` without evaluating the remaining input.

## Output

- `canonicalValue` is the locale-independent, ungrouped Decimal value using `.`
  as its decimal separator. Copying a result copies this value.
- The setting historically named `significantDigits` accepts `0...7`. Because
  zero is valid, V1 defines it as the maximum displayed fractional digits; it
  does not round the canonical value. Rounding is decimal half-even and trailing
  fractional zeros are omitted.
- Thousands grouping is an independent Boolean. When enabled, display uses the
  active locale's grouping separator; when disabled, no grouping is inserted.
- A result decoration anchors immediately after the source line's trailing
  equals sign. It never enters `NSTextStorage`, `Note.body`, SQLite, FTS, undo,
  selection coordinates, clean export, or ordinary source copy.

## Diagnostics

Diagnostics contain a stable code, UTF-16 source range, and source-free message.
V1 codes are:

- `math-empty-expression`
- `math-invalid-number`
- `math-spaced-thousands-unsupported`
- `math-unexpected-token`
- `math-missing-operand`
- `math-missing-closing-parenthesis`
- `math-division-by-zero`
- `math-domain-error`
- `math-factorial-domain`
- `math-overflow`
- `math-underflow`
- `math-resource-limit`

Diagnostics are presentation only. Invalid input must leave source, selection,
undo history, persistence, copy output, and unrelated valid line results
unchanged.
