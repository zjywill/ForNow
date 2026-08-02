# ForNow for iPhone - Product And Interaction Design

Status: implementation-ready iOS 1.0 plan. This document does not change the
macOS 1.0 plan and is not evidence of AntiNote iOS parity. It defines the
iOS product so that the platform-neutral packages
(`ForNowCore`, `ForNowModes`, `ForNowPersistence`) can be built once and
reused, and so that iOS-specific work has a traceable contract before code
exists. Release-blocking defaults and fallbacks are fixed; only explicitly
post-1.0 research remains feasibility-gated.

Relationship to existing documents:

- `../00_SOURCE_LEDGER.md` remains the behavior evidence base. AntiNote
  evidence (`AN-*`) describes a macOS app; this document records where iOS
  platform constraints force a redesigned interaction rather than a port.
- `../01_PRODUCT_SPEC.md` principles PR-001 through PR-006 still apply. FR
  adaptation is mapped in section 9.
- `../03_IMPLEMENTATION_PLAYBOOK.md` Step 6.2 (iCloud And iOS) is the
  scheduled integration point. Building iOS earlier than that is a product
  decision to record as `FORNOW-DECISION`, not an assumption.

Platform references reviewed on 2026-08-02:

- App Intents: `https://developer.apple.com/documentation/appintents`
- ActivityKit: `https://developer.apple.com/documentation/activitykit`
- Core Spotlight: `https://developer.apple.com/documentation/corespotlight`
- VisionKit data scanning:
  `https://developer.apple.com/documentation/visionkit/datascannerviewcontroller`
- App Review Guidelines:
  `https://developer.apple.com/app-store/review/guidelines/`

## 1. Positioning On iPhone

ForNow on iPhone is the same product idea - a local-first scratchpad for
text that is useful now but does not deserve organization - adapted to a
platform with no global hotkey, no floating windows, and no background
clipboard access.

It is optimized for:

- capturing a thought in under three seconds from any context;
- quick calculations, conversions, checklists, and timers on the go;
- receiving text and images from other apps through the share sheet;
- OCR from camera and screenshots;
- staging text before exporting it to a permanent destination.

It is not:

- a replacement for the macOS invocation model - the two apps are
  companions, joined later by sync (`AN-BETA-002`, Step 6.2);
- a knowledge base, document editor, or task manager;
- a cloud account service or AI chat application.

iOS 1.0 targets iPhone (`TARGETED_DEVICE_FAMILY = 1`). iPad-specific
multicolumn layout, pointer interactions, and drag/drop are deferred; an iPad
running the iPhone-compatible build receives no separate layout promise.

## 2. The Core Problem: Invocation Without A Global Hotkey

On macOS, time-to-note is solved by the global hotkey (`AN-WIN-001`). iOS
offers no equivalent. The iOS design therefore replaces one hotkey with a
stack of system capture surfaces. Availability depends on OS version, device,
user configuration, lock state, and system scheduling:

| Surface | Availability | Mechanism |
|---|---|---|
| Lock Screen widget | Supported devices; unlock may be required | Widget action opens a fresh transient note |
| Action Button | Supported devices and user configuration | User binds a ForNow App Shortcut or Control |
| Control Center control | iOS 18+ | Control opens the capture route |
| Home Screen quick action | iOS baseline | Long-press icon -> "New Note" |
| Back Tap | User-configured Accessibility shortcut | Shortcut calls `CaptureNoteIntent` |
| Siri / App Shortcuts | Locale and system support vary | Capture phrase with optional dictated content |
| Spotlight | App Shortcut availability varies | Capture action may appear in system search |
| Home Screen icon | iOS baseline | Cold open follows the configured resume policy |

Rules:

- Every available capture surface targets the same ready state: editor focused,
  insertion point restored, keyboard requested, autosave armed. Authentication,
  permission, or system-owned confirmation UI is allowed when iOS requires it.
- Capture surfaces that accept content (Siri dictation, share sheet,
  shortcut input) create the note with that content already committed.
- All capture surfaces are implemented through one versioned App Intents
  surface, mirroring the macOS URL router contract (`FR-URL-001`), so every
  external entry point is decoded and tested consistently. A URL route may
  delegate to the same command layer but is not replaced by App Intents.

## 3. Interaction Redesign Matrix

Each row records a macOS interaction, its evidence, and the iOS decision.
`Port` means the interaction carries over; `Redesign` means a new iOS
interaction replaces it; `Drop` means the platform makes it impossible.

