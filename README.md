# ForNow

ForNow is a native macOS temporary scratchpad inspired by the workflow category
demonstrated by AntiNote. It is a clean-room implementation: behavior may be
studied and independently reproduced, but source code, branding, copy, icons,
themes, screenshots, and proprietary assets must not be copied.

Product line: **Notes, for now.**

## Status

This repository currently contains the implementation plan and product
specification. Application code should not start until the three Phase 0
technical spikes in `docs/03_IMPLEMENTATION_PLAYBOOK.md` pass.

## Documents

- `docs/00_SOURCE_LEDGER.md`: evidence from AntiNote's official material.
- `docs/01_PRODUCT_SPEC.md`: complete product behavior and state rules.
- `docs/02_ARCHITECTURE.md`: modules, data model, editor design, and security.
- `docs/03_IMPLEMENTATION_PLAYBOOK.md`: ordered implementation steps.
- `docs/04_TEST_MATRIX.md`: requirement-to-test traceability.
- `docs/05_AI_POLICY.md`: rules for using AI during development and in-product.
- `docs/06_MANUAL_WALKTHROUGH.md`: tab-by-tab manual coverage and release scope.

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
