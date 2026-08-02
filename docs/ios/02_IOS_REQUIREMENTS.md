# ForNow iOS Requirements Extension

This file formally defines the iOS-specific requirements referenced by
`01_IOS_PRODUCT_DESIGN.md`. It extends `../01_PRODUCT_SPEC.md`; macOS
`FR-*` requirements remain authoritative for shared behavior and are
reused, not duplicated.

Traceability rules:

- Every `FR-IOS-*` is registered now in `traceability.yml` with its source
  section, controlling `FORNOW-DECISION-*`, release scope, and planned test
  IDs.
- `FORNOW-DECISION-012` is the baseline decision for iPhone adaptation;
  privacy, sync, single-writer, network, and extension requirements add their
  narrower decisions.
- Playbook Step 0.2 imports or validates these entries when the repository-wide
  `docs/traceability.yml` is created.
- iOS requirements never cite `AN-*` as their direct source; they cite
  this design document set. Shared AntiNote parity stays expressed through
  the macOS `FR-*` requirements they reference.

## Capture

### FR-IOS-CAP-001 - Unified capture surface

- Source: `01_IOS_PRODUCT_DESIGN.md` section 2;
  `FORNOW-DECISION-009`.
- Every available capture surface targets one ready state: editor focused,
  insertion point restored, keyboard requested, autosave armed.
- The app adds no interstitial screen, onboarding gate, or note list before
  the editor. System authentication, permission, and confirmation UI remain
  allowed when required by iOS.
- All external entry points execute through the versioned App Intents layer
  or the shared command router defined in `03_IOS_ARCHITECTURE.md`, never
  through ad-hoc mutation inside views.

### FR-IOS-CAP-002 - Widget and Control Center capture

- Source: `01_IOS_PRODUCT_DESIGN.md` section 2.
- Lock Screen and Home Screen widgets provide a capture button that opens a
  fresh transient note.
- On iOS 18 or newer, a Control Center control provides the same action;
  the app remains fully functional on iOS 17 without it.
- Device-, lock-, and user-configuration-dependent surfaces are enhancements,
  not prerequisites for the Home Screen capture flow.
- Widgets render from the immutable snapshot file only and never open the
  database.

### FR-IOS-CAP-003 - Content-bearing capture

- Source: `01_IOS_PRODUCT_DESIGN.md` section 2.
- Action Button, Back Tap, Siri, and Spotlight App Shortcuts invoke
  `CaptureNoteIntent` with optional text content.
- Supplied content is committed as the note body before the editor
  appears; an empty invocation produces a transient blank note under the
  same lifecycle rules as `FR-NOTE-002`.
- If iOS requires authentication or opens the app before providing content,
  the command remains idempotent and never creates duplicate notes.

## Import

### FR-IOS-IMP-001 - Share extension

- Source: `01_IOS_PRODUCT_DESIGN.md` section 5;
  `FORNOW-DECISION-009`.
- Accepts text, URLs, and images from the system share sheet.
- User chooses append-to-snapshotted-note or create-new per invocation, with a
  remembered default.
- The extension stages payloads into the App Group inbox and never opens
  or writes the SQLite store.
- Append carries a stable note ID captured from the app-owned share-target
  snapshot. A missing or deleted target degrades to create-new and never
  appends to whichever note happens to be current later.
- Images are staged for OCR by the app; the extension performs no
  recognition itself.

### FR-IOS-IMP-002 - Paste-on-open banner

- Source: `01_IOS_PRODUCT_DESIGN.md` section 5.
- On activation, pasteboard `changeCount` may be compared with the last seen
  value; the app does not read content or type metadata before user action.
- A non-modal banner hosts a system `UIPasteControl` for text and URLs.
  Activating it inserts content as one undo group through the normalization
  pipeline of `FR-CLIP-003`.
- The banner never blocks typing and dismisses after action, timeout, or
  the next capture event.

### FR-IOS-IMP-003 - Intent ingestion policy

- Source: `01_IOS_PRODUCT_DESIGN.md` section 5.
- `AppendToNoteIntent` content passes through the same normalization
  pipeline as paste.
- The formatting policy of `FR-AUTO-003` (prefix, suffix, separator,
  timestamp) applies to share-extension and intent ingestion.

## Navigation And Editor