| macOS interaction | Evidence | iOS decision |
|---|---|---|
| Global hotkey Option-A | `AN-WIN-001` | Redesign: capture surface stack (section 2) |
| Window presence modes (Dock/Menu Bar/Both/Neither) | `AN-WIN-002` | Drop: no equivalent concept |
| Pin window / auto-hide | `AN-WIN-003` | Drop |
| Spaces, full-screen overlay, multi-display | `AN-WIN-004` | Drop |
| Command-W/O close and toggle | `AN-WIN-005` | Drop: iOS app lifecycle handles this |
| Two-finger swipe between notes | `AN-NAV-002` | Redesign: conflict-aware paging gesture between notes |
| Command-left/right bracket | `AN-NAV-002` | Port for hardware keyboards via `UIKeyCommand`; gesture is primary |
| Create at newest edge, discard blank | `AN-NAV-003`, `AN-NAV-004` | Port unchanged |
| Jump to front / promote | `AN-NAV-005` | Port: toolbar buttons; hardware-keyboard shortcuts when present |
| Confirmed deletion Command-D | `AN-LIFE-002` | Redesign: swipe action or toolbar delete with the same confirmation and suppression semantics |
| Cursor entry after navigation | `AN-NAV-007` | Drop on touch (no pre-edit focus state); hardware keyboards keep arrow-entry |
| Cross-note search Command-F | `AN-NAV-006` | Redesign: explicit toolbar search; optional, privacy-gated Core Spotlight indexing |
| Find and replace | `AN-NAV-006` | Port with touch UI; same matching modes and source-coordinate rules |
| Contextual copy decision table | `AN-CLIP-001` | Port unchanged (selection > inline code > block > whole note) |
| Clean copy projection | `AN-CLIP-002` | Port unchanged |
| Paste normalization + raw paste | `AN-CLIP-003` | Port, subject to section 5 consent UX |
| Keywords, slash picker, aliases, case-insensitive matching | `AN-CMD-001..003`, `AN-REV-001` | Port unchanged; slash picker becomes a bottom-anchored suggestion bar above the keyboard |
| List mode, check trigger | `AN-LIST-001..003` | Port; checkbox toggled by tap or trigger text |
| Math, units, currency, variables, aggregates | `AN-MATH-001..005` | Port unchanged (parser packages are platform-neutral) |
| Result click-to-copy | `AN-MATH-005` | Port: tap-to-copy with haptic confirmation |
| Timer commands | `AN-TIME-001` | Port; see section 6 for Live Activity redesign |
| Menu-bar timer status | `AN-TIME-002` | Redesign: Live Activity + Dynamic Island |
| Screenshot/image OCR | `AN-OCR-001`, `AN-OCR-002` | Port, plus camera scanning via VisionKit (section 7) |
| AutoPaste session | `AN-AUTO-001`, `AN-AUTO-002` | Drop: iOS forbids background clipboard polling. Replacement in section 5 |
| Link shortening and expansion | `AN-TXT-003` | Port; a standard context menu exposes open and expand/shorten actions |
| Simple Markdown, code mode | `AN-MD-001`, `AN-CODE-001` | Port unchanged |
| URL schemes / automation | `AN-URL-001` | Port and extend: keep the URL router, add App Intents as the primary iOS automation surface |
| JavaScript extensions (`::` palette) | `AN-EXT-001` through `AN-EXT-004` | Research only: shared runtime requires technical and App Review feasibility gates |
| Quick export and app adapters | `AN-EXP-001..003` | Redesign around the system share sheet; same canonical export document and adapters |
| Themes, paper, text size | `AN-UI-001` | Port; add Dynamic Type support as the iOS-native text-size path |
| RTL layout override | `AN-REV-002` | Port |
| Expiration, backups, bulk delete | `AN-LIFE-001`, `AN-BACK-001`, `AN-NOTE-SET-001` | Adapt: local backups plus explicit Files export/import; no assumed always-visible database folder |
| No usage analytics | `AN-PRIV-001` | Port unchanged |

## 4. In-App Interaction Model

### Navigation

- One note on screen at a time, matching `AN-NAV-001`.
- A paging gesture moves previous/next only after a horizontal-intent threshold.
  It does not begin during marked text, text selection handles, link gestures,
  or horizontal code scrolling. Boundary resistance previews the transient
  blank note before the gesture commits.
- A bottom toolbar carries note count (configurable), search, new note, and
  overflow. While the keyboard is visible, the essential actions remain
  available through a compact input accessory or safe-area toolbar.
- Hardware keyboards get an explicit iOS shortcut table through `UIKeyCommand`.
  Windowing-only macOS shortcuts are excluded and system conflicts win.

### Editor

- `UITextView` with TextKit 2, wrapped for SwiftUI shell screens (settings,
  search results). The decoration architecture from
  `../02_ARCHITECTURE.md` section 6 applies unchanged: source text only,
  versioned projections, decorations never serialized.
