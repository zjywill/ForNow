# ADR-010 - In-App Backup Management

- Status: `PROPOSED`
- Date: 2026-08-06
- Step: 5.3
- Decisions: `FORNOW-DECISION-001`, `FORNOW-DECISION-019`
- Requirements: `FR-BACK-001`, `FR-BACK-002`

## Context

ADR-003 proves the SQLite snapshot and rollback primitives, but an in-app
restore crosses additional live state: a pending editor draft can overwrite a
restored Note, a Timer can tick against the replaced store, and AutoPaste can
append to a destination whose identity changed. Public evidence also leaves
retention bounds, list size semantics, failure presentation, and recovery-log
privacy undefined.

## Decision

ForNow adopts the policy, scheduling, list, restore coordination, and recovery
report rules frozen in `docs/backup/BACKUP_MANAGEMENT_V1.md`.

The production application composes one persistence repository into both Note
and backup services. App-level operations commit and flush source before a due
or manual backup. Confirmed restore suspends runtime writers, creates an
emergency snapshot before target validation, performs the persistence restore,
and reloads Note and Timer state from the resulting store before writers resume.

Every confirmed restore attempt with a published emergency snapshot produces a
bounded metadata-only JSON report. Ordinary backup rows exclude emergency
snapshots but expose the exact published manifest, combined byte size, schema,
and Note count.

## Consequences

- Never disables scheduling without disabling manual safety operations.
- A corrupt restore target still leaves an emergency current-state snapshot.
- Restore cannot be followed by a delayed pre-restore editor or Timer write.
- Recovery artifacts are inspectable without leaking canonical source into
  logs or preferences.
- Report publication is part of restore completion; failure after replacement
  invokes the same emergency rollback path.

## Acceptance Contract

This decision can be accepted only after Step 5.3 proves:

- defaults, all ten frequencies, count and age retention, failure states, and
  both exact reveal targets;
- a backup list with date, combined byte size, schema, and Note count;
- manual and periodic backup after a successful source flush;
- cancel-first native confirmation and no operation after cancellation;
- emergency backup before every confirmed target validation and replacement;
- atomic restore, old-schema migration, injected rollback, Note/FTS identity,
  and runtime Note/Timer/AutoPaste reconciliation;
- atomically published reports whose serialized bytes contain no Note body;
- the full real-app destructive restore rehearsal without Finder replacement.
