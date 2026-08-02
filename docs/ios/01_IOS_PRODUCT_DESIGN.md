# ForNow for iPhone - Product And Interaction Design

Status: design draft. This document does not change the macOS 1.0 plan. It
defines the iOS product so that the platform-neutral packages
(`ForNowCore`, `ForNowModes`, `ForNowPersistence`) can be built once and
reused, and so that iOS-specific work has a traceable contract before any
code exists.

Relationship to existing documents:

- `../00_SOURCE_LEDGER.md` remains the behavior evidence base. AntiNote
  evidence (`AN-*`) describes a macOS app; this document records where iOS
  platform constraints force a redesigned interaction rather than a port.
- `../01_PRODUCT_SPEC.md` principles PR-001 through PR-006 still apply. FR
  adaptation is mapped in section 9.
- `../03_IMPLEMENTATION_PLAYBOOK.md` Step 6.2 (iCloud And iOS) is the
  scheduled integration point. Building iOS earlier than that is a product
  decision to record as `FORNOW-DECISION`, not an assumption.

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

## 2. The Core Problem: Invocation Without A Global Hotkey

On macOS, time-to-note is solved by the global hotkey (`AN-WIN-001`). iOS
offers no equivalent. The iOS design therefore replaces one hotkey with a
stack of system capture surfaces, ordered by speed:

| Surface | Time to typing | Mechanism |
|---|---|---|
| Lock Screen widget | ~2 s | Widget button launches app directly into a fresh transient note |
| Action Button (Pro models) | ~2 s | App Intent `CaptureNoteIntent` bound by the user in Settings |
| Control Center control | ~3 s | iOS 18 Controls API, opens capture surface |
| Home Screen quick action | ~3 s | Long-press icon -> "New Note" |
| Back Tap | ~3 s | User-bound Shortcut calling `CaptureNoteIntent` |
| Siri / App Shortcuts | ~4 s | "Capture in ForNow" phrase, optional dictated content |
| Spotlight | ~4 s | App Shortcuts appear as top-hit actions |
| Home Screen icon | ~5 s | Cold open resumes the most recent note |

Rules:

- Every capture surface lands in the same state: editor focused, insertion
  point restored, keyboard up, autosave armed. No interstitial screens.
- Capture surfaces that accept content (Siri dictation, share sheet,
  shortcut input) create the note with that content already committed.
- All capture surfaces are implemented through one versioned App Intents
  surface, mirroring the macOS URL router contract (`FR-URL-001`), so every
  external entry point is testable and rate-limited the same way.

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
| Two-finger swipe between notes | `AN-NAV-002` | Port: horizontal swipe gesture between notes |
| Command-left/right bracket | `AN-NAV-002` | Port for hardware keyboards via `UIKeyCommand`; gesture is primary |
| Create at newest edge, discard blank | `AN-NAV-003`, `AN-NAV-004` | Port unchanged |
| Jump to front / promote | `AN-NAV-005` | Port: toolbar buttons; hardware-keyboard shortcuts when present |
| Confirmed deletion Command-D | `AN-LIFE-002` | Redesign: swipe action or toolbar delete with the same confirmation and suppression semantics |
| Cursor entry after navigation | `AN-NAV-007` | Drop on touch (no pre-edit focus state); hardware keyboards keep arrow-entry |
| Cross-note search Command-F | `AN-NAV-006` | Redesign: pull-down or toolbar search field; results promote on tap. Spotlight indexing (Core Spotlight) makes notes findable system-wide |
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
| Link shortening and expansion | `AN-TXT-003` | Port; long-press replaces Command-click gestures |
| Simple Markdown, code mode | `AN-MD-001`, `AN-CODE-001` | Port unchanged |
| URL schemes / automation | `AN-URL-001` | Port and extend: keep the URL router, add App Intents as the primary iOS automation surface |
| JavaScript extensions (`::` palette) | `AN-EXT-001` through `AN-EXT-004` | Port (post-1.0): shared manifest, sandbox, scopes, and bridges; iOS provides only the palette presentation |
| Quick export and app adapters | `AN-EXP-001..003` | Redesign around the system share sheet; same canonical export document and adapters |
| Themes, paper, text size | `AN-UI-001` | Port; add Dynamic Type support as the iOS-native text-size path |
| RTL layout override | `AN-REV-002` | Port |
| Expiration, backups, bulk delete | `AN-LIFE-001`, `AN-BACK-001`, `AN-NOTE-SET-001` | Port; backups stored on-device and optionally in iCloud Drive (user-visible folder) |
| No usage analytics | `AN-PRIV-001` | Port unchanged |