- Slash picker renders as a suggestion strip docked above the keyboard,
  filterable by typing and selectable by tap. Hardware number keys select
  numbered entries; VoiceOver actions expose the same choices.
- Links use a standard context menu for Open and Expand/Shorten. A direct tap
  follows the configured link-opening policy. Same caret-exit shortening rule.
- Checkboxes and math results are tappable decorations with the same
  source-range command paths as macOS.

### Search

- Tap the toolbar search button to present cross-note search. Pull-to-reveal is
  reserved for a future note-list surface and is not attached to the editor
  scroll gesture.
- Empty query lists all notes, newest first; tapping a result promotes it,
  matching `FR-NOTE-007` semantics.
- Core Spotlight indexing is disabled by default. When the user opts in, a
  transactional outbox records index work beside note mutations and an
  asynchronous worker applies bounded title/snippet metadata. Reconciliation
  repairs missed updates. Core Spotlight is never described as part of the
  SQLite transaction (`FORNOW-DECISION-008`).

## 5. AutoPaste Replacement: Deliberate Import

iOS gives no background pasteboard access and shows a consent prompt on
programmatic reads. AutoPaste as designed for macOS (`FR-AUTO-001`) is
impossible; pretending otherwise would produce a broken feature.

Replacement stack, all explicit and session-scoped:

1. **Share Extension** - "Send to ForNow" from any app's share sheet.
   Target choice: append to the note that was active when the share target
   snapshot was written, or create a new note. The staged payload carries a
   stable note ID; if it is stale or absent, the import creates a new note
   rather than appending to an unrelated future "current" note. Text, URLs,
   and images are accepted; images route to OCR per user setting.
2. **Paste-on-open banner** - when the app becomes active and the
   pasteboard `changeCount` differs from the last seen value, a non-modal
   banner presents a system `UIPasteControl` configured for text and URLs.
   The app does not read pasteboard content to decide whether to show the
   banner. The user's tap performs the paste as one undo group, then the
   banner dismisses.
3. **App Intents ingestion** - Shortcuts can append clipboard or other
   content through `AppendToNoteIntent`, subject to the same normalization
   pipeline as paste (`FR-CLIP-003`).

The capture-policy formatting from `FR-AUTO-003` (prefix, suffix,
separator, timestamp) survives as the formatting policy for share
extension and intent ingestion.

## 6. Timer: Live Activity Replaces The Menu Bar

- Starting a supported timer may register a Live Activity; countdowns and
  stopwatches show in supported Lock Screen and Dynamic Island presentations.
- iOS 1.0 Live Activities are read-only. Tapping the activity opens the app at
  the timer, where pause/resume/stop execute through the normal state machine.
  Interactive background controls are a later enhancement gated by a platform
  spike and the single-writer database rule (`FORNOW-DECISION-009`).
- Completion produces the same notification/sound settings as macOS
  (`FR-TIME-003`), mapped to `UNUserNotificationCenter` time-sensitive
  notifications where the user has granted permission.
- The macOS full-screen takeover is dropped. ForNow does not request or imply
  Critical Alerts entitlement; time-sensitive delivery remains subject to
  user and system policy.
- The activity uses timestamp-derived display and a stale date. Without remote
  push or granted background execution, completion cannot promise that iOS
  will end the activity within a fixed number of seconds; final cleanup occurs
  on the next execution opportunity.
- Timer state persists through termination exactly as in
  `FR-TIME-001`: timestamps, not decremented counters.

## 7. OCR Plus Camera

- Paste, share sheet, and an in-app camera button all feed
  the same `OCRService` protocol from `ForNowIntegrations`.
- Camera input uses VisionKit's `DataScannerViewController` for live text
  capture when `isSupported` and `isAvailable` are true, with still-image or
  document-scan fallback when live scanning is unavailable.
- `VNDocumentCameraViewController` and Vision recognition stay on-device.
- The documented format validation, atomic insertion, and one-undo-group
  rules (`FR-OCR-001..003`) apply unchanged.

## 8. Architecture

### Package reuse

Targeted for reuse after cross-platform compile and behavior tests:

- `ForNowCore` - models, state machines, use cases;
- `ForNowModes` - all parsers, evaluators, dependency graphs;
- `ForNowDesign` - semantic tokens (iOS variant adds Dynamic Type scaling).

Reused with iOS implementations behind the same protocols:

- `ForNowPersistence` - same logical GRDB schema and migrations, with the
  container path and protection policy injected per platform;
- `ForNowIntegrations` - iOS implementations of OCR, notifications, rate
  providers, export adapters, URL router.

New iOS-only modules:

- `ForNowEditorIOS` - `UITextView` editor with the same projection and
  decoration contracts as `ForNowEditor`;
- `ForNowCapture` - App Intents, widgets, Control Center control, share
  extension, Spotlight donation;