### FR-IOS-NAV-001 - Touch navigation with macOS semantics

- Source: `01_IOS_PRODUCT_DESIGN.md` section 4.
- A thresholded horizontal paging gesture navigates previous/next; swiping
  past the newest note creates the transient blank note only after commit,
  and abandoning it blank discards it.
- Paging does not begin during marked text, selection-handle interaction,
  link context menus, or horizontal code scrolling. It provides progressive
  boundary resistance before committing.
- Jump-to-front, promote, and confirmed deletion follow `FR-NOTE-004` and
  `FR-NOTE-005` semantics with touch controls.
- Hardware keyboards receive an explicit iOS-applicable shortcut table through
  `UIKeyCommand`; windowing-only commands are excluded and system conflicts
  win.

### FR-IOS-EDIT-001 - Editor projection parity

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 4 and 8.
- The iOS editor honors the same contracts as `FR-EDIT-001`,
  `FR-EDIT-002`, `FR-EDIT-005`, and `FR-EDIT-006`: source-only
  persistence, versioned projections, undo grouping, and correct
  international text handling.
- The iOS editor passes the same mandatory fixture set as the macOS
  editor spike before any mode feature ships.

## Search

### FR-IOS-SRCH-001 - In-app and Spotlight search

- Source: `01_IOS_PRODUCT_DESIGN.md` section 4;
  `FORNOW-DECISION-008`.
- In-app search follows `FR-NOTE-007` semantics with touch presentation.
- Core Spotlight is disabled by default and requires explicit opt-in.
- A note mutation writes a search-index outbox record in the same SQLite
  transaction. Asynchronous indexing applies bounded title/snippet metadata;
  deletion, expiration, and bulk deletion enqueue removals.
- Reconciliation repairs missed or duplicate index operations. The app never
  claims atomicity across SQLite and Core Spotlight.
- Tapping a Spotlight result opens the note directly; it does not promote
  it unless the user edits.

## Timer

### FR-IOS-TIME-001 - Live Activity

- Source: `01_IOS_PRODUCT_DESIGN.md` section 6;
  `FORNOW-DECISION-009`.
- Starting any timer registers a Live Activity; stopping or completing
  marks it stale or ends it at the next permitted execution opportunity.
- iOS 1.0 Live Activities are read-only. Tapping opens the app at the linked
  timer; pause/resume/stop then use the normal state machine.
- Update frequency respects the system budget defined in
  `03_IOS_ARCHITECTURE.md`; timer display remains timestamp-derived, never
  counter-derived (`FR-TIME-001`).
- Completion uses ordinary or time-sensitive local notifications according to
  permission and user settings. Critical Alerts are not required.

## OCR

### FR-IOS-OCR-001 - Camera and shared-image recognition

- Source: `01_IOS_PRODUCT_DESIGN.md` section 7.
- Camera capture uses VisionKit live text only when the device reports it
  supported and available; still-image or document-scan capture is the
  required fallback.
- Recognition remains on-device.
- All recognition honors `FR-OCR-001` through `FR-OCR-003`: format
  validation, cancellable progress, atomic insertion, one undo group.

## Data

### FR-IOS-DATA-001 - App Group store isolation

- Source: `01_IOS_PRODUCT_DESIGN.md` section 8;
  `FORNOW-DECISION-009`.
- Exactly one SQLite store lives in the App Group container; only the app
  process opens it.
- Inbox imports are idempotent: each staged payload carries a UUID and is
  applied at most once, surviving crashes between staging and import.
- Snapshot files for widgets are versioned, atomically written, and
  contain no more data than the widget renders.
- Share-target snapshots contain only the stable current note ID and version;
  no note body is exposed to extensions.

## Accessibility

### FR-IOS-A11Y-001 - Dynamic Type and VoiceOver parity

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 3 and 8.
- Text size honors Dynamic Type alongside the in-app size setting.
- Interactive decorations (checkboxes, results, links, timer) expose
  VoiceOver actions equivalent to their tap behavior, matching
  `FR-MATH-006` accessibility intent.
- Paging, sheets, and Live Activity transitions respect Reduce Motion.
  Materials respect Reduce Transparency and Increase Contrast.

## Lifecycle And Appearance

