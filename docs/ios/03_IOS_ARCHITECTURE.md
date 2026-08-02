# ForNow iOS Technical Architecture

Implements `02_IOS_REQUIREMENTS.md`. Shares the baseline rules of
`../02_ARCHITECTURE.md` (Swift 6 concurrency, error handling, privacy,
package discipline); only iOS-specific decisions are recorded here.

## 1. Baseline

- Deployment target: iOS 17.0.
- Device family: iPhone only for 1.0 (`TARGETED_DEVICE_FAMILY = 1`).
- iOS 18-only features (Control Center control) are availability-gated and
  never required for core flows.
- Toolchain: Swift 6 language mode; XcodeGen-generated project from
  `project.ios.yml`, with no manually added files after generation.
- Placeholder identifiers are supplied through checked-in `.xcconfig`
  templates and local signing configuration:
  - app: `com.<organization>.ForNow`;
  - share extension: `com.<organization>.ForNow.Share`;
  - widgets: `com.<organization>.ForNow.Widgets`;
  - App Group: `group.com.<organization>.ForNow`;
  - CloudKit container: `iCloud.com.<organization>.ForNow`.
- Targets:

| Target | Kind | Purpose |
|---|---|---|
| `ForNowIOS` | app | editor, modes, settings, search, export |
| `ForNowShareExtension` | share extension | stage shared content into the inbox |
| `ForNowWidgets` | widget extension | capture widgets, Control (iOS 18+), timer Live Activity |
| `ForNowIOSTests` / `ForNowIOSUITests` | test bundles | unit and UI tests |

- Entitlements: App Groups for app, share extension, and widgets; iCloud and
  CloudKit for the app; Live Activities for the app/widgets target.
  Keychain Sharing, when needed, uses a separate Keychain Access Group
  entitlement and is never described as an App Group.
- No remote-notification background mode is required for iOS 1.0. Live
  Activities are read-only and update from app execution opportunities.
- Each shipping target includes the required privacy manifest and purpose
  strings. The release checklist re-audits required-reason APIs against the
  submission SDK.
- File protection: the App Group container uses
  `NSFileProtectionCompleteUntilFirstUserAuthentication` so Lock Screen
  capture works after first unlock while keeping the store encrypted at
  rest.

## 2. Package Platform Map

| Package | macOS | iOS | Notes |
|---|---|---|---|
| `ForNowCore` | yes | yes | unchanged; add `iOS(.v17)` to platforms |
| `ForNowModes` | yes | yes | unchanged |
| `ForNowDesign` | yes | yes | iOS variant adds Dynamic Type scaling |
| `ForNowPersistence` | yes | yes | same schema; container path injected per platform |
| `ForNowIntegrations` | yes | yes | protocol implementations differ per platform |
| `ForNowEditor` | yes | no | AppKit only |
| `ForNowWindowing` | yes | no | AppKit only |
| `ForNowEditorIOS` | no | yes | `UITextView` projection host |
| `ForNowCapture` | no | yes | App Intents, widgets, share staging, Spotlight |

Package manifests use conditional compilation only at platform
boundaries; no `#if os(iOS)` inside `ForNowCore` or `ForNowModes`.

## 3. App Group Data Protocol

Container layout:

```text
group.com.<organization>.ForNow/
├── store/notes.sqlite3          # opened only by the app process
├── inbox/<uuid>.json            # staged payload descriptor
├── inbox/<uuid>.bin             # optional binary payload (image)
└── snapshots/
    ├── widget-v1.json           # bounded widget/timer presentation
    └── share-target-v1.json     # current note ID only
```

### Inbox payload descriptor (versioned)

```json
{
  "version": 1,
  "id": "UUID",
  "createdAt": "ISO-8601",
  "kind": "text | url | image",
  "target": {
    "kind": "existingNote | newNote",
    "noteID": "UUID when kind is existingNote"
  },
  "text": "optional inline text",
  "payloadFile": "optional <uuid>.bin",
  "normalizationPolicyVersion": 1
}
```

Import rules:

- The share extension writes the descriptor and payload atomically
  (write-temp-then-rename) and posts a Darwin notification; it never
  opens the database.
- The app imports on activation: parse, validate, apply through the same
  use cases as UI commands, then delete the staged files.
