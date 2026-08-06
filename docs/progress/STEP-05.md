# Step 0.5 - Persistence And Backup Spike

- Status: `DONE`
- Started: 2026-08-03
- Completed: 2026-08-03
- Evidence reviewed: `AN-POS-002`, `AN-NAV-005`, `AN-BACK-001`
- Requirements: `FR-NOTE-001`, `FR-NOTE-004`, `FR-NOTE-007`,
  `FR-BACK-001`, `FR-BACK-002`
- Tests: `IT-NOTE-001`, `IT-NOTE-004A`, `IT-NOTE-004B`, `IT-NOTE-007`,
  `IT-BACK-001A` through `IT-BACK-001E`, `IT-BACK-001G` through
  `IT-BACK-001I`, `IT-BACK-001L`, `IT-BACK-002A` through `IT-BACK-002H`,
  `FAULT-DB-001` through `FAULT-DB-003`

## Files Changed

- `Packages/ForNowCore/Sources/ForNowCore/Note.swift`
- `Packages/ForNowPersistence/`
- `docs/02_ARCHITECTURE.md`
- `docs/decisions/ADR-003_PERSISTENCE_AND_BACKUP.md`
- `scripts/test-persistence-spike.sh`

## Commands Run

```bash
scripts/test-persistence-spike.sh
swift test --package-path Packages/ForNowPersistence
swift build --package-path Packages/ForNowPersistence \
  --product PersistenceCrashWorker
scripts/format.sh --fix
scripts/format.sh
scripts/test-editor-projection.sh
scripts/test-window-spike.sh
scripts/test-traceability.sh
scripts/check-generated-project.sh
scripts/test.sh
git diff --check
```

## Automated Test Results

- `PersistenceSpikeTests`: 15 passed, 0 failed, 0 skipped.
- Stable UUID CRUD, source revision, deletion, ASCII FTS, and literal CJK
  search passed.
- 120 concurrent promotions retained 12 unique order keys and advanced the
  monotonic sequence by at least 120.
- A 250 ms debounced saver retained only its latest generation; an injected
  disk-full write kept the unsaved draft exportable and retryable in memory.
- All ten documented backup frequencies, exact eligibility boundaries, and
  count/age retention passed.
- Online copies reopened without WAL sidecars and matched database and
  canonical-note SHA-256 manifests.
- A real worker was killed with `SIGKILL` after flushing a mixed English/CJK
  body. A new process reopened the WAL database and returned the exact body.
- A second worker was killed after the online backup copy and before manifest
  publication. The hidden temp file existed after the kill, no manifest was
  published, and opening the store removed the temp file.
- Corrupt backup rejection, a 100-note restore rehearsal, emergency rollback,
  v1-to-v2 restore migration, and explicit FTS divergence detection passed.

## Manual Test Results

- This spike has no GUI interaction matrix. Its destructive process and backup
  paths were exercised by the command-line fault gate above.
- The automated 100-note rehearsal verifies the data contract associated with
  `MT-BACK-002`; it is not recorded as a manual pass. The human release
  rehearsal remains part of the later backup-and-recovery phase.

## Deviations And Open Questions

- FTS5 `unicode61` does not guarantee substring matching within every
  unsegmented CJK run. Queries containing CJK scalars therefore use a
  parameterized literal scan. ADR-003 records the replacement contract for a
  future tokenizer.
- Integrity checks run through the pool's writer connection. A reader may hold
  a pre-commit WAL snapshot and can otherwise report a false note/FTS mismatch.
- `SOAK-BACK-001`, `IT-BACK-001F`, `IT-BACK-001J`, and `IT-BACK-001K` belong
  to later settings and release integration; this spike does not claim them.
