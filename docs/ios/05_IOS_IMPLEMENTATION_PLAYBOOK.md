# ForNow iOS Implementation Playbook

## Purpose

This is the executable build order for the iPhone product defined by:

- `01_IOS_PRODUCT_DESIGN.md`;
- `02_IOS_REQUIREMENTS.md`;
- `03_IOS_ARCHITECTURE.md`;
- `04_IOS_TEST_MATRIX.md`;
- `traceability.yml`.

It assumes the macOS 1.0 shared packages exist and pass their own Phase 0
gates. iOS feasibility work may begin after macOS 1.0. A public iOS 1.0 is
blocked until Step 1 sync and migration are complete.

## Status And Reporting

Use the macOS playbook status vocabulary: `BLOCKED`, `READY`, `ACTIVE`,
`VERIFYING`, `DONE`.

Each step creates `docs/progress/IOS-STEP-XX.md` with:

- status, owner, start date, completion date;
- requirements and decisions reviewed;
- Xcode, SDK, deployment target, and device matrix;
- changed files and migrations;
- commands and test results;
- screenshots or recordings for manual interaction cells;
- performance measurements;
- deviations, risks, and follow-up work.

No step is `DONE` until every listed exit criterion is recorded.

## Build Conventions

- Project source of truth: `project.ios.yml`.
- Configuration source of truth: checked-in `.xcconfig` templates plus local
  signing values.
- Generated Xcode project files must produce no unexplained diff.
- Swift 6 concurrency warnings are errors in shared and iOS targets.
- The app target is the only SQLite writer.
- Every external mutation carries an idempotency UUID.
- UI code calls use cases; views, widgets, intents, and extensions never write
  persistence directly.
- Every `FR-IOS-*` maps through `traceability.yml` to at least one test.

Run `scripts/validate-ios-docs.rb` after every requirements, test-matrix,
decision, or traceability change.

Expected script surface:

```text
scripts/ios/bootstrap.sh
scripts/ios/generate.sh
scripts/ios/build.sh
scripts/ios/test-unit.sh
scripts/ios/test-ui.sh
scripts/ios/test-sync.sh
scripts/ios/test-performance.sh
scripts/ios/archive.sh
scripts/ios/validate-release.sh
```

Scripts accept destinations and identifiers through environment variables; no
personal Team ID or signing secret is committed.

## Dependency Order

```text
Step 0.1 project
  -> Step 0.2 shared-package compile
  -> Step 0.3 editor spike
  -> Step 0.4 system-surface spikes
  -> Step 1 persistence and sync
  -> Step 2 app shell and note lifecycle
  -> Step 3 editor parity and modes
  -> Step 4 capture and import
  -> Step 5 search, timer, and OCR
  -> Step 6 export, backup, settings, privacy, accessibility
  -> Step 7 hardening and App Store release
```

Step 1 sync can overlap late Step 0.3 work after the schema and repository
protocols are stable. No later step may bypass a failed spike by introducing a
second implementation path.

## Step 0.1 - Create The iOS Project

Status: `BLOCKED` until macOS Step 0.1 is `DONE`.

Requirements:

- `FR-IOS-REL-001`
- `FR-IOS-DATA-001`

Tasks:

1. Add the iOS app, share extension, widgets, unit-test, UI-test, and
   performance-test targets to `project.ios.yml`.
2. Set iOS 17.0 and `TARGETED_DEVICE_FAMILY = 1`.
3. Add `.xcconfig` placeholders for bundle IDs, App Group, CloudKit container,
   and signing team.
4. Add App Group, iCloud/CloudKit, Live Activities, and notification
   capabilities to the owning targets only.
5. Add privacy manifests and camera/photo-library purpose strings.
6. Add the iOS build/test/archive scripts.
7. Add CI jobs for shared packages and an unsigned simulator build.
8. Record the current Xcode, Swift, SDK, App Store submission, and
   required-reason API requirements in the step report.

Deliverables:

- reproducible iOS project;
- empty app, share extension, and widget targets compile;
- CI simulator build;
- entitlement ownership table;
- no secret or personal identifier in Git.

Tests:

- clean-checkout generation;
- Debug simulator build;
- Release unsigned simulator build;
- generated-project no-diff check;
- entitlement inspection.

Exit criteria:

- project regeneration is deterministic;
- each capability exists on only the targets that need it;
- the empty iPhone app launches on the baseline simulator;
- App Store validation finds no malformed bundle relationship.

Estimated effort: 1-2 days.

## Step 0.2 - Prove Shared Package Portability

Status: `BLOCKED` until Step 0.1.

