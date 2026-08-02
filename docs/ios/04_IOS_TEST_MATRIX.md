# ForNow iOS Test Matrix

This matrix verifies `02_IOS_REQUIREMENTS.md`. Test prefixes:

- `UT`: unit;
- `ET`: editor and gesture edge;
- `IT`: integration;
- `UIT`: end-to-end UI;
- `MT`: recorded physical-device manual;
- `PT`: performance;
- `ST`: security and privacy;
- `SP`: feasibility spike.

Every ID in this file must also appear under the same requirement in
`traceability.yml`.

## 1. Rules

1. Every iOS 1.0 `FR-IOS-*` has at least one automated test and any required
   physical-device cell.
2. Shared parser, mode, editor-state, persistence, and export behavior runs
   from the macOS matrix against iOS destinations; this file adds
   platform-specific verification.
3. Manual evidence records device model, OS version, app build, locale,
   accessibility settings, permissions, iCloud state, date, and tester.
4. Tests never depend on JavaScript extensions; `FR-IOS-EXT-001` is
   post-1.0 research.
5. Performance failures require an approved exception with captured trace;
   changing the budget silently is not allowed.

## 2. Capture

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-CAP-001` | `UIT-IOS-CAP-001A` through `UIT-IOS-CAP-001D` | Ordinary launch, fresh capture, content capture, required system UI; one ready state and no app interstitial |
| `FR-IOS-CAP-002` | `UIT-IOS-CAP-002`, `MT-IOS-CAP-002A` through `MT-IOS-CAP-002C` | Home/Lock widgets, iOS 18 Control, iOS 17 fallback, locked-device behavior |
| `FR-IOS-CAP-003` | `UT-IOS-CAP-003A` through `UT-IOS-CAP-003C`, `MT-IOS-CAP-003` | Intent decoding, idempotency, Siri/Shortcut/Action Button without duplicate notes |

Required manual cells:

- cold and warm Home Screen launch;
- Lock Screen launch before and after first unlock;
- Action Button-capable device;
- iOS 18+ Control Center;
- Siri disabled and denied;
- capture payload delivered before and after app process launch.

## 3. Import And Paste

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-IMP-001` | `IT-IOS-IMP-001A` through `IT-IOS-IMP-001E` | Text/URL/image staging, stable target ID, deleted-target fallback, no database open, atomic files |
| `FR-IOS-IMP-002` | `UT-IOS-IMP-002A`, `UT-IOS-IMP-002B`, `ET-IOS-IMP-002A`, `ET-IOS-IMP-002B` | `changeCount` suppression, `UIPasteControl`, no pre-read, one undo group |
| `FR-IOS-IMP-003` | `UT-IOS-IMP-003A` through `UT-IOS-IMP-003D` | Shared normalization, prefix/suffix/separator/timestamp, policy version rejection |

Inbox fault fixtures:

- process kill before rename, after rename, after database commit, and before
  staged-file deletion;
- duplicate payload UUID;
- malformed descriptor and path traversal;
- 100 staged payloads with equal timestamps;
- target note deleted or expired before import;
- image payload larger than the accepted decoded-area limit;
- disk full during descriptor or binary write.

## 4. Navigation, Lifecycle, And Editor

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-NAV-001` | `ET-IOS-NAV-001A` through `ET-IOS-NAV-001H` | Threshold, velocity, boundary resistance, transient commit, selection/IME/link/code-scroll conflicts, hardware keys |
| `FR-IOS-EDIT-001` | `ET-IOS-EDIT-001A` through `ET-IOS-EDIT-001H` plus shared Step 0.3 fixtures | Source integrity, stale projection, undo, IME/Emoji, Dynamic Type, RTL, VoiceOver |
| `FR-IOS-LIFE-001` | `UT-IOS-LIFE-001A`, `UT-IOS-LIFE-001B`, `UIT-IOS-LIFE-001A`, `UIT-IOS-LIFE-001B` | Resume/new setting, background churn, explicit fresh capture, expiration/bulk delete |

Property tests:

- 10,000 random editor operations per seed across at least 100 seeds;
- insert/delete/replace around every decoration type;
- undo all then redo all;
- random selection and marked-text ranges remain valid;
- paging recognizer never commits for excluded gesture owners.

## 5. Search

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-SRCH-001` | `UT-IOS-SRCH-001A` through `UT-IOS-SRCH-001C`, `IT-IOS-SRCH-001A`, `IT-IOS-SRCH-001B`, `MT-IOS-SRCH-001` | In-app semantics, default-off index, transactional outbox, retry/reconciliation, purge, direct open without promote |

