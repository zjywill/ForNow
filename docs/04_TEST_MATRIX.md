# ForNow Test Matrix

## 1. Rules

1. Every implemented `FR-*` has at least one automated test.
2. AppKit, Space, full-screen, permission, and release behavior also has a
   documented manual test.
3. Test names include the requirement ID.
4. A bug fix adds a regression test before the issue is closed.
5. Fixtures contain no private user notes or copyrighted AntiNote content.
6. UI screenshots use original ForNow visuals.

Test categories:

- `UT`: pure unit test;
- `IT`: integration test;
- `ET`: editor/AppKit integration test;
- `UIT`: UI automation;
- `MT`: manual platform test;
- `PT`: performance test;
- `ST`: security/privacy test;
- `SOAK`: long-running reliability test.

## 2. Window And Invocation

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-WIN-001` | `UT-WIN-001`, `IT-WIN-001`, `MT-WIN-001` | Option-A default, register, toggle, conflict, customize, macOS 15.0/15.1 diagnostic |
| `FR-WIN-002` | `UT-WIN-002`, `UIT-WIN-002`, `MT-WIN-002` | Dock/Menu/Both/Neither, dropdown size, in-app commands, note preservation |
| `FR-WIN-003` | `UT-WIN-003`, `UIT-WIN-003`, `MT-WIN-003` | Command-P, pin, focus loss, suspension tokens, owned panels |
| `FR-WIN-004` | `MT-WIN-004A` through `MT-WIN-004H` | Displays, Spaces, full screen, Stage Manager, every mode |
| `FR-WIN-005` | `UIT-WIN-005A`, `UIT-WIN-005B`, `IT-WIN-005` | Command-W, Command-O, global toggle, flush before hide |

Required manual matrix dimensions:

```text
Display: single | dual
Space: same | different
Foreground app: windowed | full screen
ForNow mode: standard | pseudo menu | dropdown
Pin: off | on
Auto-hide: off | on
Owned panel: none | settings | save panel | permission panel
```

The supported combinations must be listed explicitly; unsupported combinations
must show deterministic behavior rather than silently failing.

## 3. Notes

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-NOTE-001` | `UT-NOTE-001`, `IT-NOTE-001` | Stable UUID across edit, promote, export, backup restore |
| `FR-NOTE-002` | `UT-NOTE-002A` through `UT-NOTE-002F`, `IT-NOTE-002` | Blank, whitespace, IME, undo-to-blank, first durable edit |
| `FR-NOTE-003` | `UT-NOTE-003`, `UIT-NOTE-003`, `ET-NOTE-003` | Command brackets, previous/next, boundaries, swipe, directional cursor entry |
| `FR-NOTE-004` | `UT-NOTE-004`, `IT-NOTE-004A`, `IT-NOTE-004B` | Command-1, Command-Shift-1, monotonic promotion, ties, concurrency |
| `FR-NOTE-005` | `UIT-NOTE-005A`, `UIT-NOTE-005B`, `IT-NOTE-005` | Cancel, confirm, suppressed warning, backup recovery |
| `FR-NOTE-006` | `UT-NOTE-006A` through `UT-NOTE-006E`, `IT-NOTE-006` | Today/week/month/year/never, idempotency, clock changes, launch |
| `FR-NOTE-007` | `UT-NOTE-007`, `IT-NOTE-007`, `UIT-NOTE-007` | Command-F, empty/text query, arrows, Enter promote, Escape |
| `FR-NOTE-008` | `UT-NOTE-008A` through `UT-NOTE-008G`, `ET-NOTE-008` | All match modes, regex error, zero length, replace undo |
| `FR-NOTE-009` | `UT-NOTE-009A` through `UT-NOTE-009F`, `IT-NOTE-009` | Launch, duration thresholds, close timestamp, note count |
| `FR-NOTE-010` | `UT-NOTE-010A` through `UT-NOTE-010F`, `IT-NOTE-010`, `UIT-NOTE-010` | Cutoff preview, exact predicate, safety backup, cancel, backup failure |

Required text fixtures:

- empty string;
- spaces, tabs, and newlines;
- Simplified and Traditional Chinese;
- Japanese and Korean;
- Latin combining marks;
- Emoji and ZWJ sequences;
- right-to-left sample;
- 50,000-character note;
- duplicate first lines;
- URL-only note;
- keyword-only note.

## 4. Editor

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-EDIT-001` | `UT-EDIT-001`, `ET-EDIT-001`, `IT-EDIT-001` | Source contains no visual result/control artifact |
| `FR-EDIT-002` | `UT-EDIT-002A` through `UT-EDIT-002F`, `ET-EDIT-002` | Range mapping, stale projection rejection, selection stability |
| `FR-EDIT-003` | `UT-EDIT-003A` through `UT-EDIT-003J`, `ET-EDIT-003` | Exact subset, Command-slash, exclusions, unsupported syntax unchanged |
| `FR-EDIT-004` | `UT-EDIT-004A` through `UT-EDIT-004L`, `ET-EDIT-004` | Caret exit, duplicates, toggle, copy, auto-shortening off, all links off |
| `FR-EDIT-005` | `ET-EDIT-005A` through `ET-EDIT-005H` | Type, paste, checkbox, OCR, replace-all, parser no-op |
| `FR-EDIT-006` | `ET-EDIT-006A` through `ET-EDIT-006G` | IME marked text, Emoji, composed text, UTF-16 bounds |
| `FR-EDIT-007` | `UT-EDIT-007`, `ET-EDIT-007` | Forced RTL/LTR presentation, source unchanged |

Property tests:

- Generate random valid source strings.
- Generate random insert/delete/replace mutations.
- Reparse and apply decorations.
- Assert source equality with the editor's exported source.
- Assert selection remains in bounds.
- Undo every operation and assert the original source.
- Redo every operation and assert the final source.
- Run 10,000 operations per seed across at least 100 seeds before release.

## 5. Clipboard

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-CLIP-001` | `UT-CLIP-001A` through `UT-CLIP-001E`, `ET-CLIP-001` | Selection, inline code, block code, result, whole note |
| `FR-CLIP-002` | `UT-CLIP-002A` through `UT-CLIP-002F` | Header/title, checklist trigger, full URL, whitespace |
| `FR-CLIP-003` | `UT-CLIP-003A` through `UT-CLIP-003J`, `ET-CLIP-003` | Each transform alone and combined |
| `FR-CLIP-004` | `UT-CLIP-004`, `ET-CLIP-004` | Raw path bypasses optional transforms |

Paste source fixtures:

- Safari HTML;
- Chrome HTML;
- Notes rich text;
- Word rich text;
- Excel/Numbers cells;
- terminal text with tabs;
- IDE text with leading indentation;
- Markdown bullets and numbered lists;
- CRLF input;
- empty and binary-only pasteboard.

## 6. Commands And Lists

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-CMD-001` | `UT-CMD-001A` through `UT-CMD-001G` | Canonical IDs, aliases, one main alias, conflicts, keyword master switch |
| `FR-CMD-002` | `UT-CMD-002A` through `UT-CMD-002G`, `ET-CMD-002` | Header, title, invalid keyword, case-insensitive matching, removal, undo |
| `FR-CMD-003` | `UT-CMD-003`, `UIT-CMD-003`, `MT-CMD-003` | Slash eligibility, filter, number, replace, VoiceOver |
| `FR-CMD-004` | `UT-CMD-004A` through `UT-CMD-004D`, `ET-CMD-004` | Language header, default language, indent stripping and links disabled |
| `FR-LIST-001` | `UT-LIST-001A` through `UT-LIST-001F` | Empty, comment, headings, ordinary items, math disabled |
| `FR-LIST-002` | `UT-LIST-002`, `ET-LIST-002A`, `ET-LIST-002B` | Pointer/keyboard parity, undo, caret stability |
| `FR-LIST-003` | `UT-LIST-003A` through `UT-LIST-003E` | Custom marker, source mutation, clean copy, settings change preserves source |

## 7. Math

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-MATH-001` | `UT-MATH-001A` through `UT-MATH-001Z`, `PT-MATH-001` | Syntax, precedence, diagnostics, locales, digits 0-7, grouping toggle |
| `FR-MATH-002` | `UT-MATH-002A` through `UT-MATH-002J` | Sum, average, count, comments, blanks, fractions |
| `FR-MATH-003` | `UT-MATH-003A` through `UT-MATH-003N` | Categories, aliases, symbols, incompatible, composition |
| `FR-MATH-004` | `UT-MATH-004A` through `UT-MATH-004N`, `IT-MATH-004`, `ST-MATH-004` | Primary symbol/currencies, daily refresh, stale cache, custom rate, privacy |
| `FR-MATH-005` | `UT-MATH-005A` through `UT-MATH-005M`, `ET-MATH-005` | Graph, update, cycle, duplicate, autocomplete, units dropped |
| `FR-MATH-006` | `ET-MATH-006A`, `ET-MATH-006B`, `MT-MATH-006` | Pointer copy, keyboard copy, VoiceOver result |