Requirements:

- shared `FR-NOTE-*`, `FR-EDIT-*`, `FR-CLIP-*`, `FR-CMD-*`, `FR-LIST-*`,
  `FR-MATH-*`, `FR-TIME-*`, `FR-OCR-*`, and `FR-EXP-*`.

Tasks:

1. Add iOS 17 platform declarations to shared package manifests.
2. Remove accidental AppKit imports from Core, Modes, Persistence, Design, and
   protocol-only Integrations targets.
3. Inject clocks, locale, file locations, paste input, notifications, OCR, and
   export adapters.
4. Run all parser, state-machine, projection, persistence, and migration suites
   on an iOS simulator destination.
5. Produce a package API report showing which types are shared and which remain
   platform adapters.

Deliverables:

- all shared packages compile for macOS and iOS;
- no `#if os(iOS)` in Core or Modes;
- shared test suites run on iOS;
- portability report.

Exit criteria:

- no duplicate parser or state-machine implementation exists;
- shared behavior fixtures produce identical results on macOS and iOS;
- Swift 6 concurrency checks pass.

Estimated effort: 2-4 days.

## Step 0.3 - iOS Editor Projection Spike

Status: `BLOCKED` until Step 0.2.

Requirements:

- `FR-IOS-EDIT-001`
- `FR-IOS-NAV-001`
- `FR-IOS-A11Y-001`

Tasks:

1. Build a `UITextView` + TextKit 2 host with source versioning.
2. Implement fake result, shortened-link, and checkbox decorations.
3. Evaluate overlay, layout-fragment, and attachment-backed rendering.
4. Implement source-coordinate copy, selection, undo, marked text, and stale
   projection rejection.
5. Add the paging coordinator with the architecture constants.
6. Exercise Dynamic Type, VoiceOver, Reduce Motion, RTL, Emoji, Chinese IME,
   combining marks, and long notes.
7. Record one renderer decision with rejected alternatives and measured costs.

Tests:

- macOS Step 0.3 mandatory fixtures on iOS;
- `ET-IOS-EDIT-001A` through `ET-IOS-EDIT-001H`;
- `ET-IOS-NAV-001A` through `ET-IOS-NAV-001H`;
- 100 property-test seeds with 10,000 edits each;
- Instruments typing and allocation trace.

Exit criteria:

- persisted source remains byte-for-byte independent of decoration rendering;
- no gesture begins during marked text, selection handles, link menus, or
  horizontal code scroll;
- one action equals one undo group;
- p95 synchronous typing work is under 4 ms on the baseline device;
- the renderer decision is recorded before Step 2.

Estimated effort: 5-8 days.

## Step 0.4 - System Surface Feasibility Spikes

Status: `BLOCKED` until Step 0.1; may run beside Step 0.3.

Requirements:

- `FR-IOS-CAP-001` through `FR-IOS-CAP-003`
- `FR-IOS-IMP-001` through `FR-IOS-IMP-003`
- `FR-IOS-TIME-001`
- `FR-IOS-OCR-001`
- `FR-IOS-PRIV-001`

Build isolated prototypes for:

1. `CaptureNoteIntent` opening the app with one idempotent payload on iOS 17
   and the current shipping iOS.
2. Lock Screen/Home Screen widgets and iOS 18 Control opening the same route.
3. Share extension atomic file staging and app import after process death.
4. `UIPasteControl` delivery without a pre-read.
5. Read-only Live Activity timestamp display, stale state, deep-link open, and
   local-notification completion.
6. `DataScannerViewController` support/availability checks and fallback.
7. Core Spotlight opt-in, purge, outbox retry, and reconciliation.

Exit criteria:

- every 1.0 surface has a proven fallback on unsupported hardware or OS;
- no extension or widget opens SQLite;
- no pasteboard content is read before user action;
- Live Activity behavior remains correct with the app terminated;
- a failed optional surface does not block Home Screen capture.

Estimated effort: 5-7 days.

## Step 1 - Persistence, Migration, And CloudKit Sync

Status: `BLOCKED` until Steps 0.2 and 0.4.

Requirements:

- `FR-IOS-DATA-001`
- `FR-IOS-SYNC-001`
- `FR-IOS-BACK-001`

Tasks:

1. Add `ingested_payload`, `spotlight_outbox`, and `sync_metadata`
   migrations.
2. Implement hybrid logical clocks and deterministic serialization.
3. Implement the private CloudKit custom zone with `CKSyncEngine`.
4. Sync note content, promotion time, expiration policy, and tombstones.
5. Keep selection, scroll, timers, notifications, and presentation local.
6. Implement concurrent-body recovery-note creation.
7. Implement concurrent deletion/edit recovery behavior.
8. Implement local-only mode, later iCloud enablement, account loss, and
   account replacement confirmation.
