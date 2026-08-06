# ADR-003 - Persistence And Backup Integrity

- Status: `ACCEPTED`
- Date: 2026-08-03
- Step: 0.5
- Requirements: `FR-NOTE-001`, `FR-NOTE-004`, `FR-NOTE-007`,
  `FR-BACK-001`, `FR-BACK-002`

## Context

ForNow must keep the last explicitly flushed edit after abrupt termination,
assign stable note identity and working order under concurrent promotion, keep
search rows transactional with notes, and restore a validated backup without
risking the current store. SQLite WAL and FTS5 each add an integrity detail:
backup files must not depend on unpublished sidecars, and a pool reader may
hold a snapshot older than the latest writer commit.

## Decision

`PersistenceStore` is an actor around one GRDB `DatabasePool`. It enables WAL,
foreign keys, and a bounded busy timeout. Note and FTS mutations share one
write transaction. A metadata-backed 64-bit sequence assigns monotonic,
unique order keys even when modification timestamps tie or promotions arrive
concurrently. A forward-only v2 migration adds `source_revision`.

FTS5 with `unicode61` handles ordinary token queries. Because that tokenizer
does not provide deterministic substring matching inside every unsegmented CJK
run, queries containing a CJK scalar use a parameterized, literal
`instr(body, query)` scan ordered by the same working order. This is a
correctness fallback; a future tokenizer may replace it only if its fixtures
retain the same deterministic results.

Integrity checks execute on the pool's writer connection. They run SQLite
`quick_check` and compare note, missing-FTS, and orphaned-FTS counts in the
latest committed WAL view. Using an arbitrary reader here is rejected because
an existing reader snapshot can report a false divergence while a transaction
has already committed.

Online backups are copied to hidden temporary files, converted to
`journal_mode=DELETE`, reopened read-only, integrity checked, and checksummed.
The manifest records schema version, database SHA-256, canonical note SHA-256,
and note count. The database is moved first and the manifest last, making the
manifest the publication marker. Store startup removes interrupted hidden
`.tmp` files.

Restore validates the manifest and source database before replacement, creates
an emergency backup of the current store, closes the pool, replaces the
database, migrates forward, and verifies note identity. Any post-replacement
failure restores and verifies the emergency copy before returning an error.

## Acceptance Contract

This decision remains accepted only while the Step 0.5 gate proves:

- an explicitly flushed edit survives a real `SIGKILL` and WAL reopen;
- an interrupted backup publishes no manifest and startup removes its temp
  file;
- a failed save remains exportable from memory;
- note order remains unique through concurrent promotions;
- ASCII and CJK search return deterministic results;
- a corrupt backup cannot replace the current store;
- restoring v1 migrates to v2 with note/FTS parity intact;
- an injected post-replacement failure restores the pre-restore store.
