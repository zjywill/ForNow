# ADR-008 - Quick Export Document And Destinations

- Status: `ACCEPTED`
- Date: 2026-08-06
- Step: 5.1
- Decision: `FORNOW-DECISION-017`
- Requirements: `FR-EXP-001`, `FR-EXP-002`, `FR-EXP-003`, `FR-EXP-004`

## Context

Public evidence establishes Command-S quick export, TXT, Markdown, ZIP,
Obsidian, Bear, Apple Notes through Shortcuts, keyword/title settings, and three
custom placeholders. It does not define the canonical model fields, whether
title extraction removes file content, atomic no-overwrite behavior, filename
normalization, application URL shapes, scheme allowlist, date format, or size
limits.

Letting adapters read editor presentation would leak decorations into exported
data. Hand-built query strings risk double encoding and parameter injection.
Writing directly to a selected file can leave partial data, and allowing an
arbitrary custom scheme would turn a note body into an unbounded external-action
surface.

## Decision

ForNow V1 builds one immutable `ExportDocument` from canonical source through
the existing clean projection. Title extraction retains the full cleaned text
for file-oriented destinations. Settings, filename rules, URL shapes, atomic
commit behavior, custom scheme allowlist, placeholder component rules, UTC date,
and 4 KiB/8 KiB limits are frozen in `docs/export/QUICK_EXPORT_V1.md`.

File and ZIP adapters write a sibling temporary item and commit it with an
explicit overwrite policy. Application and custom URL adapters use decoded
component values with `URLComponents`, check Launch Services availability, and
open only after validation and final-size checks. Command-S flushes the live
source, snapshots the current note, and routes to the configured adapter.

## Consequences

- Every destination is testable against the same source-derived document.
- First-line titles can name files and permanent notes without losing the first
  line from TXT, Markdown, ZIP, or Shortcut input.
- Default file operations cannot overwrite an existing item.
- Query delimiters and percent signs from note content cannot inject parameters
  or be double encoded.
- Custom templates intentionally support a finite set of note/productivity app
  schemes rather than arbitrary executables or web/file URLs.
- Missing applications and invalid configurations fail before any external
  action and can present specific recovery guidance.

## Acceptance Contract

This decision remains accepted only while Step 5.1 proves:

- canonical projection covers title, keyword, links, list triggers, Unicode,
  line endings, and exact source immutability;
- TXT, Markdown, and ZIP round-trip and leave no partial destination on failure;
- existing files require explicit replacement approval and unsafe titles remain
  valid, deterministic filenames;
- Obsidian, Bear, and Apple Shortcut adapters construct encoded-once URLs and
  unavailable destinations perform no open;
- every custom placeholder/component boundary, allowlist rule, compatibility
  transform, and size limit is covered;
- Command-S uses the configured destination and all failures preserve Note,
  SQLite, and FTS source.