Spotlight fault points:

- crash before Core Spotlight request;
- request succeeds but app dies before acknowledgement;
- duplicate outbox replay;
- delete arrives before stale upsert;
- opt-out during full rebuild;
- expired note queued for upsert;
- system index cleared externally.

## 6. Timer And Live Activity

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-TIME-001` | `UT-IOS-TIME-001A` through `UT-IOS-TIME-001D`, `MT-IOS-TIME-001A` through `MT-IOS-TIME-001D` | Timestamp display, stale date, read-only activity, deep-link timer ID, notification permission, launch reconciliation |

Manual cells:

- app terminated mid-countdown;
- device reboot mid-countdown;
- clock and timezone change;
- notification denied, scheduled-summary, Focus, and time-sensitive disabled;
- supported Dynamic Island presentations and non-Dynamic-Island Lock Screen;
- tap stale activity after the timer note was deleted.

## 7. OCR And Camera

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-OCR-001` | `UT-IOS-OCR-001A` through `UT-IOS-OCR-001C`, `MT-IOS-OCR-001A` through `MT-IOS-OCR-001C`, `ST-IOS-OCR-001` | Live scanner, unsupported-device fallback, document/still image, cancellation, atomic insertion, no network |

Required fixtures:

- supported and unsupported live-scanner hardware;
- camera denied and restricted;
- rotated, low-light, multilingual, and large images;
- app backgrounded during recognition;
- note edited or deleted before recognition completes.

## 8. Data, Sync, And Backup

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-DATA-001` | `IT-IOS-DATA-001A` through `IT-IOS-DATA-001F`, `ST-IOS-DATA-001` | App-only store, receipt idempotency, snapshot bounds, file protection, quarantine, stable order |
| `FR-IOS-SYNC-001` | `IT-IOS-SYNC-001A` through `IT-IOS-SYNC-001O` | Upload/download, offline replay, edit/edit and edit/delete recovery, tombstone retention/compaction, stale-client re-bootstrap, local-only enablement, account loss/replacement, migration |
| `FR-IOS-BACK-001` | `UT-IOS-BACK-001A`, `IT-IOS-BACK-001A` through `IT-IOS-BACK-001C`, `MT-IOS-BACK-001` | Local backup, Files export/import, checksum/schema validation, safety backup, sync merge restore |

Sync fixture matrix:

- Mac creates, iPhone edits;
- iPhone creates, Mac promotes;
- both edit the same body offline;
- one deletes while the other edits offline;
- expiration races an edit;
- repeated CloudKit event delivery;
- seven days offline then reconnect;
- device wall clock moves backward and forward;
- iCloud unavailable at launch;
- local-only notes merged into a non-empty private database;
- iCloud account removed then restored;
- migration from the latest macOS release candidate.
- 364-day offline replay receives retained tombstones;
- 366-day offline replay performs safety backup, server re-bootstrap, and
  recovered-note import before upload;
- tombstones older than 400 days compact without stale-ID resurrection.

Every concurrent content fixture asserts that all user-authored text survives
either on the original note or a recovered note.

## 9. Appearance And Accessibility

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-A11Y-001` | `MT-IOS-A11Y-001A` through `MT-IOS-A11Y-001D` | VoiceOver actions, Dynamic Type accessibility sizes, Reduce Motion, Reduce Transparency/Increase Contrast |
| `FR-IOS-UI-001` | `UT-IOS-UI-001A`, `UIT-IOS-UI-001A`, `MT-IOS-UI-001A`, `MT-IOS-UI-001B` | Theme/paper persistence, no macOS translucency, system material fallback, iOS-only shortcut table |

Manual accessibility cells include VoiceOver, Switch Control, Full Keyboard
Access, Bold Text, Button Shapes, Reduce Motion, Reduce Transparency, Increase
Contrast, RTL system language, and the largest Dynamic Type size.