Mandatory parser fixture groups:

- integers and decimals;
- unary and binary operators;
- alternate multiply/divide symbols;
- parentheses and precedence;
- percentages;
- roots and logarithms;
- floor and ceiling;
- factorial boundary;
- division by zero;
- overflow and precision;
- decimal comma;
- unsupported spaced thousands;
- prose surrounding numbers;
- assignments with spaces;
- forward/back references according to policy;
- dependency cycle;
- all unit categories;
- ISO currency codes and configured symbols;
- offline/stale currency rates.

Golden expected outputs must include:

- canonical numeric value;
- formatted display;
- source range;
- diagnostic code;
- dependency IDs;
- copied result text.

## 8. Timers

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-TIME-001` | `UT-TIME-001A` through `UT-TIME-001L`, `IT-TIME-001` | All commands, persisted timestamps, relaunch |
| `FR-TIME-002` | `UT-TIME-002A` through `UT-TIME-002N`, `ET-TIME-002` | Every state transition, repeated command, click/Escape |
| `FR-TIME-003` | `IT-TIME-003A` through `IT-TIME-003J`, `UIT-TIME-003`, `MT-TIME-003` | Quit, menu bar, countdown/break notification, sound, takeover, volume |

Clock scenarios:

- normal progression;
- system sleep;
- wall clock forward;
- wall clock backward;
- time-zone change;
- process quit while running;
- forced termination;
- day boundary;
- timer completion while app hidden.

## 9. OCR

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-OCR-001` | `UT-OCR-001`, `IT-OCR-001A` through `IT-OCR-001F` | Formats, size limit, unsupported, drag/drop, paste |
| `FR-OCR-002` | `IT-OCR-002`, `ST-OCR-001`, `ST-OCR-002`, `MT-OCR-002` | Local Vision, language, empty image, no network |
| `FR-OCR-003` | `ET-OCR-003A` through `ET-OCR-003E` | Captured position, stale position, cancel, one undo |

Fixtures:

- clear English;
- clear Simplified Chinese;
- mixed language;
- rotated;
- low contrast;
- empty image;
- static GIF;
- animated GIF rejection or first-frame policy;
- malformed and unsupported input;
- 20 MiB encoded-size and 40 megapixel limits;

## 10. AutoPaste

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-AUTO-001` | `UT-AUTO-001`, `IT-AUTO-001`, `UIT-AUTO-001` | Start and all stop paths, visible indicator |
| `FR-AUTO-002` | `UT-AUTO-002A` through `UT-AUTO-002F`, `SOAK-AUTO-002` | Change count, dedupe, self-loop, bounded history |
| `FR-AUTO-003` | `UT-AUTO-003A` through `UT-AUTO-003H` | Default/custom delimiter and policy formatting |

Privacy assertions:

- monitor service has zero polling activity while inactive;
- no captured history exists outside note content;
- logs contain no clipboard text;
- destination deletion stops observation.

## 11. Export And Backup

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-EXP-001` | `UT-EXP-001A` through `UT-EXP-001F` | Canonical payload, title, keyword, links, list triggers |
| `FR-EXP-002` | `IT-EXP-002A` through `IT-EXP-002H`, `ST-EXP-002` | TXT, MD, ZIP, atomic write, overwrite, filenames |
| `FR-EXP-003` | `UT-EXP-003`, `IT-EXP-003A` through `IT-EXP-003F` | Destination URLs, missing app, failure preserves note |
| `FR-EXP-004` | `UT-EXP-004A` through `UT-EXP-004J`, `IT-EXP-004`, `ST-EXP-004` | Placeholders, query/path encoding, allowlist, size, invalid template |
| `FR-BACK-001` | `IT-BACK-001A` through `IT-BACK-001L`, `SOAK-BACK-001` | Every frequency, retention, reveal folder, integrity, disk full, concurrency |
| `FR-BACK-002` | `IT-BACK-002A` through `IT-BACK-002H`, `MT-BACK-002` | Validate, emergency backup, replace, migrate, rollback |

