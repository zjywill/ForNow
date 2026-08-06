# ADR-007 - Appearance And Settings Presentation

- Status: `ACCEPTED`
- Date: 2026-08-06
- Step: 4.4
- Decision: `FORNOW-DECISION-016`
- Requirements: `FR-UI-001`, `FR-UI-002`, `FR-UI-003`, `FR-EDIT-007`,
  `FR-NOTE-009`

## Context

Public evidence defines independent light and dark themes, five paper styles,
three paper visibility levels, text sizes, remappable quick actions,
translucency, and a layout-direction override. It does not define semantic
token names, exact built-in colors, contrast thresholds, material fallback,
how paper follows scrolling, how RTL checklist controls avoid text, or how
independently stored global and in-app shortcuts recover from a conflict.

Persisting presentation attributes in note text would corrupt search, clean
copy, and future theme changes. Treating material as the baseline would reduce
legibility on older systems and when Reduce Transparency is enabled. Trusting
each shortcut payload independently could leave the global invocation occupied
after startup.

## Decision

ForNow V1 uses four built-in semantic themes and an opaque-first presentation.
Theme, paper, typography, material, accessibility, direction, and quick-action
rules are frozen in `docs/appearance/APPEARANCE_V1.md`. Text and controls meet
a 4.5 contrast threshold. Native material is an optional macOS 15+ layer with
solid and high-contrast fallbacks.

Appearance, spacing, and direction remain source-free TextKit/AppKit
presentation. Natural RTL list items mirror their controls to the right gutter.
All settings are versioned and rollback published state after a failed write.
Quick-action drafts share one validator with save, global-shortcut replacement,
and startup reconciliation; the registered global invocation has priority over
an invalid in-app binding.

## Consequences

- Light and dark selections can evolve independently without view-specific
  color branches.
- Paper and type changes redraw in place without parsing or persisting source.
- Reduce Transparency always produces a solid readable editor.
- A mismatched theme can still be previewed, but translucent mode requires an
  explicit warning confirmation.
- RTL source and selection coordinates remain unchanged while controls mirror
  visually.
- Invalid or externally inconsistent shortcut state cannot displace the global
  invocation and never partially replaces the active quick-action map.

## Acceptance Contract

This decision remains accepted only while Step 4.4 proves:

- every built-in theme passes all defined contrast pairs;
- all five paper styles produce distinct pixels and list spacing follows the
  selected paper family;
- XS through XL, double size, Command-plus/minus, and natural/LTR/RTL changes
  preserve exact source and create no Undo entry;
- macOS 14 fallback, macOS 15+ material, 0 through 90 opacity, mismatch
  confirmation, Reduce Transparency, and Increase Contrast policies pass;
- the supported Settings width contains the longest labels and controls;
- invalid quick-action drafts preserve the active binding and global invocation;
- real application and SQLite/FTS evidence contain canonical note source only.