## 4. In-App Interaction Model

### Navigation

- One note on screen at a time, matching `AN-NAV-001`.
- Horizontal edge-independent swipe moves previous/next. Swiping past the
  newest note creates the transient blank note; leaving it blank discards it
  (unchanged lifecycle rules).
- A bottom bar carries: note count (configurable), search, new note, and
  overflow menu. It collapses while the keyboard is up.
- Hardware keyboards (iPad, paired keyboards) get the full macOS shortcut
  set through `UIKeyCommand` where the OS allows it.

### Editor

- `UITextView` with TextKit 2, wrapped for SwiftUI shell screens (settings,
  search results). The decoration architecture from
  `../02_ARCHITECTURE.md` section 6 applies unchanged: source text only,
  versioned projections, decorations never serialized.
- Slash picker renders as a suggestion strip docked above the keyboard,
  filterable by typing, selectable by tap or number row; VoiceOver
  navigable.
- Links: tap opens (with confirmation sheet), long-press toggles
  expanded/shortened. Same caret-exit shortening rule.
- Checkboxes and math results are tappable decorations with the same
  source-range command paths as macOS.

### Search

- Pull down on the note to reveal the search field (Notes-app idiom), or
  tap the bottom-bar search button.
- Empty query lists all notes, newest first; tapping a result promotes it,
  matching `FR-NOTE-007` semantics.
- Notes are indexed in Core Spotlight with `NSUserActivity` donation so
  system Spotlight finds and opens them; deletion and expiration remove
  index entries in the same transaction.

## 5. AutoPaste Replacement: Deliberate Import

iOS gives no background pasteboard access and shows a consent prompt on
programmatic reads. AutoPaste as designed for macOS (`FR-AUTO-001`) is
impossible; pretending otherwise would produce a broken feature.

Replacement stack, all explicit and session-scoped:

1. **Share Extension** - "Send to ForNow" from any app's share sheet.
   Target choice: append to current note or create a new note. Text, URLs,
   and images (images route to OCR per user setting).
2. **Paste-on-open banner** - when the app becomes active and the
   pasteboard `changeCount` differs from the last seen value, a
   non-modal banner offers "Paste what you copied". One tap, one undo
   group, then the banner dismisses. No silent reads: the check uses
   `UIPasteboard.general.hasStrings` metadata patterns that do not trigger
   the system paste prompt; content is read only after the tap.
3. **App Intents ingestion** - Shortcuts can append clipboard or other
   content through `AppendToNoteIntent`, subject to the same normalization
   pipeline as paste (`FR-CLIP-003`).

The capture-policy formatting from `FR-AUTO-003` (prefix, suffix,
separator, timestamp) survives as the formatting policy for share
extension and intent ingestion.

## 6. Timer: Live Activity Replaces The Menu Bar

- Starting any timer registers a Live Activity; countdowns and stopwatches
  show in the Dynamic Island and on the Lock Screen.
- Pause/resume and stop are Live Activity buttons routed to the same
  `TimerStateMachine` transitions as in-app commands.
- Completion produces the same notification/sound settings as macOS
  (`FR-TIME-003`), mapped to `UNUserNotificationCenter` time-sensitive
  notifications where the user has granted permission.
- Full-screen takeover becomes a critical-banner style local notification;
  iOS has no overlay window concept.
- Timer state persists through termination exactly as in
  `FR-TIME-001`: timestamps, not decremented counters.

## 7. OCR Plus Camera

