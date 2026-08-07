# Backup Management V1

- Status: `FROZEN`
- Step: 5.3
- Decisions: `FORNOW-DECISION-001`, `FORNOW-DECISION-019`
- Requirements: `FR-BACK-001`, `FR-BACK-002`

## 1. Policy And Scheduling

Backup settings are versioned independently from Note source. The default is
every three hours, twelve retained copies, and a maximum age of thirty days.
The frequency choices are 10 minutes, 30 minutes, 1 hour, 3 hours, 12 hours,
1 day, 3 days, 1 week, 1 month, and Never. Retained copies are bounded to
1 through 100 and maximum age is bounded to 1 through 3,650 days.

ForNow checks eligibility after startup, once per minute while running, after
wake, and after a wall-clock change. Never disables only automatic creation;
manual backup and guarded restore remain available. A due automatic backup
first commits the live editor and flushes pending repository writes. Backup,
retention, bulk deletion, expiration, migration, and restore operations are
serialized by the repository and by one application-level operation guard.

Changing retention applies the new count and age bounds immediately. A backup
is published only after its SQLite image and manifest are complete and valid.
The manifest is the publication marker. Failure leaves no listable partial
backup and remains visible as a recoverable Settings error.

## 2. Folders And Backup List

Settings has separate Reveal Notes Folder and Reveal Backups Folder commands.
The notes folder is the parent directory of the live SQLite file; the backups
folder is the repository backup directory. Reveal creates no substitute copy
and never exposes canonical source inside preferences or logs.

The ordinary backup list contains published `backup-*.json` manifests only.
Each row shows its creation date, the combined SQLite-plus-manifest byte size,
schema version, and Note count. Emergency restore backups remain ordinary local
SQLite artifacts in the same folder, but are excluded from the ordinary list
to prevent accidental selection. Recovery reports identify them by filename.

Manual backup first commits and flushes live source, creates one validated
snapshot under the active retention policy, refreshes the list, and reports
failure without changing Note, FTS, Timer, or AutoPaste state.

## 3. Guarded Restore

Restore is available only from a listed manifest. The native confirmation is
cancel-first and states that current notes will be replaced and an emergency
copy will be created. Cancellation performs no repository operation.

Every confirmed restore attempt creates and publishes an emergency snapshot of
the current state before validating or replacing the requested backup. This
also preserves the current state when the requested manifest is corrupt or
unsupported. After that snapshot exists, ForNow validates manifest format,
schema, SQLite integrity, database checksum, canonical Note checksum, and Note
count before replacement.

Before the operation, ForNow commits the current editor, flushes pending saves,
dismisses searches and commands, stops AutoPaste, and suspends Timer ticking and
notifications. A valid target replaces the closed SQLite store atomically,
migrates forward, and passes database, Note, FTS, and canonical identity checks.
The visible Note and Timer are then reloaded from the resulting store; no stale
pre-restore draft or timer may write back afterward.

If replacement or post-replacement verification fails, the same operation
restores and verifies the emergency snapshot before returning failure. If the
target is rejected before replacement, the current store remains open and is
not needlessly replaced. In both cases the application reloads runtime state
from the verified current store.

## 4. Recovery Report

Every confirmed attempt that successfully creates its emergency snapshot
writes a version-1 JSON recovery report into the backups folder. The report
contains only operation ID, timestamps, requested and emergency manifest
filenames, requested schema and Note count when known, outcome, and a bounded
failure code. Outcomes are `restored`, `rejected`, `rolledBack`, and
`rollbackFailed`.

Reports never contain Note bodies, titles derived from source, selected text,
search terms, editor state, file contents, or unrestricted error descriptions.
A successful restore is not reported as complete until its `restored` report
is atomically published. If that publication fails after replacement, the
operation rolls back to the emergency snapshot.

## 5. Acceptance Mapping

- `IT-BACK-001A`: online SQLite snapshot and manifest validation.
- `IT-BACK-001B`: all frequency choices and exact eligibility boundaries.
- `IT-BACK-001C`: count retention.
- `IT-BACK-001D`: age retention.
- `IT-BACK-001E`: interrupted publication and startup cleanup.
- `IT-BACK-001F`: exact Notes and Backups reveal targets.
- `IT-BACK-001G`: backup, writes, migration, and restore serialization.
- `IT-BACK-001H`: database and canonical Note checksums.
- `IT-BACK-001I`: self-contained backup without WAL or SHM dependency.
- `IT-BACK-001J`: versioned policy persistence and immediate retention.
- `IT-BACK-001K`: manual and automatic failure visibility with no mutation.
- `IT-BACK-001L`: Note/FTS integrity divergence detection.
- `SOAK-BACK-001`: repeated creation across count and age rollover.
- `IT-BACK-002A`: invalid target rejection after emergency snapshot.
- `IT-BACK-002B`: emergency current-state snapshot before replacement.
- `IT-BACK-002C`: atomic replacement and exact IDs, bodies, and order.
- `IT-BACK-002D`: older schema migration.
- `IT-BACK-002E`: injected post-replacement rollback.
- `IT-BACK-002F`: settings compatibility and runtime Note/Timer reload.
- `IT-BACK-002G`: checksum and integrity validation before replacement.
- `IT-BACK-002H`: restored FTS identity and search behavior.
- `MT-BACK-002`: real-app destructive rehearsal, emergency artifact, recovery
  report privacy inspection, and zero Finder replacement.
