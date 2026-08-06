# ADR-001 - Editor Decoration Rendering

- Status: `ACCEPTED`
- Date: 2026-08-03
- Step: 0.3
- Requirements: `FR-EDIT-001`, `FR-EDIT-002`, `FR-EDIT-004`,
  `FR-EDIT-005`, `FR-EDIT-006`

## Context

ForNow must keep `Note.body` as understandable source text while presenting
interactive checkboxes, shortened links, calculation results, diagnostics, and
timers. Source selection, marked text, undo, copy, and accessibility must remain
in source UTF-16 coordinates at the AppKit boundary.

## Options

### Attachment-backed rendering

Rejected. Text attachments enter attributed text storage, introduce replacement
characters into the layout model, and make it too easy for rendered controls to
leak into source, selection, copy, and persistence paths.

### Custom TextKit layout fragments

Deferred for cases an overlay cannot express. A custom fragment can alter line
geometry precisely, but it couples every decoration to TextKit layout internals
and still needs a separate accessibility and pointer surface. It adds risk
before the simpler coordinate-preserving strategy is exhausted.

### Overlay adornments anchored to TextKit 2 source ranges

Accepted. The `NSTextView` text storage contains source only. Semantic AppKit
controls are positioned from source ranges after layout. A link overlay yields
to the source whenever selection or the insertion point enters its range.
Results anchor at a zero-length source offset. Checkbox activation performs one
ordinary source replacement and one undo group.

## Decision Contract

Accept the overlay strategy only if the Step 0.3 test and fixture gate passes:

- result, link, and control labels never enter source or attributed storage;
- all mandatory Unicode, marked-text, selection, copy, and edit fixtures pass;
- stale projections are rejected by source version;
- 500 randomized edits preserve source/range invariants;
- native undo/redo remains source-based;
- screenshot review shows stable positioning without overlap.

If production profiling exposes a decoration that genuinely changes line
height or wraps independently, that decoration may use a custom layout fragment
behind the same immutable `EditorProjection` contract. Attachments remain
forbidden as a source-of-truth mechanism.
