# ForNow Variables V1

Contract ID: `fornow-variables-v1`

This document freezes the Step 3.5 variable grammar, dependency policy,
autocomplete contract, diagnostics, and bounds. It extends
`fornow-math-expression-v1` and `fornow-conversions-v1` without changing either
frozen grammar.

## Eligibility

- Variables are active only in the body of a note whose current mode settings
  resolve the first line to canonical `math` mode.
- Blank lines and lines whose trimmed source begins with `//` are ignored.
- An ordinary expression still requires one trailing `=` to request a result.
- An assignment is evaluated even without a trailing `=` because later lines
  may depend on it. A trailing `=` additionally requests a result decoration
  for the assignment line.

## Assignment Grammar

```text
assignment := name ":" expression ["="]
name       := name-character (name-character | horizontal-space)*
```

- A line with a first colon is an assignment candidate. It is selected as an
  assignment when its normalized name is referenced elsewhere in the document,
  or when every word on the right side belongs to the frozen Basic Math,
  unit/currency, or already-declared-variable vocabulary. A candidate whose
  right side contains other prose remains an ordinary Basic Math line. This
  preserves existing inputs such as `Lunch: $10 + USD 20 dollars =` while
  keeping unreferenced declarations such as `number of guests: 9` available to
  autocomplete.
- A name contains Unicode letters and decimal digits separated by spaces or
  tabs. It must contain at least one letter and is limited to 64 UTF-16 units.
- Leading and trailing horizontal whitespace is not part of the name.
- Name identity uses precomposed Unicode, collapsed internal horizontal
  whitespace, and locale-independent case folding. The original spelling of a
  unique declaration remains its display and insertion spelling.
- The document may contain at most 128 selected declarations. Colon prose that
  remains an ordinary Basic Math line does not consume this limit.
- The right side may be any Basic Math V1 expression or Step 3.4 unit/currency
  conversion. The optional trailing equals sign is not part of the right side.

## References And Graph

- A reference is a complete, case-insensitive match for a declared normalized
  name. Letter, number, and underscore characters cannot border a match.
- When names overlap, the longest complete name wins. Remaining ties use stable
  declaration source order.
- The graph includes the entire current document, so both forward and backward
  references are supported.
- Evaluation is deterministic for one source version. Declarations are emitted
  and ordinary requested results are returned in stable source order.
- A result records unique transitive dependency IDs in declaration source
  order. IDs use the declaration's preserved spelling.
- Dependency traversal is limited to 64 declarations. A document edit rebuilds
  the graph and all dependent values from the new immutable source version.

## Duplicate Policy

V1 uses an error policy, not nearest-prior shadowing. Every declaration sharing
one normalized name emits `variable-duplicate-name`; none of those declarations
provides a value. A reference to that name emits the same diagnostic. This keeps
results independent of cursor position and prevents an edit from silently
changing which declaration wins.

## Conversion Values

- A conversion assignment may display its normal unit/currency result when the
  declaration ends in `=`.
- The stored graph value is only the canonical Decimal numeric value.
- A later reference does not inherit a unit, currency code, or rate metadata.
  The user must write a new source unit or currency when using that number in a
  later conversion.

## Autocomplete

- Autocomplete is a pure source/selection projection and is available only at
  an empty selection in a Math body expression, never on an assignment name.
- The current expression suffix must contain at least three letters or digits.
- Matching is case-insensitive prefix matching against unique valid variable
  names. Results use declaration source order and are capped at nine visible
  entries.
- Tab accepts the first visible result. Keys `1` through `9` accept the
  corresponding visible result. Pointer activation accepts that exact result.
- Escape dismisses the current projection. Typing, selection movement, or a
  source-version change recomputes it.
- Showing, filtering, or dismissing autocomplete never changes source. An edit
  plan applies only when its expected source and replacement range still match,
  and insertion is one native editor replacement.

## Stable Diagnostics

Step 3.5 adds:

- `variable-invalid-declaration`
- `variable-duplicate-name`
- `variable-cycle`
- `variable-depth-limit`
- `variable-dependency-unavailable`
- `variable-resource-limit`

Diagnostics contain a stable code, a bounded UTF-16 source range, and a
source-free message. Cyclic declarations emit `variable-cycle`; a non-cyclic
line that depends on a failed declaration emits
`variable-dependency-unavailable`.

## Source Integrity And Bounds

- Variable values, graph edges, diagnostics, autocomplete state, and results are
  projections. None is written into `Note.body`, SQLite FTS, or clipboard text
  unless the user explicitly copies a result.
- Parsing retains the existing per-32-line cancellation checks. Reference
  regular expressions are compiled in chunks of at most 128 candidate names,
  the evaluated graph is bounded to 128 selected declarations, expression
  parsing retains the Basic Math V1 token/depth limits, and autocomplete exposes
  at most nine results.