9. Implement backup restore as merge/import when sync is enabled.
10. Implement 400-day tombstone retention and the 365-day offline-client
    re-bootstrap with safety backup and recovered-note import.
11. Add a development CloudKit container and scripted schema deployment; do
    not deploy production schema until fixtures pass.

Tests:

- `IT-IOS-DATA-001A` through `IT-IOS-DATA-001F`;
- `IT-IOS-SYNC-001A` through `IT-IOS-SYNC-001O`;
- two-device physical test;
- offline edit on both devices then reconnect;
- clock skew forward/backward;
- edit/edit, edit/delete, expiration/edit, and promote/edit conflicts;
- local-only enablement with existing remote data;
- iCloud account loss and replacement;
- restore merge with newer remote records;
- 364-day retained-tombstone replay and 366-day forced re-bootstrap;
- tombstone compaction after 400 days;
- schema migration from the latest macOS release candidate.

Exit criteria:

- every conflict preserves user-authored text;
- duplicate replay is idempotent;
- a device can remain offline for seven days and converge after reconnect;
- account loss never deletes local notes;
- local-only mode passes all non-sync workflows;
- public iOS release remains blocked until this step is `DONE`.

Estimated effort: 8-12 days.

## Step 2 - App Shell And Note Lifecycle

Status: `BLOCKED` until Steps 0.3 and 1.

Requirements:

- `FR-IOS-CAP-001`
- `FR-IOS-NAV-001`
- `FR-IOS-LIFE-001`
- shared `FR-NOTE-001` through `FR-NOTE-006`, `FR-NOTE-009`,
  `FR-NOTE-010`.

Tasks:

1. Build the SwiftUI app shell around the UIKit editor.
2. Implement ordinary launch resume/new policy.
3. Implement fresh transient capture route.
4. Implement next/previous paging, newest-edge creation, blank discard,
   jump-to-front, promote, delete, expiration, and bulk deletion.
5. Keep essential toolbar actions available while the keyboard is visible.
6. Persist selection and scroll restoration per device.
7. Write the share-target snapshot after active-note changes.

Exit criteria:

- all note lifecycle transitions match shared requirements;
- foreground/background transitions never create notes;
- explicit capture creates exactly one transient note;
- destructive actions have the required confirmation and backup behavior.

Estimated effort: 5-7 days.

## Step 3 - Editor Parity And Modes

Status: `BLOCKED` until Step 2.

Requirements:

- `FR-IOS-EDIT-001`
- `FR-IOS-A11Y-001`
- shared editor, clipboard, command, list, math, Markdown, code, link, and
  find/replace requirements.

Tasks:

1. Promote the selected spike renderer into `ForNowEditorIOS`.
2. Implement normal/raw paste, clean copy, contextual copy, links, Markdown,
   code mode, and find/replace.
3. Add slash suggestions as an input accessory.
4. Integrate list, math, aggregate, unit, currency, and variable engines.
5. Add tappable and VoiceOver-accessible checkbox/result/link decorations.
6. Generate the iOS hardware-keyboard table from the command registry.
7. Run every shared behavior fixture on device.

Exit criteria:

- shared feature suites pass without iOS-specific parser forks;
- VoiceOver can invoke every decoration action;
- large Dynamic Type sizes do not hide editor or essential controls;
- no decoration enters persisted source.

Estimated effort: 8-12 days.

## Step 4 - Capture And Import

Status: `BLOCKED` until Steps 0.4 and 2.

Requirements:

- `FR-IOS-CAP-001` through `FR-IOS-CAP-003`
- `FR-IOS-IMP-001` through `FR-IOS-IMP-003`
- `FR-IOS-DATA-001`

Tasks:

1. Implement Home Screen icon and quick action first.
2. Add App Shortcuts/Siri and supported Action Button binding.
3. Add Lock Screen/Home Screen widgets.
4. Add iOS 18 Control Center control behind availability checks.
5. Implement share extension text, URL, and image staging.
6. Implement stable target note snapshot and create-new fallback.
7. Implement `UIPasteControl` banner.
8. Import staged payloads in stable order with receipt-based idempotency.
9. Add visible import results and quarantine diagnostics.

Exit criteria:

- every available capture path reaches the same ready state;
- unsupported surfaces disappear without breaking capture;
- 100 queued imports preserve order and apply once;
- a deleted append target creates a new note and reports the fallback;
- no extension process reads note bodies or opens SQLite.

