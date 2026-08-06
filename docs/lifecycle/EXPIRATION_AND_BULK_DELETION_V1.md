# Expiration And Bulk Deletion V1

- Status: `FROZEN`
- Step: 5.2
- Decision: `FORNOW-DECISION-018`
- Requirements: `FR-NOTE-005`, `FR-NOTE-006`, `FR-NOTE-010`

## 1. Expiration Choices

ForNow stores one global expiration choice in versioned lifecycle settings:

| Choice | Explicit `expiresAt` |
|---|---|
| Today | Start of the next local calendar day |
| One week | Seven local calendar days after the reference instant |
| One month | One local calendar month after the reference instant |
| One year | One local calendar year after the reference instant |
| Never | `nil` |

Calendar addition uses the user's autoupdating calendar and time zone. The
result is persisted as an absolute timestamp, so later time-zone or clock
changes do not reinterpret an existing deadline.

The reference instant is the source modification time for a new meaningful
note or source edit, and the promotion time for an intentional promotion.
Selection, scroll, projection, navigation, settings, and other metadata-only
saves preserve both `modifiedAt` and `expiresAt`.

Changing the global choice atomically rewrites every durable note. Existing
notes receive a new grace period whose reference is the later of their current
`modifiedAt` and the setting-change time. This prevents enabling a finite
policy from immediately deleting old notes. Choosing Never clears every
stored `expiresAt`. A transient blank note receives the current choice only
when its first meaningful source is committed.

## 2. Expiration Processing

Expiration deletes rows satisfying this exact predicate:

```text
expiresAt != nil AND expiresAt <= evaluationTime
```

The repository flushes pending canonical drafts, selects eligible IDs, and
removes Note, FTS, and linked Timer rows in one SQLite write transaction. It
returns the IDs actually deleted. Repeating a run at the same or later time
returns no already-deleted ID, so launch, scheduled, wake, and clock-change
runs are idempotent even when they overlap.

ForNow runs expiration before loading the launch note, once per minute while
the app is running, after system wake, and after a wall-clock change. A clock
rollback can delay a future deletion but cannot recreate a row or emit the
same deletion twice. When a running-session deletion removes the visible note,
ForNow loads the newest survivor or creates a transient blank note. AutoPaste
and in-memory Timer state stop when their destination is deleted.

## 3. Bulk Preview

The Settings date control resolves the selected date to the start of that
local calendar day. Repository callers may supply any exact cutoff instant.
Preview uses only this strict predicate:

```text
modifiedAt < cutoff
```

A note exactly equal to the cutoff is excluded. Preview returns the cutoff and
a unique, deterministic snapshot of eligible Note IDs. It does not mutate a
note or create a backup.

## 4. Confirmed Bulk Deletion

Confirmation is bound to the preview snapshot. Before deletion, ForNow flushes
pending canonical source and publishes a validated safety backup of the current
SQLite store. If backup publication fails, no Note, FTS, or Timer deletion is
attempted.

After the backup succeeds, one write transaction revalidates every previewed
ID and deletes only IDs that still satisfy `modifiedAt < cutoff`. Notes created
after preview are never added to that confirmation. Previewed notes edited to
the cutoff or later are skipped. The receipt reports previewed, deleted, and
skipped IDs plus the safety-backup timestamp and note count.

Cancellation clears the preview and performs no repository mutation. The UI
must show the exact preview count and the copy "This action cannot be undone."
before exposing the destructive confirmation command.

## 5. Failure And Recovery Rules

- Expiration and bulk deletion never rewrite canonical source.
- Note and FTS deletion share one transaction; partial membership is invalid.
- A successful safety backup may remain if the later delete transaction fails.
- Backup failure, confirmation cancellation, an empty preview, and a stale
  preview with no still-eligible IDs delete zero notes.
- Recovery from a confirmed permanent deletion is available only through the
  safety backup until a separately documented Trash feature exists.

## 6. Acceptance Mapping

- `UT-NOTE-006A` through `UT-NOTE-006E`: every calendar choice.
- `IT-NOTE-006`: explicit timestamps, launch/active processing, metadata
  preservation, idempotency, clock changes, FTS, and linked Timer cleanup.
- `UT-NOTE-010A` through `UT-NOTE-010F`: strict preview, cutoff equality,
  frozen membership, revalidation, cancellation, and backup failure.
- `IT-NOTE-010`: real SQLite safety backup, transactional delete, FTS parity,
  and backup recovery evidence.
- `UIT-NOTE-010`: exact count, irreversible copy, cancel-first confirmation,
  destructive action, success, and error states.
