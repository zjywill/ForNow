# ForNow OCR V1 Contract

- Contract ID: `fornow-ocr-v1`
- Decision: `FORNOW-DECISION-014`
- Evidence: `AN-OCR-001`, `AN-OCR-002`
- Requirements: `FR-OCR-001`, `FR-OCR-002`, `FR-OCR-003`

This contract freezes resource, language, cancellation, and asynchronous
insertion behavior that the public evidence leaves unspecified. It does not
claim undocumented AntiNote parity.

## Input And Validation

Image input takes precedence when one pasteboard item offers both image and text
representations. Paste captures the current editor selection. Drag/drop captures
the source position under the pointer without changing the current selection.

Accepted decoded formats are PNG, JPEG, and a GIF containing exactly one frame.
JPG and JPEG filename extensions both map to JPEG. AppKit commonly publishes a
copied bitmap as TIFF, so an in-memory TIFF clipboard representation is decoded
and re-encoded as PNG before validation. A TIFF file is not accepted.

Validation uses the ImageIO-reported type and first-frame dimensions rather than
trusting the filename extension or pasteboard declaration. Input is rejected
before recognition when it is empty, malformed, animated, unsupported, larger
than 20 MiB encoded, larger than 40,000,000 pixels, or has invalid dimensions.
Pixel-area calculation is overflow-safe. File size is checked before reading
when metadata is available and encoded size is checked again after reading.

A dropped file uses security-scoped access only for the read. ForNow creates no
OCR temporary file. Neither the original image nor a normalized clipboard image
is stored in a note, SQLite, FTS, UserDefaults, logs, or application attachments.

## Local Recognition

Production recognition uses Apple's local Vision framework with accurate text
recognition and language correction. It does not invoke an HTTP client or send
image data, note text, recognized text, confidence, or language settings.

The persistent language choices are:

- Automatic, the default, with Vision language detection;
- System Preferred, filtered to languages supported by the current request;
- English;
- Simplified Chinese;
- Traditional Chinese;
- Japanese;
- Korean;
- French;
- German;
- Spanish.

An explicitly selected language unavailable to the current Vision revision
produces a recoverable error. System Preferred falls back to Vision's supported
list when no preferred language matches.

## Request Ownership And Cancellation

There is at most one application OCR request. Starting a new request first
cancels the prior task. User cancellation, window close, and application
shutdown do the same. Cancellation is forwarded to `VNRequest.cancel()`.

Every request captures a monotonically increasing generation token. Completion,
failure, or cancellation from an older generation cannot change visible state
or insert text after a replacement request has started. Cancellation clears
progress without showing an error and never inserts a partial result.

## Source-Versioned Insertion

Before recognition, the editor captures its source snapshot version and a
validated UTF-16 replacement range. The image itself does not enter the editor
or Undo history.

When recognition finishes:

1. Empty or whitespace-only recognition produces a recoverable error and no
   source edit.
2. If the source version is unchanged, recognized plain text replaces the
   captured paste selection or inserts at the captured drop position.
3. If the source version changed, the original range is not reused. The app
   asks whether to insert at the current selection; cancellation discards the
   result.
4. If the editor is unavailable, the range is invalid, or IME marked text is
   active, insertion fails without editing source.

The final `NSTextView` insertion is bracketed by undo-coalescing boundaries and
forms exactly one Undo operation. Projection refresh, progress, confirmation,
errors, confidence metadata, and image data create no Undo entries and never
enter canonical source, SQLite, FTS, or clean copy.

## Presentation And Errors

Recognition exposes an indeterminate progress indicator, visible status text,
and an independently accessible cancel button. Malformed data, unsupported
format, animated GIF, resource limits, unavailable language, empty recognition,
and insertion failure use recoverable alerts. Dismissing an alert returns to the
editor without changing source.

## V1 Defaults

- language: Automatic;
- maximum encoded size: 20 MiB;
- maximum decoded pixel area: 40 megapixels;
- GIF policy: one frame only;
- concurrent recognition requests: one.