Backup release rehearsal:

1. Create 100 notes with known checksums.
2. Create backup.
3. Modify, delete, and reorder notes.
4. Restore backup.
5. Verify IDs, bodies, order, settings compatibility, and FTS.
6. Intentionally fail restore halfway.
7. Verify emergency rollback.
8. Preserve all generated logs without note bodies.

## 12. Appearance And Accessibility

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-UI-001` | `UT-UI-001`, `UIT-UI-001`, `MT-UI-001` | Independent light/dark selection, semantic tokens, contrast |
| `FR-UI-002` | `UIT-UI-002A` through `UIT-UI-002J`, `MT-UI-002` | Paper/opacity choices, list spacing, macOS 15+, 0-90, reduced transparency |
| `FR-UI-003` | `UT-UI-003`, `UIT-UI-003`, `MT-UI-003` | XS-XL, double size, zoom keys, conflicts, longest labels |
| `FR-UI-004` | `UT-UI-004A` through `UT-UI-004F`, `IT-UI-004`, `ST-UI-004` | 1.x schema, directory, reload, invalid quarantine, built-in fallback |

Accessibility manual paths:

- invoke and dismiss;
- navigate and create;
- search and promote;
- slash picker;
- checkbox;
- math result;
- timer;
- OCR progress/error;
- AutoPaste status;
- export;
- settings;
- destructive confirmation;
- backup restore.

Each path is tested with:

- keyboard only;
- VoiceOver;
- Reduce Motion;
- Reduce Transparency;
- Increase Contrast;
- 200% effective text size.

## 13. URL And Security

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-URL-001` | `UT-URL-001A` through `UT-URL-001H`, `IT-URL-001`, `ST-URL-001` through `ST-URL-004` | Every route, exact decoding, limits, invalid UUID, no mutation |
| `FR-URL-002` | `UT-URL-002A` through `UT-URL-002F`, `IT-URL-002`, `ST-URL-005` | Callback fields/allowlist/size, disabled reload, integrity check |
| `FR-INT-001` | `IT-INT-001A` through `IT-INT-001E`, `ST-INT-001` | 1.x create/search/pin, no DB access, compatibility, uninstall |

Additional tests:

- `ST-URL-001`: unknown route.
- `ST-URL-002`: invalid percent encoding.
- `ST-URL-003`: oversized content.
- `ST-URL-004`: invalid UUID.
- `ST-URL-005`: unapproved callback scheme.
- `ST-URL-006`: path traversal in export filename.
- `ST-URL-007`: script-like payload remains inert text.
- `ST-LOG-001`: note text absent from logs.
- `ST-KEY-001`: secrets absent from UserDefaults and logs.
- `ST-NET-001`: no request during offline core workflow.
- `ST-CLIP-001`: inactive monitor performs no reads.
- `ST-OCR-001`: OCR produces no network traffic.

