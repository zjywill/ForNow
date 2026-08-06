# ADR-006 - AutoPaste Session And Capture Semantics

- Status: `ACCEPTED`
- Date: 2026-08-06
- Step: 4.3
- Decision: `FORNOW-DECISION-015`
- Requirements: `FR-AUTO-001`, `FR-AUTO-002`, `FR-AUTO-003`

## Context

The public evidence defines an explicit `paste` command, visible active state,
clipboard appending, configurable delimiters, and three user stop actions. It
does not define whether existing pasteboard content is captured, whether note
navigation retargets the session, how application-owned copies are suppressed,
how much duplicate history is retained, how IME composition interacts with an
append, or what happens when the destination disappears.

Polling outside an explicit session would violate the product privacy boundary.
Retaining clipboard bodies for deduplication would create unnecessary sensitive
history. Retargeting after navigation could send clipboard content to a note the
user did not select when starting the session.

## Decision

ForNow V1 uses one application-wide, explicitly started AutoPaste session. The
session snapshots a fixed destination note ID and capture policy. Monitoring
records the current pasteboard change count as a baseline, reads only string
content on later changes, processes captures sequentially, and stops if the
destination is deleted or unavailable. Navigation never retargets it.

Deduplication retains a 64-entry FIFO set of SHA-256 hashes of normalized text
plus the last change count, never clipboard bodies. Application-owned copies
register a bounded final change count and are consumed by the monitor. Current
destination appends wait for IME marked text to clear. Every accepted append is
flushed as canonical note source before processing the next event.

Session formatting, command grammar, normalization, UI, stop paths, and privacy
rules are frozen in `docs/autopaste/AUTOPASTE_V1.md`.

## Consequences

- Text present before session start is never captured.
- An active indicator always names the original target, even after navigation.
- Changing AutoPaste settings does not mutate an active session.
- Duplicate detection is bounded rather than permanent; a hash may be accepted
  again after it leaves the 64-item window.
- Clipboard text exists transiently only while queued for an accepted append.
- Startup and inactive state create no polling timer.
- A missing destination stops the session instead of recreating a note.

## Acceptance Contract

This decision remains accepted only while Step 4.3 proves:

- all explicit and lifecycle stop paths invalidate observation immediately;
- inactive monitoring performs zero polling and stores no callback;
- 1,000 application-layer events create the expected distinct canonical note
  lines with no duplicate or application-owned-copy loop;
- the 10,000-event hash soak remains bounded;
- fixed-target navigation, destination deletion, IME deferral, and settings
  persistence are covered;
- real application evidence confirms source-only SQLite and FTS persistence.