- Import order is stable by `(createdAt, id)`.
- Import is idempotent by payload UUID. The application transaction inserts an
  `ingested_payload` receipt beside the note mutation; a crash between commit
  and file deletion re-processes as a no-op.
- An `existingNote` target is validated by stable ID. If the note was deleted
  or expired, the app creates a new note and records the fallback in the
  user-visible import result.
- Malformed payloads are quarantined to `inbox/quarantine/` with a
  diagnostic entry (no user content in logs).

### Widget snapshot

- Written atomically by the app after note-list-relevant mutations.
- `widget-v1.json` contains only the exact fields rendered: note count and
  active timer summary. Note previews are excluded from Lock Screen widgets in
  1.0.
- `share-target-v1.json` contains schema version, stable current note ID, and
  generated-at time; it contains no title or body.
- Widgets read only this file. Schema versioned as `widget-v1`; unknown
  versions render a neutral placeholder.

## 4. App Intents Contract

One versioned command surface mirrors the macOS URL router discipline
(`FR-URL-001`): strict decoding, bounded payloads, idempotency IDs for external
mutations, and no mutation on invalid input.

- `CaptureNoteIntent(content: String?)` - creates note (or transient
  blank) through the app command router and opens the app into the ready state
  of `FR-IOS-CAP-001`. The iOS 17 implementation uses the supported
  open-app intent behavior; newer SDK execution-mode APIs are availability
  gated.
- `AppendToNoteIntent(content: String, target: existing(noteID) | new)` -
  ingests through the normalization pipeline; callable from Shortcuts without
  opening the app (returns receipt, app applies on next activation via the
  inbox mechanism).
- iOS 1.0 exposes no background `SearchNotesIntent`; in-app search and optional
  Core Spotlight cover search without creating a second note-content read
  model in an extension process.
- iOS 1.0 exposes no mutating Live Activity intent. The activity deep link
  opens the app at the timer, where commands route to `TimerStateMachine`.
- Home Screen quick actions, widgets, App Shortcuts, and iOS 18 Controls decode
  into the same `CaptureRequest` model before routing.

Limits: text payloads capped at 200 KB, image payloads at 25 MB decoded
area per the OCR limits in `../02_ARCHITECTURE.md` section 10.
No App Entity exposes a note body in iOS 1.0.

## 5. Editor Architecture

`ForNowEditorIOS` mirrors the macOS editor contract
(`../02_ARCHITECTURE.md` section 6):

- `UITextView` + TextKit 2, hosted in SwiftUI via `UIViewRepresentable`.
- Same `SourceSnapshot` / `EditorProjection` / `EditorDecoration` types
  from the shared packages; decoration rendering strategy is decided by
  the iOS editor spike below, not assumed from the macOS choice.
- Slash picker is an input-accessory suggestion strip driven by the same
  slash catalog from `ForNowModes`.
- Hardware keyboard: an iOS-specific `UIKeyCommand` table generated from the
  canonical command registry; conflicts with system gestures resolve in favor
  of the system and are documented.
- Note paging uses a pan coordinator outside `UITextView` selection handling.
  Initial tuning values are 12 pt intent hysteresis, horizontal dominance
  `abs(dx) >= 1.5 * abs(dy)`, and commit when projected travel exceeds
  35 percent of width or horizontal release velocity exceeds 700 pt/s.
  These values are configuration constants and must pass the gesture matrix
  before freeze.

### iOS Editor Spike (iOS Step 0 gate)

Build before any mode work:

1. `UITextView` with source versioning.
2. One fake result decoration, one shortened link, one tappable checkbox.
3. Candidate renderings under evaluation: overlay adornments vs TextKit 2
   layout-fragment attributes vs attachment-backed views.
4. Mandatory fixtures identical to macOS Step 0.3 (ASCII, Chinese, Emoji,
   composed accents, multiline selection, duplicate URL, marked text,
   edit before/inside/after decoration).
5. Decision recorded in `docs/progress/` before iOS Step 1 starts.

Failure conditions and invariants match macOS Step 0.3 verbatim.

The selected renderer must also pass Dynamic Type through accessibility sizes,
VoiceOver rotor navigation, Reduce Motion, right-to-left layout, and an iPhone
split-view-style narrow width used by previews and multitasking tests.

## 6. Live Activity Model

```swift
struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: TimerPhase
        var state: TimerState
        var startedAt: Date?
        var endsAt: Date?
        var accumulatedSeconds: Double
    }
    var timerID: UUID
    var kind: TimerKind
    var title: String?
}
```