- Paste, drag (iPad), share sheet, and an in-app camera button all feed
  the same `OCRService` protocol from `ForNowIntegrations`.
- Camera input uses VisionKit's `DataScannerViewController` for live text
  capture and `VNDocumentCameraViewController` for document scans; both
  stay on-device.
- The documented format validation, atomic insertion, and one-undo-group
  rules (`FR-OCR-001..003`) apply unchanged.

## 8. Architecture

### Package reuse

Reused without modification:

- `ForNowCore` - models, state machines, use cases;
- `ForNowModes` - all parsers, evaluators, dependency graphs;
- `ForNowDesign` - semantic tokens (iOS variant adds Dynamic Type scaling).

Reused with iOS implementations behind the same protocols:

- `ForNowPersistence` - same GRDB schema and migrations, stored in the App
  Group container;
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

- App, share extension, widgets, and Live Activity share one
  `DatabasePool` location inside the App Group container.
- Extensions never write SQLite directly. The share extension stages
  payloads as files in the App Group inbox plus a `DarwinNotification`;
  the app imports them through the same use cases as UI commands on next
  activation, and processes any backlog on launch.
- Widgets and Live Activities read through an immutable snapshot file
  written by the app, never through the database.

### Concurrency and limits

Same rules as `../02_ARCHITECTURE.md` sections 11-13: `@MainActor` UI,
actor-isolated repository, versioned parser cancellation, no note text in
logs, sandboxed extensions, Keychain for future secrets.

## 9. Requirement Adaptation

macOS FRs carry over unchanged unless listed here.

- `FR-WIN-001..005` -> replaced by `FR-IOS-CAPTURE-*` (capture surface
  stack, section 2). The macOS requirements remain authoritative for the
  desktop app.
- `FR-AUTO-001..002` -> replaced by `FR-IOS-IMPORT-*` (section 5).
  `FR-AUTO-003` survives as shared formatting policy.
- `FR-TIME-002` external visibility -> Live Activity path (section 6).
- `FR-NOTE-007` search -> extended with Spotlight indexing (section 4).
- `FR-EXP-003` adapters -> share-sheet presentation on iOS; adapter
  internals unchanged.
- New `FR-IOS-SYNC-001` (post-1.0, with Step 6.2): iPhone and Mac share
  one note store through CloudKit with deterministic conflict rules;
  until then both apps remain independent local stores.

All iOS additions must cite this document as their source, the same way
macOS requirements cite `AN-*` evidence. Nothing in this document
reinterprets an `AN-*` fact.

## 10. Phasing

iOS work starts only after one of:

1. macOS 1.0 ships (the playbook default), or
2. a recorded `FORNOW-DECISION` moves it earlier - in which case Phase 0
   spike 0.5 (persistence) still gates everything, because both platforms
   share the schema.

Suggested iOS sequence when started:

- **iOS Step 0** - prove `UITextView` projection parity with the macOS
  editor spike fixtures (same mandatory fixture list), prove App Group
  database sharing between app and share extension.
- **iOS Step 1** - capture stack: app shell, transient notes, navigation
  gestures, Lock Screen widget, App Intents.
- **iOS Step 2** - editor parity: copy/paste, links, Markdown, code,
  find/replace, slash picker strip.
- **iOS Step 3** - modes: list, math, aggregates, variables (pure package
  integration - expected to be fast because the parsers are done).
- **iOS Step 4** - timer with Live Activity, OCR with camera, share
  extension and import banner, search with Spotlight.
- **iOS Step 5** - themes, export, expiration, backups, release.

## 11. Open Questions

- Whether iOS 1.0 ships before CloudKit sync (two independent stores) or
  waits for Step 6.2 (one shared store). Shipping independently first
  risks a migration story for early users with notes on both platforms.
- Paste-on-open banner behavior under iOS paste-consent changes; the
  consent UX must be revalidated on each major iOS release.
- Whether Control Center and Action Button surfaces should open a fresh
  note or resume the most recent one; current decision: fresh transient
  note, matching Journey J-002.
- Widget and Live Activity snapshot refresh budget under iOS background
  execution limits.
