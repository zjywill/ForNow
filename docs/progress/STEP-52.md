# Step 5.2 - Expiration And Bulk Deletion

- Status: `DONE`
- Started: 2026-08-06
- Completed: 2026-08-06
- Evidence: `AN-LIFE-001`, `AN-LIFE-002`, `AN-NOTE-SET-001`
- Requirements: `FR-NOTE-005`, `FR-NOTE-006`, `FR-NOTE-010`
- Decision: `FORNOW-DECISION-018`
- Required tests: `UT-NOTE-006A` through `UT-NOTE-006E`, `IT-NOTE-006`,
  `UT-NOTE-010A` through `UT-NOTE-010F`, `IT-NOTE-010`, and
  `UIT-NOTE-010`

## Files Changed

- `docs/lifecycle/EXPIRATION_AND_BULK_DELETION_V1.md`
- `docs/decisions/ADR-009_EXPIRATION_AND_BULK_DELETION.md`
- `Packages/ForNowCore/Sources/ForNowCore/Dependencies.swift`
- `Packages/ForNowCore/Sources/ForNowCore/LifecycleSettings.swift`
- `Packages/ForNowCore/Sources/ForNowCore/NoteRetention.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/PersistenceNoteRepository.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/PersistenceStore.swift`
- `App/AppDelegate.swift`
- `App/AppEnvironment.swift`
- `App/BulkDeletionConfirmationCoordinator.swift`
- `App/LifecycleSettingsStore.swift`
- `App/NoteSessionModel.swift`
- `App/SettingsView.swift`
- `Tests/ForNowTests/AppEnvironmentTests.swift`
- `Tests/ForNowTests/NoteRetentionTests.swift`
- `Packages/ForNowPersistence/Tests/ForNowPersistenceTests/NoteRetentionPersistenceTests.swift`
- `UITests/ForNowUITests/LaunchTests.swift`
- `docs/00_SOURCE_LEDGER.md`
- `docs/01_PRODUCT_SPEC.md`
- `docs/traceability.yml`
- `README.md`

## Behavior Contract

- Lifecycle settings are version 2 and migrate version 1 to Never. Today,
  one week, one month, one year, and Never use the frozen local-calendar rules
  and persist an explicit absolute `expiresAt` for every finite policy.
- Meaningful source edits and promotions refresh `modifiedAt` and `expiresAt`.
  Selection, scrolling, navigation, projection, settings, and other
  metadata-only writes preserve both values.
- A policy change atomically gives existing durable notes a grace period from
  the later of their current modification time and the change time. Never
  clears every deadline.
- Expiration runs before launch-note selection, every minute, after wake, and
  after a wall-clock change. One transaction deletes Note, FTS, and linked
  Timer rows and returns only IDs actually removed.
- Bulk preview uses the strict `modifiedAt < cutoff` predicate and freezes a
  deterministic ID set. Confirmation flushes source, publishes a validated
  safety backup, and revalidates only that frozen set before one transactional
  deletion. Cancellation and backup failure perform no deletion.
- Successful deletion reconciles current Note, AutoPaste, Timer, SQLite, and
  FTS state. Settings shows the exact count, irreversible copy, cancel-first
  destructive confirmation, result, and recoverable error state.

## Automated Evidence

- `NoteRetentionTests` passes 16 of 16 calendar, settings migration,
  timestamp-preservation, policy-change, idempotency, preview, revalidation,
  cancellation, backup-failure, state-reconciliation, and AppKit alert tests.
- The complete main application suite passes 148 of 148 tests and the complete
  Editor Projection suite passes 273 of 273, with zero failures, expected
  failures, or skips. Persistence passes 21 of 21 plus the SIGKILL/WAL and
  interrupted-backup workers; Window passes 11 of 11; ForNowDesign passes 3 of
  3.
- Release Performance passes 3 of 3. A focused unbuffered replay measured
  `PT-EDIT-001` across 30 samples at `0.045709 ms` p50, `0.05225 ms` p95, and
  `0.066667 ms` worst. `PT-MATH-001` measured 10 samples at `45.911291 ms` p95
  and worst.
