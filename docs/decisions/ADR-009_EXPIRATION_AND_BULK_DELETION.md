# ADR-009 - Expiration And Bulk Deletion

- Status: `ACCEPTED`
- Date: 2026-08-06
- Step: 5.2
- Decision: `FORNOW-DECISION-018`
- Requirements: `FR-NOTE-005`, `FR-NOTE-006`, `FR-NOTE-010`

## Context

Public evidence establishes five expiration choices and bulk deletion by a
selected modification date, but it does not define calendar boundaries,
whether a settings change affects existing notes, the exact cutoff predicate,
or what happens when notes change between preview and confirmation. The product
requirements additionally require explicit timestamps, idempotency, a safety
backup, and zero deletion after cancellation or backup failure.

The current Note model already has `modifiedAt` and `expiresAt`, SQLite indexes
both columns, and the persistence layer can publish validated online backups.
Those primitives need one cross-layer contract; implementing lifecycle policy
only in Settings would otherwise race pending drafts, clear expiration during
metadata saves, or delete a different set than the user previewed.

## Decision

ForNow adopts the calendar, persistence, scheduling, preview, revalidation,
backup, receipt, and UI rules frozen in
`docs/lifecycle/EXPIRATION_AND_BULK_DELETION_V1.md`.

Every meaningful source mutation and promotion computes an explicit deadline.
Metadata-only writes preserve the existing modification and expiration values.
A policy change atomically gives all durable notes a new grace period from the
later of their modification time and the change time. Expiration runs through
an idempotent repository transaction at launch, every minute, wake, and clock
change.

Bulk preview freezes eligible IDs under `modifiedAt < cutoff`. Confirmation
flushes pending source, publishes a validated safety backup, then revalidates
only those IDs and deletes the still-eligible subset in one transaction. No
backup means no delete attempt. Cancellation is a UI-only state transition.

## Consequences

- Enabling expiration cannot immediately erase an old never-expiring note.
- Calendar month and year choices follow local civil time rather than fixed
  30-day or 365-day approximations.
- Selection and navigation can no longer keep notes alive by accidentally
  advancing `modifiedAt`.
- A visible preview is an upper bound on confirmation membership; concurrent
  edits may reduce the final count but cannot add unseen notes.
- Safety backups include the latest flushed canonical source and remain useful
  even if the subsequent transaction fails.
- Automatic expiration remains intentionally unconfirmed; explicit policy and
  deadline settings are the user's authorization.

## Acceptance Contract

This decision remains accepted only while Step 5.2 proves:

- all five choices compute and persist their frozen calendar result;
- launch, scheduled, wake, and clock-change processing cannot double-delete;
- source edits and promotions refresh deadlines while metadata saves preserve
  both lifecycle timestamps;
- preview and confirmation use the exact strict predicate and frozen membership;
- cancellation and backup failure delete zero notes;
- Note, FTS, linked Timer, AutoPaste, and visible-session state reconcile after
  every successful expiration or bulk deletion;
- the UI exposes an exact count, explicit irreversible copy, cancel-first
  confirmation, and recoverable failure state.
