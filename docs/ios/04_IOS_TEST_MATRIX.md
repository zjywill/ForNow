# ForNow iOS Test Matrix

Mirrors `../04_TEST_MATRIX.md`. Test ID prefixes are shared: `UT` unit,
`ET` editor/UI-edge, `IT` integration, `UIT` UI test, `MT` manual,
`PT` performance, `ST` security/privacy. iOS IDs carry an `IOS` infix
(example: `UT-IOS-CAP-001A`).

## 1. Rules

- Every `FR-IOS-*` maps to at least one automated test or an explicit
  manual entry.
- Shared behavior (parsers, math, modes, persistence) is verified by the
  macOS matrix running against the shared packages on iOS destinations;
  do not duplicate those cases here.
- Every manual test lists device, OS version, and prerequisite state.

## 2. Capture

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-CAP-001` | `UIT-IOS-CAP-001A` through `UIT-IOS-CAP-001D` | Ready state from every surface; no interstitial |
| `FR-IOS-CAP-002` | `UIT-IOS-CAP-002`, `MT-IOS-CAP-002A`, `MT-IOS-CAP-002B` | Lock Screen and Home widget open transient note; iOS 17 fallback without Control |
| `FR-IOS-CAP-003` | `UT-IOS-CAP-003A` through `UT-IOS-CAP-003C`, `MT-IOS-CAP-003` | Intent with/without content; Siri and Action Button manual runs |

## 3. Import

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-IMP-001` | `IT-IOS-IMP-001A` through `IT-IOS-IMP-001D`, `MT-IOS-IMP-001` | Text/URL/image staging; extension never opens database |
| `FR-IOS-IMP-002` | `UT-IOS-IMP-002A` through `UT-IOS-IMP-002C`, `ET-IOS-IMP-002` | Metadata-only pre-consent; one undo group; suppression after same changeCount |
| `FR-IOS-IMP-003` | `UT-IOS-IMP-003A` through `UT-IOS-IMP-003D` | Normalization pipeline and formatting policy shared with paste |

Inbox fault fixtures:

- kill app between stage and import -> exactly-once application;
- malformed descriptor -> quarantine, no crash, no content in logs;
- 100 staged payloads -> order-stable, all applied;
- image payload routes to OCR queue only in the app process.

## 4. Navigation And Editor

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-NAV-001` | `ET-IOS-NAV-001A` through `ET-IOS-NAV-001E`, `MT-IOS-NAV-001` | Swipe boundaries, transient lifecycle, promote/delete parity, hardware-keyboard table |
| `FR-IOS-EDIT-001` | macOS Step 0.3 fixture set on iOS + `ET-IOS-EDIT-001A` through `ET-IOS-EDIT-001D` | Source integrity, projection versioning, undo, IME/Emoji |

Property tests: the macOS editor mutation suite (10,000 operations per
seed, 100 seeds) runs against `ForNowEditorIOS` before iOS 1.0.

## 5. Search

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-SRCH-001` | `UT-IOS-SRCH-001A` through `UT-IOS-SRCH-001C`, `MT-IOS-SRCH-001` | In-app parity; Spotlight upsert/remove in same transaction; reconciliation after external deletion |

## 6. Timer And Live Activity

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-TIME-001` | `UT-IOS-TIME-001A` through `UT-IOS-TIME-001D`, `MT-IOS-TIME-001A` through `MT-IOS-TIME-001C` | Register/update/end on transitions; buttons hit state machine; relaunch and termination reconciliation; stale cleanup |

Manual cells: app terminated mid-countdown, device reboot mid-countdown,
Dynamic Island compact/expanded/minimal presentations, Lock Screen
presentation.

## 7. OCR And Camera

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-OCR-001` | `UT-IOS-OCR-001A` through `UT-IOS-OCR-001C`, `MT-IOS-OCR-001A`, `MT-IOS-OCR-001B`, `ST-IOS-OCR-001` | Live text and document scan insertion; cancellation; no network traffic |

## 8. Data And App Group

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-DATA-001` | `IT-IOS-DATA-001A` through `IT-IOS-DATA-001D`, `ST-IOS-DATA-001` | Single store; idempotent import; snapshot versioning; file-protection behavior |

| `FR-IOS-A11Y-001` | `MT-IOS-A11Y-001A`, `MT-IOS-A11Y-001B` | Dynamic Type scaling; VoiceOver actions on every decoration |

## 9. Performance

- `PT-IOS-001` cold launch to interactive under 600 ms (oldest matrix
  device);
- `PT-IOS-002` capture-to-keyboard p95 under 400 ms warm;
- `PT-IOS-003` typing synchronous work p95 under 4 ms;
- `PT-IOS-004` share extension staged under 1 s and under 120 MB;
- `PT-IOS-005` widget snapshot write under 50 ms off-main.

## 10. Soak And Fault Tests

- 24-hour timer + Live Activity soak; no unbounded updates or memory
  growth;
- 1,000 capture open/dismiss cycles; no leaked windows or keyboard
  failures;
- background/foreground churn during import, OCR, and search;
- low-storage and disk-full inbox staging;
- no-network run of every core workflow.

## 11. Test Environments

- Oldest supported iPhone on iOS 17.0 (baseline device);
- current iPhone Pro on latest iOS (Action Button, Dynamic Island);
- iOS 18 device for Control Center control;
- one device with iCloud disabled and network disabled.

## 12. Completion Definition

iOS 1.0 is test-complete when:

1. every `FR-IOS-*` has a passing mapped test;
2. the shared-package suites pass on iOS destinations in CI;
3. the editor property suite passes on device, not only simulator;
4. all manual cells are recorded in `docs/progress/`;
5. no P0/P1 defect is open.

## 13. Extensions (Post-1.0)

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-IOS-EXT-001` | `UT-IOS-EXT-001A` through `UT-IOS-EXT-001C`, `MT-IOS-EXT-001` | Shared runtime passes macOS extension suites on iOS; palette presentation; app-process-only networking |

The macOS extension suites (section 19 of `../04_TEST_MATRIX.md`) run
against the shared extension runtime package on iOS destinations.