### FR-IOS-LIFE-001 - Launch and resume policy

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 2 and 9.
- Ordinary app launch follows an iOS-specific resume-or-new-note setting.
- Background/foreground transitions alone never create a note.
- Explicit capture routes may request a fresh transient note regardless of the
  ordinary launch setting.
- Expiration and bulk deletion retain the shared `FR-NOTE-006` and
  `FR-NOTE-010` semantics.

### FR-IOS-UI-001 - Platform appearance

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 3 and 9.
- Built-in semantic themes and paper styles reuse `FR-UI-001`; text size
  integrates Dynamic Type rather than using a fixed macOS-only scale.
- macOS translucent mode does not port. iOS uses system materials only where
  they preserve legibility and honors Reduce Transparency.
- Shortcut customization includes only commands that exist on iOS.

## Export, Backup, Privacy, And Release

### FR-IOS-EXP-001 - System export and safe automation subset

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 3 and 9.
- Exports begin from the canonical `FR-EXP-001` document and present the
  system share sheet or an explicit Files destination.
- App adapters are share targets or separately validated URL routes; no
  adapter writes another application's storage directly.
- iOS URL automation may expose open, create, append, overwrite, promote/open,
  and bounded search callbacks. macOS-only hotkey, pin, and database-reload
  routes are unavailable.
- Invalid or oversized routes cause no mutation.

### FR-IOS-BACK-001 - Backup and restore

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 3 and 9.
- Automatic backups remain inside the protected application container.
- User-initiated export and restore use Files/document-picker flows and may
  target iCloud Drive when the user selects it.
- Restore validates schema and checksum, creates a safety backup, and commits
  atomically under `FR-BACK-002`.
- With sync enabled, restore merges/imports records through the sync engine; it
  does not rewind the CloudKit zone or erase newer records on other devices.
- The product does not promise that its live SQLite store is browsable in
  Files.

### FR-IOS-PRIV-001 - External surface privacy

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 4 and 9;
  `FORNOW-DECISION-008`.
- No usage analytics requirement `FR-PRIV-001` carries over unchanged.
- Spotlight indexing is opt-in and exposes only bounded title/snippet
  metadata.
- Widgets, Live Activities, App Entities, and notifications reveal no note
  body by default on locked surfaces.
- Users can disable and purge system indexing without deleting notes.

### FR-IOS-REL-001 - App Store updates and support

- Source: `01_IOS_PRODUCT_DESIGN.md` section 9.
- App Store distribution replaces direct-download, Homebrew, Sparkle-style
  update consent, and terminal support flows.
- Preference reset is an in-app action that preserves notes and backups.
- Diagnostics are exported through an explicit, redacted support package; no
  note body, clipboard content, URL payload, or secret is included.
- Upgrade and reinstall tests preserve the application container where iOS
  guarantees it; uninstall is documented as destructive to local-only data.

## Sync

### FR-IOS-SYNC-001 - CloudKit companion sync (iOS 1.0 release gate)

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 9 through 11;
  `FORNOW-DECISION-007`.
- Target: required before public iOS 1.0, implemented with macOS playbook
  Step 6.2.
- iPhone and Mac share one note store through CloudKit with deterministic
  conflict rules defined before implementation.
- Internal iOS prototypes may use an isolated disposable store. Public builds
  include the sync engine and also support a clearly labeled local-only mode
  when iCloud is unavailable or disabled. Enabling iCloud later runs the
  documented merge and recovery flow.
- Tombstones are retained for the documented bounded period. A device whose
  last successful sync predates that period must re-bootstrap before upload so
  stale local records cannot resurrect deleted notes.

## Extensions

### FR-IOS-EXT-001 - Shared extension runtime (post-1.0)

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 3 and 11;
  `FORNOW-DECISION-011`. Shared runtime behavior remains governed by
  `FR-EXT-001` through `FR-EXT-004`, which carry the AntiNote beta evidence.
- Target: research gate after iOS 1.0, aligned with macOS playbook Step 6.3.
- Technical feasibility must prove sandbox termination, memory limits, scope
  isolation, structural endpoint checks, and app-only execution.
- Distribution feasibility must document the current App Review rules for
  downloaded code, per-extension consent, moderation, reporting, and blocking.
- Failure of either gate means the iOS product ships without JavaScript
  extensions; this does not block the macOS runtime.
