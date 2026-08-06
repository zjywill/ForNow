# ADR-005 - OCR Input And Insertion Semantics

- Status: `ACCEPTED`
- Date: 2026-08-06
- Step: 4.2
- Decision: `FORNOW-DECISION-014`
- Requirements: `FR-OCR-001`, `FR-OCR-002`, `FR-OCR-003`

## Context

The public OCR evidence defines paste/drop image capture, local processing, and
PNG, JPEG, and static GIF support. It does not define resource limits, AppKit's
TIFF clipboard representation, language defaults, overlapping requests, or the
correct destination when note source changes during asynchronous recognition.

Trusting a filename or type declaration can bypass format validation. Reusing a
captured range after source mutation can replace unrelated UTF-16 content.
Allowing old requests to finish after cancellation can insert stale text.

## Decision

ForNow treats OCR images as bounded transient input. ImageIO validates the real
format, frame count, dimensions, 20 MiB encoded-size limit, and 40 megapixel
area limit before Vision runs. Clipboard TIFF may be normalized in memory to
PNG; TIFF files and other decoded types remain unsupported.

One main-actor workflow owns request generation, progress, settings, and final
insertion. Vision recognition is local, accurate, language-corrected, and
cancellable. A newer request invalidates the older generation. The editor
captures a source version plus UTF-16 selection or drop range. Unchanged source
uses that range; changed source requires confirmation before inserting at the
current selection. The final recognized plain text is one undoable source edit.

The complete behavior is frozen in `docs/ocr/OCR_V1.md`.

## Consequences

- Malformed, misleading, animated, and excessive inputs fail before Vision.
- Images remain outside note persistence, FTS, clean copy, and Undo history.
- Cancellation cannot race a late insertion from an obsolete request.
- A source edit or note navigation cannot cause OCR to reuse an old range.
- Clipboard TIFF interoperability does not expand the supported file contract.
- Explicit language choices remain testable and versioned.

## Acceptance Contract

This decision remains accepted only while Step 4.2 proves:

- PNG, JPEG, and static GIF pass while animated GIF, TIFF file, malformed data,
  encoded-size, and pixel-area violations fail recoverably;
- paste and Finder drag/drop capture the correct UTF-16 source range;
- Vision fixtures cover English, CJK, mixed content, rotation, low contrast,
  empty content, language persistence, and cancellation;
- stale source requires current-selection confirmation and one Undo restores
  the complete pre-insertion source;
- process-level monitoring observes no OCR network connection;
- SQLite and FTS contain recognized plain text only.