Estimated effort: 6-9 days.

## Step 5 - Search, Timer, And OCR

Status: `BLOCKED` until Steps 3 and 4.

Requirements:

- `FR-IOS-SRCH-001`
- `FR-IOS-TIME-001`
- `FR-IOS-OCR-001`
- `FR-IOS-PRIV-001`

Tasks:

1. Implement explicit toolbar search and shared search-result semantics.
2. Add opt-in Core Spotlight indexing, purge, outbox worker, and
   reconciliation.
3. Add timer command integration, local notifications, and read-only Live
   Activity.
4. Route Live Activity taps to the exact timer in the app.
5. Add live camera OCR where supported and still-image/document fallback.
6. Keep OCR cancellation and insertion atomic.

Exit criteria:

- Spotlight is empty before opt-in and after purge;
- outbox crash fixtures converge without exposing deleted notes;
- timer remains timestamp-correct after termination, sleep, reboot, and clock
  change;
- unavailable live scanning always has a working fallback;
- OCR produces no network traffic.

Estimated effort: 6-8 days.

## Step 6 - Export, Backup, Settings, Privacy, And Accessibility

Status: `BLOCKED` until Step 5.

Requirements:

- `FR-IOS-EXP-001`
- `FR-IOS-BACK-001`
- `FR-IOS-UI-001`
- `FR-IOS-A11Y-001`
- `FR-IOS-PRIV-001`
- `FR-IOS-REL-001`

Tasks:

1. Present canonical exports through share sheet and Files destinations.
2. Implement the safe iOS URL-route subset and callback allowlist.
3. Implement automatic local backups and Files-based export/restore.
4. Implement built-in themes, paper styles, Dynamic Type, Reduce Motion,
   Reduce Transparency, Increase Contrast, and RTL.
5. Implement Spotlight, notification, camera, and iCloud settings with
   just-in-time permission explanations.
6. Add preference reset and redacted diagnostics export.
7. Audit every Lock Screen, widget, Live Activity, notification, and App Entity
   field for note-body leakage.
8. Complete VoiceOver, Switch Control, hardware keyboard, and content-size
   manual matrices.

Exit criteria:

- backup and restore pass with sync on and off;
- invalid URL routes never mutate data;
- reset preserves notes and backups;
- diagnostics contain no user content or secrets;
- accessibility audit has no P0/P1 issue;
- privacy manifest and App Privacy answers match observed behavior.

Estimated effort: 6-9 days.

## Step 7 - Hardening And App Store Release

Status: `BLOCKED` until Steps 1 through 6 are `DONE`.

Requirements:

- every iOS 1.0 requirement except post-1.0 `FR-IOS-EXT-001`.

Tasks:

1. Run the complete unit, integration, editor, UI, performance, privacy,
   accessibility, fault, and sync matrices.
2. Run seven-day offline sync and 24-hour timer soaks.
3. Test low storage, disk full, denied permissions, iCloud disabled, account
   change, and network loss.
4. Test upgrade from the previous macOS release and every iOS release
   candidate schema.
5. Archive with distribution signing and run App Store validation.
6. Complete privacy labels, export compliance, support URL, privacy policy,
   review notes, screenshots, and TestFlight metadata.
7. Run TestFlight on the baseline and current physical devices.
8. Freeze the production CloudKit schema only after migration rehearsal.
9. Create rollback, kill-switch, support, and data-recovery runbooks.

Release gate:

1. `traceability.yml` has no missing iOS 1.0 requirement or test.
2. Step 1 sync is `DONE`.
3. No P0/P1 issue is open.
4. Physical-device editor, capture, camera, notification, Live Activity, and
   sync cells pass.
5. Offline local-only mode passes.
6. Backup restore and sync-merge rehearsal passes.
7. Privacy and accessibility audits pass.
8. App Store validation passes with the production entitlements.
9. JavaScript extensions remain absent from the 1.0 binary.

Estimated effort: 5-8 days plus TestFlight observation time.

## Schedule

For one experienced iOS engineer after the shared macOS packages are stable:

- Steps 0.1-0.4: 2.5-3.5 weeks;
- Step 1: 2-2.5 weeks;
- Steps 2-4: 3.5-5 weeks;
- Steps 5-6: 2.5-4 weeks;
- Step 7: 1.5-2.5 weeks plus TestFlight.

Planning range: **12-17 weeks**. Shared-package defects, CloudKit conflict
findings, editor rendering changes, and App Store policy changes can extend the
range; none justify removing a release gate.
