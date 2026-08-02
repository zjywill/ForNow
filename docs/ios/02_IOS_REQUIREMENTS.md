# ForNow iOS Requirements Extension

This file formally defines the iOS-specific requirements referenced by
`01_IOS_PRODUCT_DESIGN.md`. It extends `../01_PRODUCT_SPEC.md`; macOS
`FR-*` requirements remain authoritative for shared behavior and are
reused, not duplicated.

Traceability rules (same as playbook Step 0.2):

- Every `FR-IOS-*` must be registered in `docs/traceability.yml` with its
  source section in `01_IOS_PRODUCT_DESIGN.md`.
- iOS requirements never cite `AN-*` as their direct source; they cite
  this design document set. Shared AntiNote parity stays expressed through
  the macOS `FR-*` requirements they reference.

## Capture

### FR-IOS-CAP-001 - Unified capture surface

- Source: `01_IOS_PRODUCT_DESIGN.md` section 2.
- Every capture surface lands in one identical ready state: editor focused,
  insertion point restored, keyboard visible, autosave armed.
- No capture surface may show an interstitial screen, onboarding gate, or
  note list before the editor.
- All external entry points execute through the versioned App Intents layer
  defined in `03_IOS_ARCHITECTURE.md`, never through ad-hoc URL handling
  inside views.

### FR-IOS-CAP-002 - Widget and Control Center capture

- Source: `01_IOS_PRODUCT_DESIGN.md` section 2.
- Lock Screen and Home Screen widgets provide a capture button that opens a
  fresh transient note.
- On iOS 18 or newer, a Control Center control provides the same action;
  the app remains fully functional on iOS 17 without it.
- Widgets render from the immutable snapshot file only and never open the
  database.

### FR-IOS-CAP-003 - Content-bearing capture

- Source: `01_IOS_PRODUCT_DESIGN.md` section 2.
- Action Button, Back Tap, Siri, and Spotlight App Shortcuts invoke
  `CaptureNoteIntent` with optional text content.
- Supplied content is committed as the note body before the editor
  appears; an empty invocation produces a transient blank note under the
  same lifecycle rules as `FR-NOTE-002`.

## Import

### FR-IOS-IMP-001 - Share extension

- Source: `01_IOS_PRODUCT_DESIGN.md` section 5.
- Accepts text, URLs, and images from the system share sheet.
- User chooses append-to-current or create-new per invocation, with a
  remembered default.
- The extension stages payloads into the App Group inbox and never opens
  or writes the SQLite store.
- Images are staged for OCR by the app; the extension performs no
  recognition itself.

### FR-IOS-IMP-002 - Paste-on-open banner

- Source: `01_IOS_PRODUCT_DESIGN.md` section 5.
- On activation, pasteboard `changeCount` is compared with the last seen
  value using metadata-only APIs; note content is never read
  programmatically before user consent.
- A non-modal banner offers to insert the copied content; tapping inserts
  it as one undo group through the normalization pipeline of
  `FR-CLIP-003`.
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
- Horizontal swipe navigates previous/next; swiping past the newest note
  creates the transient blank note; abandoning it blank discards it.
- Jump-to-front, promote, and confirmed deletion follow `FR-NOTE-004` and
  `FR-NOTE-005` semantics with touch controls.
- Hardware keyboards receive the macOS shortcut set through
  `UIKeyCommand` wherever the OS permits, including arrow-key note entry
  (`AN-NAV-007`).

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

- Source: `01_IOS_PRODUCT_DESIGN.md` section 4.
- In-app search follows `FR-NOTE-007` semantics with touch presentation.
- Notes are indexed in Core Spotlight on save; deletion, expiration, and
  bulk deletion remove index entries in the same transaction as the
  database mutation.
- Tapping a Spotlight result opens the note directly; it does not promote
  it unless the user edits.

## Timer

### FR-IOS-TIME-001 - Live Activity

- Source: `01_IOS_PRODUCT_DESIGN.md` section 6.
- Starting any timer registers a Live Activity; stopping or completing
  ends it within a bounded delay.
- Live Activity buttons invoke the same `TimerStateMachine` transitions
  as in-app commands and URL routes.
- Update frequency respects the system budget defined in
  `03_IOS_ARCHITECTURE.md`; timer display remains timestamp-derived, never
  counter-derived (`FR-TIME-001`).

## OCR

### FR-IOS-OCR-001 - Camera and shared-image recognition

- Source: `01_IOS_PRODUCT_DESIGN.md` section 7.
- Camera capture uses VisionKit live text and document scanning,
  on-device only.
- All recognition honors `FR-OCR-001` through `FR-OCR-003`: format
  validation, cancellable progress, atomic insertion, one undo group.

## Data

### FR-IOS-DATA-001 - App Group store isolation

- Source: `01_IOS_PRODUCT_DESIGN.md` section 8.
- Exactly one SQLite store lives in the App Group container; only the app
  process opens it.
- Inbox imports are idempotent: each staged payload carries a UUID and is
  applied at most once, surviving crashes between staging and import.
- Snapshot files for widgets are versioned, atomically written, and
  contain no more data than the widget renders.

## Accessibility

### FR-IOS-A11Y-001 - Dynamic Type and VoiceOver parity

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 3 and 8.
- Text size honors Dynamic Type alongside the in-app size setting.
- Interactive decorations (checkboxes, results, links, timer) expose
  VoiceOver actions equivalent to their tap behavior, matching
  `FR-MATH-006` accessibility intent.

## Sync

### FR-IOS-SYNC-001 - CloudKit companion sync (post-1.0)

- Source: `01_IOS_PRODUCT_DESIGN.md` sections 9 and 11.
- Target: post-iOS-1.0, implemented with macOS playbook Step 6.2.
- iPhone and Mac share one note store through CloudKit with deterministic
  conflict rules defined before implementation.
- Until sync ships, both platforms keep independent local stores and the
  app must not imply cross-device availability.

## Extensions

### FR-IOS-EXT-001 - Shared extension runtime (post-1.0)

- Source: `01_IOS_PRODUCT_DESIGN.md` section 3; `../00_SOURCE_LEDGER.md`
  `AN-EXT-001` through `AN-EXT-004`.
- Target: post-iOS-1.0, aligned with macOS playbook Step 6.3.
- The manifest schema, sandbox, scopes, and bridges are shared with the
  macOS extension runtime (`FR-EXT-001` through `FR-EXT-004`); iOS adds
  only the `::` palette presentation.
- iOS constraints apply: network only through declared endpoints from the
  app process, no background extension execution, secrets in Keychain.
