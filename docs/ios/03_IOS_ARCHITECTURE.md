# ForNow iOS Technical Architecture

Implements `02_IOS_REQUIREMENTS.md`. Shares the baseline rules of
`../02_ARCHITECTURE.md` (Swift 6 concurrency, error handling, privacy,
package discipline); only iOS-specific decisions are recorded here.

## 1. Baseline

- Deployment target: iOS 17.0.
- iOS 18-only features (Control Center control) are availability-gated and
  never required for core flows.
- Toolchain: Swift 6 language mode; XcodeGen-generated project from
  `project.ios.yml`, with no manually added files after generation.
- Targets:

| Target | Kind | Purpose |
|---|---|---|
| `ForNowIOS` | app | editor, modes, settings, search, export |
| `ForNowShareExtension` | share extension | stage shared content into the inbox |
| `ForNowWidgets` | widget extension | capture widgets, Control (iOS 18+), timer Live Activity |
| `ForNowIOSTests` / `ForNowIOSUITests` | test bundles | unit and UI tests |

- Entitlements: App Groups (`group.<team>.fornow`) for app, share
  extension, and widgets. No push notifications in 1.0; Live Activities
  update locally. Keychain sharing is deferred until sync.
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
group.<team>.fornow/
├── store/notes.sqlite3          # opened only by the app process
├── inbox/<uuid>.json            # staged payload descriptor
├── inbox/<uuid>.bin             # optional binary payload (image)
└── snapshots/widget-v1.json     # immutable widget snapshot
```

### Inbox payload descriptor (versioned)

```json
{
  "version": 1,
  "id": "UUID",
  "createdAt": "ISO-8601",
  "kind": "text | url | image",
  "target": "currentNote | newNote",
  "text": "optional inline text",
  "payloadFile": "optional <uuid>.bin"
}
```

Import rules:

- The share extension writes the descriptor and payload atomically
  (write-temp-then-rename) and posts a Darwin notification; it never
  opens the database.
- The app imports on activation: parse, validate, apply through the same
  use cases as UI commands, then delete the staged files.
- Import is idempotent by payload UUID; a crash between apply and delete
  re-processes safely.
- Malformed payloads are quarantined to `inbox/quarantine/` with a
  diagnostic entry (no user content in logs).

### Widget snapshot

- Written atomically by the app after note-list-relevant mutations.
- Contains only: up to N newest note IDs, first-line previews (bounded
  length), note count, and active timer summary.
- Widgets read only this file. Schema versioned as `widget-v1`; unknown
  versions render a neutral placeholder.

## 4. App Intents Contract

One versioned surface, mirroring the macOS URL router discipline
(`FR-URL-001`): strict decoding, bounded payloads, no mutation on invalid
input.

- `CaptureNoteIntent(content: String?)` - creates note (or transient
  blank), opens app into the ready state of `FR-IOS-CAP-001`.
- `AppendToNoteIntent(content: String, target: current | new)` - ingests
  through the normalization pipeline; callable from Shortcuts without
  opening the app (returns receipt, app applies on next activation via
  the inbox mechanism).
- `SearchNotesIntent(term: String)` - returns up to 20
  `NoteEntity(id, title, snippet, lastModified)`; read-only.
- `ToggleTimerIntent(action: pauseResume | stop, timerID?)` - routes to
  `TimerStateMachine`; used by Live Activity buttons.

Limits: text payloads capped at 200 KB, image payloads at 25 MB decoded
area per the OCR limits in `../02_ARCHITECTURE.md` section 10.
`NoteEntity` exposure is limited to id, first-line title, snippet, and
timestamps - never full body through entity queries except by explicit
open.

## 5. Editor Architecture

`ForNowEditorIOS` mirrors the macOS editor contract
(`../02_ARCHITECTURE.md` section 6):

- `UITextView` + TextKit 2, hosted in SwiftUI via `UIViewRepresentable`.
- Same `SourceSnapshot` / `EditorProjection` / `EditorDecoration` types
  from the shared packages; decoration rendering strategy is decided by
  the iOS editor spike below, not assumed from the macOS choice.
- Slash picker is an input-accessory suggestion strip driven by the same
  slash catalog from `ForNowModes`.
- Hardware keyboard: `UIKeyCommand` table mapping the macOS shortcut set;
  conflicts with system gestures resolve in favor of the system and are
  documented.

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
- Live Activity buttons invoke `ToggleTimerIntent`.
- End-of-timer cleanup runs within 30 seconds of completion; stale
  activities are reconciled on launch.

## 7. Spotlight Indexing

- `CSSearchableItem` per note: `identifier = noteID`,
  `title = first line (bounded)`, `contentDescription = body excerpt`,
  `contentModificationDate`.
- Index updates are hooks on the repository transaction: save upserts;
  delete, expire, and bulk-delete remove. FTS table and Spotlight index
  are updated from the same commit boundary.
- Expired and blank-transient notes are never indexed.
- A reconciliation pass on launch removes index entries whose note IDs no
  longer exist.

## 8. Clipboard Banner Mechanics

- The app stores the last observed `UIPasteboard.general.changeCount` on
  resignation.
- On activation, only `changeCount` and `hasStrings` metadata are read;
  string content is read exclusively inside the banner's tap handler.
- Banner payload passes through the `FR-CLIP-003` pipeline; suppressed
  when AutoPaste-equivalent ingestion just ran or the banner was
  dismissed for the same `changeCount`.

## 9. Performance Budgets

- Cold launch to interactive editor: under 600 ms on the oldest supported
  device in the test matrix.
- Capture surface to keyboard visible (warm): p95 under 400 ms.
- Typing synchronous work: p95 under 4 ms (same as macOS).
- Share extension cold start to staged: under 1 s; extension memory under
  120 MB (no OCR in-extension).
- Live Activity discrete updates: only on state transitions; zero
  per-second pushes.
- Widget snapshot write: off-main, under 50 ms.

## 10. Privacy And Security

- All macOS section-13 rules apply; additionally:
- Extensions contain no analytics, no network calls, and no database
  access.
- OCR (including camera) is on-device; camera usage description states
  text capture only.
- Spotlight excerpts are excluded from indexing when a note is flagged by
  expiration policy as private (future setting; default: index all).
- Inbox, snapshots, and store inherit App Group file protection.

## 11. Architecture Exit Criteria

1. iOS editor spike passes the macOS Step 0.3 fixture set with a recorded
   rendering decision.
2. Share extension staging survives process kill between write and
   import with exactly-once application.
3. Widget renders from snapshot with the database file deleted (simulated
   lock-out).
4. All packages compile for iOS with Swift 6 concurrency checks; no
   platform `#if` in Core/Modes.
5. Live Activity start/pause/stop round-trips through the state machine
   with the app terminated between transitions.
6. Network-off run passes every core workflow.

## 12. Extension Boundary (Post-1.0)

- JavaScriptCore is available on iOS; the extension runtime layer
  (manifest parsing, sandbox, scope enforcement, bridges) ships in a
  shared package consumed by both platforms.
- The `::` palette reuses the slash-picker presentation patterns of
  `ForNowEditorIOS`.
- iOS-specific constraints: extensions never run inside widgets or the
  share extension; extension network requests execute only in the app
  process; Keychain access moves to the shared App Group keychain when
  sync ships.
- All rules of `../02_ARCHITECTURE.md` section 15 apply unchanged.