## 10. Export, Privacy, And Release

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-EXP-001` | `UT-IOS-EXP-001A`, `UT-IOS-EXP-001B`, `IT-IOS-EXP-001A`, `UIT-IOS-EXP-001A`, `ST-IOS-EXP-001` | Canonical document, share/Files, safe route subset, callback allowlist, malformed/oversized no mutation |
| `FR-IOS-PRIV-001` | `ST-IOS-PRIV-001A` through `ST-IOS-PRIV-001C`, `MT-IOS-PRIV-001` | No analytics, bounded/off-by-default Spotlight, locked-surface redaction, purge |
| `FR-IOS-REL-001` | `IT-IOS-REL-001A`, `IT-IOS-REL-001B`, `ST-IOS-REL-001A`, `MT-IOS-REL-001A`, `MT-IOS-REL-001B` | Upgrade preservation, reset preservation, redacted diagnostics, uninstall warning, App Store validation |

Security fixtures:

- malformed and double-encoded URL parameters;
- unknown route and callback scheme;
- URL credentials, fragments, oversized payload, and invalid note ID;
- diagnostic export after typing unique canary secrets into notes, clipboard,
  URLs, and extension payloads;
- Spotlight opt-out followed by index inspection;
- Lock Screen screenshots with hidden preview settings.

## 11. Performance

- `PT-IOS-001`: cold launch to editable first responder, p95 under 800 ms on
  iPhone XS with the latest available iOS 17 point release;
- `PT-IOS-002`: warm capture route to keyboard requested, p95 under 400 ms;
- `PT-IOS-003`: synchronous typing work, p95 under 4 ms;
- `PT-IOS-004`: share extension cold start to atomic stage under 1 second and
  peak memory under 120 MB;
- `PT-IOS-005`: widget/share-target snapshot write under 50 ms off-main;
- `PT-IOS-006`: 10,000-note in-app search p95 under 150 ms after warm index;
- `PT-IOS-007`: Spotlight outbox drain of 1,000 coalesced operations under
  30 seconds when the system accepts requests;
- `PT-IOS-008`: sync apply of 1,000 downloaded records without main-thread
  stalls over 16 ms.

Each performance run records device, OS, thermal state, battery state, build
configuration, signposts, sample count, p50, p95, and worst value.

## 12. Soak And Fault Tests

- 24-hour timer and read-only Live Activity;
- 1,000 capture open/dismiss cycles;
- 1,000 share payloads across 100 process terminations;
- seven-day offline sync followed by convergence;
- 10,000-note store with expiration, search, backup, and sync active;
- background/foreground churn during import, OCR, indexing, and sync;
- low-storage and disk-full staging, backup, migration, and restore;
- network disabled for every local-only workflow;
- notification, camera, Siri, Spotlight, and iCloud permissions denied.

## 13. Test Environments

Required physical devices:

- iPhone XS on the latest available iOS 17 point release;
- an iPhone supporting Action Button and Dynamic Island on the current shipping
  iOS at release time;
- an iOS 18-or-newer device for Control Center control;
- a device where `DataScannerViewController.isSupported` is false or a
  controlled fallback fixture;
- two devices signed into the same iCloud account for sync;
- one device with iCloud disabled and network disabled.

Required simulators:

- iOS 17 baseline;
- iOS 18;
- current shipping iOS at release time;
- at least one small-screen and one current-screen iPhone configuration.

## 14. Completion Definition

iOS 1.0 is test-complete when:

1. every `release: ios-1.0` entry in `traceability.yml` has passing evidence;
2. all shared-package suites pass on iOS destinations in CI;
3. editor property tests pass on a physical baseline device;
4. all required manual cells are recorded in `docs/progress/`;
5. CloudKit sync and local-only mode both pass;
6. backup restore and sync-merge rehearsal pass;
7. privacy, accessibility, performance, and App Store validation pass;
8. no P0/P1 defect is open;
9. the iOS binary contains no user-installable JavaScript extension runtime.

## 15. Extensions (Post-1.0 Research)

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-EXT-001` | `SP-IOS-EXT-001A`, `SP-IOS-EXT-001B`, `ST-IOS-EXT-001A`, `MT-IOS-EXT-001A` | Runtime termination/memory/scope prototype, structural network checks, App Review assessment |

This row is not part of the iOS 1.0 completion definition. A failed technical
or distribution gate permanently removes the feature from the proposed iOS
release without weakening the macOS extension model.
