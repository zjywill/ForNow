# ForNow

ForNow is a native macOS temporary scratchpad inspired by the workflow category
demonstrated by AntiNote. It is a clean-room implementation: behavior may be
studied and independently reproduced, but source code, branding, copy, icons,
themes, screenshots, and proprietary assets must not be copied.

Product line: **Notes, for now.**

## Status

Implementation is following the ordered gates in
`docs/03_IMPLEMENTATION_PLAYBOOK.md`. Steps 0.1, 0.2, 0.3, and 0.5 are complete.
Step 0.4 is verifying with physical dual-display coverage still pending. A
documented owner-approved exception permits Phase 1 implementation to continue,
but it does not waive that manual test or the release gate. Step 1.1 application
composition and dependency injection and Step 1.2 durable/transient note
lifecycle are complete. Step 1.3 navigation, ordering, promotion, and confirmed
deletion is also complete. Step 1.4 global invocation, presentation and presence
modes, pin, auto-hide, focus restoration, and flush-first visibility transitions
is complete. Step 1.5 cross-note search, cancellable FTS pagination, keyboard
promotion, and VoiceOver result semantics is complete, satisfying the Alpha
implementation gate. Step 2.1 production editor projection is complete with
off-main cancellable parsing, diagnostics, per-note selection and scroll
restoration, and an accessibility decoration group. `MT-WIN-004C` remains
pending despite this progress and is still required before the 1.0 release
gate. Step 2.2 contextual copy, clean export, normalized and raw paste, five
independent paste settings, single-operation undo, and clipboard error handling
are also complete. Step 2.3 HTTP/HTTPS link projection is complete with
caret-exit shortening, stable duplicate identities and suffixes, source-free
manual expansion state, safe opening and exact copying, code-context
exclusions, and independent editor settings. Step 2.4 is complete with the
documented Markdown subset, source-only TextKit presentation, Command-slash
line comments, code-note and fenced-code language parsing, deterministic syntax
highlighting, code-context clipboard/link policies, and persistent default
language and theme settings. Step 2.5 is complete with a Command-Shift-F
find/replace panel, five source-only matching modes, independent case matching,
regex validation, field-specific keyboard commands, temporary link expansion,
and single-operation Replace All undo. Step 3.1 is complete with stable mode
IDs, versioned alias and main-alias settings, generic first-line header parsing,
conflict validation, a global keyword switch, and a source-free in-window slash
picker with filtering, numeric selection, VoiceOver state, and single-operation
insertion or replacement. Step 3.2 List Mode is complete with source-backed
gutter checkboxes, configurable trailing checked markers, pointer and keyboard
toggle parity, source-only Undo/Redo, math suppression, and independently
configured clean-copy marker omission. Changing the marker reparses
presentation without rewriting existing note source.
Step 3.3 Basic Math is complete with a frozen versioned grammar, checked Decimal
evaluation, documented operators and functions, period- and comma-decimal
profiles, stable source-free diagnostics, independently configurable result
digits and thousands grouping, accessible inline result copying, and exact
source-only SQLite/FTS persistence.

Step 0.1 uses XcodeGen 2.45.4 as the reproducible project generator. Bootstrap
downloads that exact release, verifies its SHA-256, generates the project, and
resolves Swift package dependencies:

```bash
scripts/bootstrap.sh
scripts/build.sh
scripts/test.sh
scripts/test-performance.sh
```

XcodeGen 2.46.0 was the current stable release when implementation began on
2026-08-03. The project intentionally remains pinned to the reviewed 2.45.4
baseline until a separate toolchain update validates a regenerated project.

## Documents

- `docs/00_SOURCE_LEDGER.md`: evidence from AntiNote's official material.
- `docs/01_PRODUCT_SPEC.md`: complete product behavior and state rules.
- `docs/02_ARCHITECTURE.md`: modules, data model, editor design, and security.
- `docs/03_IMPLEMENTATION_PLAYBOOK.md`: ordered implementation steps.
- `docs/04_TEST_MATRIX.md`: requirement-to-test traceability.
- `docs/05_AI_POLICY.md`: rules for using AI during development and in-product.
- `docs/06_MANUAL_WALKTHROUGH.md`: tab-by-tab manual coverage and release scope.
- `docs/ios/01_IOS_PRODUCT_DESIGN.md`: iPhone product and interaction decisions.
- `docs/ios/02_IOS_REQUIREMENTS.md`: iOS-specific functional requirements.
- `docs/ios/03_IOS_ARCHITECTURE.md`: iOS platform boundaries and feasibility gates.
- `docs/ios/04_IOS_TEST_MATRIX.md`: iOS requirement-to-test traceability.
- `docs/ios/05_IOS_IMPLEMENTATION_PLAYBOOK.md`: ordered iOS build and release plan.
- `docs/ios/traceability.yml`: machine-readable iOS requirement/test map.

The iOS set is an implementation-ready platform adaptation plan, not evidence
of AntiNote iOS parity. Work proceeds through its ordered spikes and release
gates; post-1.0 JavaScript extensions remain research only.

Validate the iOS document set with:

```bash
scripts/validate-ios-docs.rb
```

## Non-negotiable Rules

1. Every parity requirement must reference at least one `AN-*` evidence ID.
2. Every implementation task must reference one or more `FR-*` requirements.
3. Every `FR-*` requirement must have automated or explicitly documented manual
   verification.
4. Every official manual tab must map to a defined `FR-*` requirement or an
   explicit `FORNOW-DECISION-*` scope decision.
5. An undocumented AntiNote behavior is not a requirement. Record it as an
   open question and verify it before implementation.
6. Derived editor decorations must never become the source of truth for a note.
7. Core 1.0 must work without generative AI, an account, or a network
   connection.