- iOS app shell (SwiftUI) with settings screens mirroring the macOS
  settings model contracts.

### App Group and extensions

- One SQLite store lives in the App Group container and is opened only by the
  app process (`FORNOW-DECISION-009`).
- Extensions never write SQLite directly. The share extension stages
  payloads as files in the App Group inbox plus a `DarwinNotification`;
  the app imports them through the same use cases as UI commands on next
  activation, and processes any backlog on launch.
- Widgets and Live Activities read immutable snapshot files written by the
  app, never through the database.

### Concurrency and limits

Same rules as `../02_ARCHITECTURE.md` sections 11-13: `@MainActor` UI,
actor-isolated repository, versioned parser cancellation, no note text in
logs, sandboxed extensions, Keychain for future secrets.

## 9. Requirement Adaptation

macOS requirements do not carry over by default. Each group has an explicit
iOS disposition:

| macOS requirements | iOS disposition |
|---|---|
| `FR-WIN-001..005` | Not applicable; replaced by `FR-IOS-CAP-*` |
| `FR-NOTE-001..006`, `008`, `010` | Shared behavior |
| `FR-NOTE-007`, `009` | Adapted by `FR-IOS-SRCH-001` and `FR-IOS-LIFE-001` |
| `FR-EDIT-*`, `FR-CLIP-*`, `FR-CMD-*`, `FR-LIST-*`, `FR-MATH-*` | Shared source semantics; touch and keyboard presentation are iOS-specific |
| `FR-TIME-001..002` | Shared state machine; external visibility adapted by `FR-IOS-TIME-001` |
| `FR-OCR-*` | Shared recognition/insertion contracts; camera availability adapted by `FR-IOS-OCR-001` |
| `FR-AUTO-001..002` | Not applicable; replaced by `FR-IOS-IMP-*` |
| `FR-AUTO-003` | Shared formatting policy |
| `FR-EXP-*` | Adapted by `FR-IOS-EXP-001` |
| `FR-BACK-*` | Adapted by `FR-IOS-BACK-001` |
| `FR-UI-001`, `003` | Shared intent; adapted by `FR-IOS-UI-001` |
| `FR-UI-002` | Paper styles may port; macOS translucency does not |
| `FR-UI-004` | Deferred with custom-theme work |
| `FR-URL-001..002` | Only the documented safe subset in `FR-IOS-EXP-001`; hotkey, pin, and database reload routes do not port |
| `FR-INT-001` | Not applicable on iOS |
| `FR-EXT-*` | Research only under `FR-IOS-EXT-001` and `FORNOW-DECISION-011` |
| `FR-UPD-001`, `FR-SUP-001`, `FR-DIST-001` | Replaced by `FR-IOS-REL-001` |
| `FR-PRIV-001` | Shared, extended by `FR-IOS-PRIV-001` |

Every iOS addition cites this design set and the controlling
`FORNOW-DECISION-*` where one exists. Nothing in this document reinterprets an
`AN-*` fact or claims parity with an unpublished AntiNote iOS interaction.

## 10. Phasing

iOS feasibility and editor spikes may start after macOS 1.0. Public iOS 1.0 is
blocked until the sync engine and local-only fallback pass the Step 6.2 exit
criteria (`FORNOW-DECISION-007`).

Suggested iOS sequence when started:

- **iOS Step 0** - prove `UITextView` projection parity; prove App Group inbox
  staging without extension database access; spike App Intent execution,
  Live Activity controls, Spotlight outbox, VisionKit fallback, and App Store
  extension policy.
- **iOS Step 1** - capture stack: app shell, transient notes, navigation
  gestures, Lock Screen widget, App Intents.
- **iOS Step 2** - editor parity: copy/paste, links, Markdown, code,
  find/replace, slash picker strip.
- **iOS Step 3** - modes: list, math, aggregates, variables (pure package
  integration - expected to be fast because the parsers are done).
- **iOS Step 4** - timer with Live Activity, OCR with camera, share
  extension and import banner, search with Spotlight.
- **iOS Step 5** - sync migration, themes, export, expiration, backups,
  accessibility, privacy, App Store release.

## 11. Fixed 1.0 Decisions And Deferred Research

- Every explicit capture surface opens a fresh transient note. Ordinary Home
  Screen launch follows `FR-IOS-LIFE-001`.
- Paste-on-open uses `UIPasteControl`; paste-consent behavior is revalidated on
  every major iOS release without changing the no-pre-read rule.
- Widget and Live Activity snapshots are best-effort and may be stale until the
  next permitted refresh; the app view is authoritative.
- iOS 1.0 Live Activities are read-only and open the app for control.
- User-installable JavaScript extensions are post-1.0 research and cannot block
  the core iOS release.