- Debug and Release unsigned builds, strict Swift formatting, generated-project
  comparison, iOS documentation validation, and `git diff --check` pass.
- Traceability generation, validation, and both fault injections pass with 65
  of 65 evidence entries, 69 of 69 requirements, 494 mapped test IDs, and 18
  decisions. `FORNOW-DECISION-018` controls `FR-NOTE-005`, `FR-NOTE-006`, and
  `FR-NOTE-010`.

## Real Application Evidence

- A current Debug application launched through LaunchServices with an isolated
  `HOME` and `CFFIXED_USER_HOME`. It created two durable Notes and a real
  running countdown linked to the Note containing `timer 10`.
- The visible Settings picker changed from Never to After one week. Version-2
  lifecycle settings persisted `noteExpirationChoice: oneWeek`, and both Notes
  received explicit `expires_at = 1786628637.226338` deadlines without changing
  their source or `modified_at` values.
- Command-bracket navigation committed selection metadata for both Notes while
  preserving exact lifecycle timestamps. The two `modified_at` values remained
  `1786023746.543523` and `1786023542.160308`; both `expires_at` values remained
  `1786628637.226338`.
- One Note was assigned a modification time before the current local day. The
  Settings preview showed `1 note match the selected cutoff.` and
  `This action cannot be undone.` Cancel was the native default button. After
  Cancel, the store remained 2 Notes, 2 FTS rows, 1 Timer, and zero backups.
- A second preview showed the same exact count. Confirming produced
  `Deleted 1 note; safety backup created.` The backup manifest reported schema
  2 and two Notes, and its database SHA-256
  `9903433d7e99f3be9db7bb45c90a949abee3661f84e4223660783d8fe8e7c8a8`
  matched the published SQLite file. The backup contained 2 Notes, 2 FTS rows,
  and the linked Timer, while the committed main store contained 1 Note, 1 FTS
  row, and zero Timers.
- Main-store and backup `PRAGMA integrity_check` and `PRAGMA quick_check`
  returned `ok`. Missing-FTS, orphan-FTS, and orphan-Timer queries all returned
  zero. The surviving source remained exactly `Current note metadata`.
- The 640-by-852-point Settings window contained the 83-by-24-point expiration
  picker, 141-by-24-point preview button, exact preview and irreversible labels,
  and 186-by-13-point completion label. Accessibility exposed the stable
  identifiers documented by `UIT-NOTE-010`.
- The survivor was then assigned an already elapsed explicit deadline. The next
  launch removed Note, FTS, and Timer state before selecting the launch page;
  a second launch remained at zero rows with both integrity checks still `ok`,
  proving real-process launch idempotency.
- The instance quit normally, the isolated preference domain and evidence
  directory were removed, no ForNow process remained, and the user's ordinary
  ForNow preferences were unchanged.

## Exit Criteria

- Clock changes do not double-delete: `PASS` in launch, repeated, rollback,
  forward-clock, wake/clock routing, and real repeated-launch evidence.
- Bulk-delete predicate has preview tests: `PASS` for strict cutoff equality,
  frozen membership, edited-member revalidation, the real exact count, and
  transactional confirmation.
- Cancellation leaves all notes unchanged: `PASS` in repository and
  environment tests plus the real 2-Note, 2-FTS, 1-Timer, zero-backup snapshot.
- Every Step 5.2 task is implemented: `PASS` in the frozen contract, accepted
  decision, mapped automated suites, real Settings interaction, validated
  backup-before-mutation, timer cascade, and SQLite/FTS inspection.

## Environment Limitation

- The host still has zero valid Apple Development signing identities.
  `scripts/test-ui.sh` therefore exits with its documented status 2 before
  launching the signed runner. Native AppKit integration tests and real-process
  Accessibility interaction cover Step 5.2 without claiming that the signed
  runner passed.

## Deferred Manual Evidence

Physical simultaneous dual-display coverage `MT-WIN-004C` remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