Rules:

- Registration, update, and end are driven by `TimerStateMachine`
  transitions only; no independent UI writes.
- Countdown displays use `endsAt` with system timer text (no per-second
  pushes); state changes (pause/resume/stop) trigger discrete updates.
- iOS 1.0 activities contain no mutation buttons. Tapping opens
  `fornow://timer/<timerID>`, which validates the ID and presents the timer in
  the app.
- Countdown activities set `staleDate = endsAt`. Completion schedules a local
  notification when the timer starts. Ending the activity is best-effort on
  foreground/background execution and is reconciled on launch.
- The UI must not imply that a stale activity is still running after `endsAt`;
  system timer text and stale presentation are timestamp-derived.

## 7. Spotlight Indexing

- `CSSearchableItem` per note: `identifier = noteID`,
  `title = first line (bounded)`, `contentDescription = body excerpt`,
  `contentModificationDate`.
- Indexing is disabled until the user opts in. Enabling it enqueues a full
  rebuild; disabling it deletes the ForNow domain and clears pending work.
- The SQLite transaction writes `spotlight_outbox(sequence, note_id,
  operation, note_revision, enqueued_at)`. A serial worker coalesces entries,
  calls Core Spotlight asynchronously, and deletes only acknowledged rows.
- Save enqueues upsert; delete, expire, and bulk-delete enqueue removal.
  FTS and the outbox update in the SQLite transaction. Core Spotlight does
  not.
- Expired and blank-transient notes are never indexed.
- A reconciliation pass on launch and after opt-in changes repairs differences
  between the note store and ForNow's searchable domain.

## 8. Clipboard Banner Mechanics

- The app stores the last observed `UIPasteboard.general.changeCount` on
  resignation and may use only that integer to decide whether to show the
  paste banner.
- The banner embeds `UIPasteControl` configured for text and URLs. ForNow does
  not call `string`, `strings`, `hasStrings`, or pattern-detection APIs before
  the user's action.
- The system-delivered payload passes through the `FR-CLIP-003` pipeline and
  is suppressed when equivalent ingestion just ran or the banner was
  dismissed for the same `changeCount`.

## 9. CloudKit Sync

iOS 1.0 uses `CKSyncEngine` with the user's private CloudKit database and one
custom record zone. The app has no ForNow account service.

Synced note fields:

```text
noteID, body, createdAt, contentRevision, contentClock,
promotedAt, promotionClock, expirationPolicy, expirationClock,
deletedAt, deletionClock
```

Device-local fields:

```text
selection, scrollOffset, activeTimer, notification state,
window/editor presentation, shortcut bindings
```

Rules:

- Every mutation receives a hybrid logical clock `(wallTime, counter,
  deviceID)`. Device ID is random, stored in Keychain, and used only as a
  deterministic tie-breaker.
- `sync_metadata.base_record_json` stores the last server record observed by
  this device. Incoming and local values are each compared with that base:
  unchanged/local-only/remote-only changes merge directly; changes on both
  sides are concurrent and use the recovery rules below.
- Non-conflicting records merge by field ownership. Promotion changes
  `promotedAt` and `promotionClock`; content edits change `body`,
  `contentRevision`, and `contentClock`; expiration and deletion have their
  own clocks.
- Concurrent edits to the same body never discard text silently. The higher
  clock remains on the original note ID; the lower-clock body is inserted as a
  new recovered note carrying the original note ID and conflict time in local
  metadata.
- A causally later tombstone deletes the note. A deletion concurrent with a
  content edit keeps the tombstone on the original ID and creates a recovered
  note from the concurrent content.
- Tombstones are metadata-only CloudKit records with an empty body and are
  retained for 400 days. A client whose last successful sync is older than 365
  days must create a safety backup and perform a full server re-bootstrap
  before uploading. Local records changed since its last sync are imported as
  recovered notes with new IDs after the server snapshot is applied. This
  prevents stale-ID resurrection while allowing bounded tombstone compaction.
- Tombstone count and oldest age are available only in local diagnostics; they
  are not analytics.
- Transient blank notes are not uploaded. Expiration produces a tombstone.
- Active timers and notification scheduling are device-local in iOS 1.0.
- A local-only store can later enable iCloud. Upload and download run through
  the same merge rules before normal incremental sync begins.