## 14. Updates, Distribution, Support, And Privacy

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-UPD-001` | `UT-UPD-001A` through `UT-UPD-001F`, `IT-UPD-001`, `UIT-UPD-001` | Second-launch consent, decline, manual check, separate check/install |
| `FR-SUP-001` | `IT-SUP-001A` through `IT-SUP-001D`, `ST-SUP-001` | Reset preferences, preserve notes/backups, diagnostic launch, private logs |
| `FR-DIST-001` | `IT-DIST-001A` through `IT-DIST-001F`, `MT-DIST-001` | Signed direct install, Homebrew gate, Setapp out of scope, upgrade preservation |
| `FR-PRIV-001` | `ST-PRIV-001A`, `ST-PRIV-001B`, `MT-PRIV-001` | No analytics SDK, no analytics request, network-disabled smoke |

## 15. Performance

| Test | Dataset | Budget |
|---|---|---:|
| `PT-LAUNCH-001` | 1,000 notes | cold ready under 500 ms target |
| `PT-WIN-001` | warm app | hotkey-to-caret p95 under 150 ms |
| `PT-EDIT-001` | 50k characters | synchronous edit p95 under 4 ms |
| `PT-PARSE-001` | 10k math lines | full parse under 150 ms off-main |
| `PT-SEARCH-001` | 100k notes | warm first page under 50 ms target |
| `PT-BACK-001` | 100 MB database | editing remains responsive |
| `PT-MEM-001` | 1,000 notes open session | idle target under 100 MB |
| `PT-TOGGLE-001` | 1,000 toggles | no window or memory accumulation |

Budgets are targets until Phase 0 measures the actual hardware baseline. Any
change requires a written decision, not silent relaxation.

## 16. Soak And Fault Tests

- `SOAK-APP-001`: 24-hour ordinary editing session.
- `SOAK-TIME-001`: 24-hour timer with sleep/wake.
- `SOAK-AUTO-001`: 10,000 distinct clipboard events.
- `SOAK-BACK-001`: backups across retention rollover.
- `FAULT-DB-001`: process kill during pending save.
- `FAULT-DB-002`: process kill during backup.
- `FAULT-DB-003`: disk-full write failure.
- `FAULT-DB-004`: corrupt WAL.
- `FAULT-OCR-001`: cancellation during recognition.
- `FAULT-NET-001`: rate request timeout and malformed response.
- `FAULT-EXP-001`: destination removed during export.

## 17. Release Test Environments

Minimum:

- macOS 14 latest point release available;
- macOS 15.0 and 15.1 through archived hardware/VM evidence or documented
  registration diagnostics;
- macOS 15.2 or newer for restored Option-only shortcut behavior;
- macOS 15 latest for current compatibility;
- macOS 26 latest;
- Apple Silicon;
- Intel through available physical or hosted hardware;
- one and two displays;
- fresh account with no prior preferences;
- upgrade from the previous release candidate;
- network disabled;
- notifications denied;
- accessibility settings enabled.

## 18. Test Completion Definition

The matrix is complete when:

1. every implemented `FR-*` row is green;
2. every manual matrix cell is signed with OS/build/date;
3. all property-test seeds pass;
4. backup rehearsal passes;
5. offline and privacy tests pass;
6. performance budgets pass or have approved exceptions;
7. every fixed P0/P1 issue has a regression test.

## 19. Extensions (Post-1.0)

| Requirement | Test IDs | Minimum verification |
|---|---|---|
| `FR-EXT-001` | `UT-EXT-001A` through `UT-EXT-001E` | Manifest schema, versioning, quarantine, load order, sandbox isolation |
| `FR-EXT-002` | `UT-EXT-002A` through `UT-EXT-002E`, `ET-EXT-002` | Palette filtering, four command types, scope immutability, undo grouping |
| `FR-EXT-003` | `UT-EXT-003A` through `UT-EXT-003F`, `ST-EXT-003` | Placeholder substitution, parsed endpoint and redirect validation, lookalike-host/path escapes, identity spoofing, denied-by-default |
| `FR-EXT-004` | `UT-EXT-004A` through `UT-EXT-004C`, `IT-EXT-004` | MathEvaluator parity with math mode, preferences, service dependencies |

Hostile-extension fixtures:

- scope escape attempts (line-scoped code requesting full text);
- lookalike host, path-boundary escape, endpoint mismatch, and redirect escape;
- identity spoofing of another extension;
- oversized output and infinite loop (execution limits);
- malformed manifest, missing files, undeclared JS files.

Replay fixtures: an identical manifest plus input snapshot must produce
identical source edits across repeated runs and across machines.