- iCloud account loss pauses sync without deleting local notes. Account
  replacement requires explicit confirmation before joining the new private
  database.
- Backup restore while sync is enabled is a merge/import operation. It does
  not rewind the CloudKit zone or delete records from other devices.
- The product does not claim end-to-end encryption beyond the protection
  Apple documents for the selected CloudKit configuration.

Persistence adds:

```sql
CREATE TABLE ingested_payload (
    id TEXT PRIMARY KEY NOT NULL,
    applied_at REAL NOT NULL
);

CREATE TABLE spotlight_outbox (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    note_revision TEXT,
    enqueued_at REAL NOT NULL
);

CREATE TABLE sync_metadata (
    note_id TEXT PRIMARY KEY NOT NULL,
    base_record_json BLOB,
    local_revision TEXT NOT NULL,
    dirty INTEGER NOT NULL DEFAULT 0,
    cloud_record_name TEXT,
    cloud_change_tag TEXT
);

CREATE TABLE sync_change (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    enqueued_at REAL NOT NULL
);

CREATE TABLE sync_engine_state (
    key TEXT PRIMARY KEY NOT NULL,
    value BLOB NOT NULL
);

CREATE TABLE recovery_metadata (
    note_id TEXT PRIMARY KEY NOT NULL,
    recovered_from_note_id TEXT NOT NULL,
    reason TEXT NOT NULL,
    recovered_at REAL NOT NULL
);
```

Schema details and migration tests are finalized in iOS Step 1 before any
production CloudKit container is deployed.

## 10. Performance Budgets

- Cold launch to interactive editor: p95 under 800 ms on an iPhone XS running
  the latest available iOS 17 point release, measured from process start to
  editable first responder.
- Capture surface to keyboard visible (warm): p95 under 400 ms.
- Typing synchronous work: p95 under 4 ms (same as macOS).
- Share extension cold start to staged: under 1 s; extension memory under
  120 MB (no OCR in-extension).
- Live Activity discrete updates: only on state transitions; zero
  per-second pushes.
- Widget snapshot write: off-main, under 50 ms.

## 11. Privacy And Security

- All macOS section-13 rules apply; additionally:
- The share and widget extension targets contain no analytics, network calls,
  or database access.
- OCR (including camera) is on-device; camera usage description states
  text capture only.
- Spotlight is off by default. When enabled, title and snippet lengths are
  bounded, Lock Screen previews remain disabled, and disabling search purges
  the ForNow searchable domain.
- Inbox, snapshots, and store inherit App Group file protection.
- Share and widget extensions receive no Keychain Access Group entitlement in
  iOS 1.0.
- URL routes reject credentials, fragments where unsupported, malformed
  percent encoding, oversized payloads, unknown actions, and non-allowlisted
  callback schemes.

## 12. Architecture Exit Criteria

1. iOS editor spike passes the macOS Step 0.3 fixture set with a recorded
   rendering decision.
2. Share extension staging survives process kill between write and
   import with exactly-once application.
3. Widget renders from snapshot with the database file deleted (simulated
   lock-out).
4. All packages compile for iOS with Swift 6 concurrency checks; no
   platform `#if` in Core/Modes.
5. A completed timer displays correctly in a stale Live Activity, opens the
   correct timer in the app, and reconciles after termination and reboot.
6. Spotlight outbox survives failures before request, after request, and before
   acknowledgement without losing or exposing deleted notes.
7. CloudKit two-device, concurrent-edit, delete/edit, account-loss, local-only
   enablement, and restore-merge fixtures pass.
8. Network-off run passes every local-only core workflow.

## 13. Extension Boundary (Post-1.0 Research)

- JavaScriptCore availability is necessary but not sufficient. A prototype
  must prove termination, memory limits, scope isolation, and app-process-only
  execution before shared runtime adoption.
- The `::` palette reuses the slash-picker presentation patterns of
  `ForNowEditorIOS`.
- iOS-specific constraints: extensions never run inside widgets or the
  share extension; extension network requests execute only in the app process;
  any shared secrets use a separately configured Keychain Access Group.
- A written App Review assessment covers guideline sections applicable to
  downloadable software, consent, moderation, reporting, and blocking.
- All security rules of `../02_ARCHITECTURE.md` section 15 apply. A failed
  technical or distribution gate removes extensions from iOS scope without
  affecting macOS.
