# ForNow Implementation Playbook

## How To Use This Document

Execute steps in order. A step is complete only when:

1. all listed deliverables exist;
2. all listed tests pass;
3. the exit criteria are recorded in the step report;
4. referenced AntiNote evidence and ForNow requirements were reviewed;
5. open behavior questions were resolved or explicitly deferred.

Do not begin a later phase merely because the UI looks complete.

## Status Vocabulary

- `BLOCKED`: prerequisite or evidence is missing.
- `READY`: prerequisites are complete.
- `ACTIVE`: implementation is underway.
- `VERIFYING`: code exists and tests/review are running.
- `DONE`: exit criteria passed.

Each step receives a file in `docs/progress/STEP-XX.md` containing:

- status;
- start and completion dates;
- evidence IDs reviewed;
- requirements implemented;
- files changed;
- commands run;
- automated test results;
- manual test results;
- deviations and open questions.

## Phase 0 - Establish The Project And Prove The Risks

### Step 0.1 - Create The Repository

Status: `READY`

Goal: Create a reproducible native macOS project at `~/Git/ForNow`.

Evidence:

- `AN-POS-002`
- `AN-POS-003`

Tasks:

1. Create `~/Git/ForNow`.
2. Initialize Git with default branch `main`.
3. Add this documentation set.
4. Add `project.yml` as the Xcode project source of truth.
5. Pin XcodeGen 2.45.4 in setup documentation, then re-check whether a newer
   stable version exists before execution.
6. Define macOS 14 deployment target and Swift 6 language mode.
7. Create application, unit-test, UI-test, and performance-test targets.
8. Add local packages listed in `02_ARCHITECTURE.md`.
9. Add GRDB and KeyboardShortcuts dependencies.
10. Generate the project and commit `Package.resolved`.
11. Add formatting, build, test, and project-generation scripts.
12. Add a CI workflow that builds and runs unit tests.

Expected commands:

```bash
cd ~/Git
mkdir ForNow
cd ForNow
git init -b main
brew install xcodegen
xcodegen generate
xcodebuild -project ForNow.xcodeproj -scheme ForNow build
xcodebuild -project ForNow.xcodeproj -scheme ForNowTests test
```

Deliverables:

- reproducible `ForNow.xcodeproj`;
- empty app launches;
- all package targets compile;
- CI configuration;
- `scripts/bootstrap.sh`, `scripts/build.sh`, `scripts/test.sh`.

Tests:

- clean checkout bootstrap;
- Debug build;
- Release build without signing;
- unit-test target runs one smoke test.

Exit criteria:

- no file must be manually added in Xcode after generation;
- project regeneration produces no unexpected diff;
- application launches on the development Mac;
- repository contains no AntiNote asset or copied source material.

Estimated effort: 1 day.

### Step 0.2 - Freeze Evidence And Requirement Traceability

Status: `READY`

Goal: Make hallucinated product behavior detectable.

Evidence:

- all `AN-*` entries;
- `06_MANUAL_WALKTHROUGH.md`.

Tasks:

1. Add machine-readable `docs/traceability.yml`.
2. Record every `AN-*` evidence ID, official section URL, confidence, and
   applicable `FR-*` requirements.
3. Record every `FR-*` requirement and planned test IDs.
4. Add a validation script that fails for unknown or orphan IDs.
5. Add `UNVERIFIED` as the only allowed marker for undocumented behavior.
6. Add an open-question template requiring owner, decision deadline, and
   verification method.

Deliverables:

- `docs/traceability.yml`;
- `scripts/validate-traceability.swift`;
- `docs/OPEN_QUESTIONS.md`.

Tests:

- inject an invalid evidence ID and confirm validation fails;
- inject an `FR-*` requirement without a test and confirm validation fails;
- restore valid files and confirm validation succeeds.

Exit criteria:

- every parity requirement traces to the official manual or another official
  source;
- every product improvement is marked `FORNOW-DECISION`, not `AN-*`.

Estimated effort: 0.5 day.

### Step 0.3 - Editor Projection Spike

Status: `BLOCKED` until Step 0.1.

Goal: Prove that visible enhancements can coexist with immutable source text,
correct selection, undo, and copy.

Evidence:

- `AN-TXT-001`
- `AN-TXT-003`
- `AN-CLIP-001`
- `AN-LIST-002`
- `AN-MATH-001`

Requirements:

- `FR-EDIT-001`
- `FR-EDIT-002`
- `FR-EDIT-004`
- `FR-EDIT-005`
- `FR-EDIT-006`

Build only:

1. An AppKit `NSTextView`.
2. Source snapshot versioning.
3. A fake calculation result shown after a line.
4. A visual shortened link.
5. A clickable checkbox decoration.
6. Copy projection.
7. Undo/redo through all three decoration types.

Mandatory fixtures:

- ASCII;
- Chinese;
- Emoji;
- composed accents;
- multiline selection;
- duplicate URL;
- marked-text input;
- edit before/inside/after decorated source.

Deliverables:

- standalone `EditorProjectionSpike` target;
- screen recording or screenshots of the interactions;
- offset-mapping unit tests;
- written choice between overlay adornments, TextKit layout fragments, and
  attachment-backed rendering.

Failure conditions:

- result characters enter `Note.body`;
- undo changes decoration state without source change;
- caret skips or duplicates source positions;
- Chinese marked text is committed early;
- copying a shortened link loses the original URL.

Exit criteria:

- 500 randomized edits preserve source and selection invariants;
- all mandatory fixtures pass;
- the chosen strategy is documented and approved.

Estimated effort: 3-5 days.

### Step 0.4 - Window And Spaces Spike

Status: `BLOCKED` until Step 0.1.

Goal: Prove invocation and focus behavior before designing the app shell.

Evidence:

- `AN-WIN-001`
- `AN-WIN-002`
- `AN-WIN-003`
- `AN-WIN-004`
- `AN-WIN-005`

Requirements:

- `FR-WIN-001` through `FR-WIN-005`.

Build:

1. Standard window.
2. Floating panel.
3. Menu bar dropdown panel.
4. Global shortcut registration with Option-A default, conflict handling, and
   macOS 15.0/15.1 diagnostics.
5. Pin with Command-P.
6. Auto-hide with suspension token.
7. Current-screen placement.
8. Configurable dropdown width/height and all Dock/Menu/Both/Neither modes.

Manual matrix:

- one display;
- two displays;
- multiple Spaces;
- another app in full screen;
- Stage Manager on/off;
- app focused/unfocused;
- pinned/unpinned;
- standard/menu/dropdown modes;
- settings and save panels open;
- macOS 15.0/15.1 workaround documented even if not locally testable.

Deliverables:

- `WindowSpike` target;
- state-transition log;
- completed manual matrix;
- window-level and collection-behavior design decision.

Exit criteria:

- global shortcut reaches a focused editor in every supported matrix cell;
- no panel appears offscreen;
- auto-hide does not close an owned system panel;
- repeated shortcut presses do not create duplicate windows.

Estimated effort: 3-4 days.

### Step 0.5 - Persistence And Backup Spike

Status: `BLOCKED` until Step 0.1.

Goal: Prove local durability, ordering, FTS, backup, migration, and restore.

Evidence:

- `AN-POS-002`
- `AN-NAV-005`
- `AN-BACK-001`

Requirements:

- `FR-NOTE-001`
- `FR-NOTE-004`
- `FR-NOTE-007`
- `FR-BACK-001`
- `FR-BACK-002`

Build:

1. Initial GRDB schema.
2. Note CRUD and monotonic promotion.
3. FTS index.
4. Debounced save repository.
5. Online backup.
6. Corruption detection.
7. Restore with emergency rollback.
8. One forward migration.

Test scenarios:

- kill process immediately after typing;
- kill during backup temp-file creation;
- simulate disk-full error;
- corrupt backup;
- restore old schema;
- promote notes concurrently;
- search Chinese and ASCII;
- reopen WAL database after unclean exit.

Exit criteria:

- last flushed edit survives process kill;
- failed save remains exportable from memory;
- corrupt backup cannot replace a healthy store;
- restore rollback returns the pre-restore store;
- FTS and note rows never diverge in tests.

Estimated effort: 3-4 days.

### Phase 0 Gate

Do not begin Phase 1 until Steps 0.3, 0.4, and 0.5 are `DONE`.

Project exception recorded 2026-08-04: the product owner directed Phase 1 work
to continue while `MT-WIN-004C` remains pending because a second simultaneous
physical display is not currently application-visible. This exception does not
convert the test to a pass, accept ADR-002, waive `FR-WIN-004`, or relax the 1.0
release gate. Step 0.4 remains `VERIFYING` until the physical dual-display cell
passes.

If any spike fails:

1. document the failure;
2. update architecture;
3. rerun the spike;
4. do not hide the issue behind a simplified mock.

## Phase 1 - Capture-First Alpha

### Step 1.1 - App Environment And Dependency Injection

Prerequisites: Phase 0 Gate.

Goal: Compose production services without global singletons.

Tasks:

1. Create `AppEnvironment`.
2. Inject repository, clock, UUID generator, parser, window coordinator,
   clipboard, OCR, notification, and rate provider.
3. Add production, preview, and test environments.
4. Centralize startup and shutdown ordering.
5. Add structured logging without note text.

Deliverables:

- production app composition;
- fake services for tests;
- launch smoke test.

Exit criteria:

- UI previews and tests need no real database or network;
- app shutdown flushes repository before service teardown.

Estimated effort: 1 day.

### Step 1.2 - Durable And Transient Notes

Evidence:

- `AN-NAV-003`
- `AN-NAV-004`
- `AN-NOTE-SET-001`

Requirements:

- `FR-NOTE-001`
- `FR-NOTE-002`
- `FR-NOTE-009`

Tasks:

1. Implement transient blank model.
2. Define meaningful-content policy.
3. Persist on first meaningful edit.
4. Discard blank on navigation/hide.
5. Implement launch and reopen-duration new-note policies.
6. Persist note count preference.

Tests:

- blank;
- whitespace only;
- newline only;
- keyword only;
- IME marked text;
- type then undo to blank;
- close/reopen duration thresholds.

Exit criteria:

- no abandoned blank rows;
- no text is lost when a transient note becomes durable.

Estimated effort: 1-2 days.

### Step 1.3 - Navigation, Jump, Promote, Delete

Evidence:

- `AN-NAV-002` through `AN-NAV-005`
- `AN-NAV-007`

Requirements:

- `FR-NOTE-003`
- `FR-NOTE-004`
- `FR-NOTE-005`

Tasks:

1. Implement previous/next commands.
2. Bind Command-left-bracket and Command-right-bracket.
3. Add two-finger gesture interpretation.
4. Create at newest boundary.
5. Implement Command-1 and Command-Shift-1.
6. Implement pre-edit navigation focus and directional entry.
7. Implement Command-D confirmation and suppression preference.
8. Add reset-delete-warning support in settings, avoiding a terminal-only
   recovery path.

Tests:

- one note;
- oldest/newest boundary;
- empty note boundary;
- rapid navigation while autosave is pending;
- promote ties;
- cancel and confirm deletion;
- directional cursor entry.

Exit criteria:

- ordering remains stable across relaunch;
- every navigation path commits source first.

Estimated effort: 2-3 days.

### Step 1.4 - Global Invocation And Presence Modes

Evidence:

- `AN-WIN-001` through `AN-WIN-005`

Requirements:

- `FR-WIN-001` through `FR-WIN-005`

Tasks:

1. Integrate validated window spike.
2. Add Option-A default and global shortcut preferences.
3. Add registration diagnostics for macOS 15.0/15.1 Option-only limitations.
4. Add standard, pseudo-menu, both, neither, and traditional dropdown modes.
5. Keep all commands accessible inside the app in neither mode.
6. Add configurable dropdown width and height.
7. Add Command-W, Command-O, and Command-P.
8. Add pin and auto-hide.
9. Restore focus/selection after show.
10. Add current-display placement.

Exit criteria:

- hotkey-to-caret p95 under 150 ms on the development machine;
- no duplicate windows after 1,000 toggle cycles;
- current note survives every hide/show path.

Estimated effort: 3 days.

### Step 1.5 - Alpha Search

Evidence:

- `AN-NAV-006`

Requirement:

- `FR-NOTE-007`

Tasks:

1. Build command-palette-style search overlay.
2. Bind Command-F.
3. Show all notes for empty query.
4. Query FTS for non-empty input.
5. Navigate with arrows.
6. Promote/open with Enter.
7. Dismiss with Escape.
8. Add VoiceOver result descriptions.

Exit criteria:

- 10,000-note fixture returns first page under 50 ms after index warmup;
- Enter uses the same promotion transaction as the editor command.

Estimated effort: 2 days.

### Alpha Gate

Alpha is complete when a user can:

1. invoke globally;
2. type immediately;
3. create and navigate notes;
4. promote and search;
5. close and reopen without data loss;
6. recover from a local backup.

No smart mode is required for this gate.

## Phase 2 - Editor Parity

### Step 2.1 - Production Editor Projection

Evidence:

- `AN-TXT-001`
- `AN-TXT-002`

Requirements:

- `FR-EDIT-001`
- `FR-EDIT-002`
- `FR-EDIT-005`
- `FR-EDIT-006`

Tasks:

1. Integrate the approved spike implementation.
2. Add source-version cancellation.
3. Add projection diagnostics.
4. Add selection and scroll restoration.
5. Add large-note parsing cancellation.
6. Add accessibility container for decorations.

Exit criteria:

- randomized editor invariant suite passes 10,000 operations;
- 50,000-character ordinary note remains responsive;
- no parser decoration enters autosave source.

Estimated effort: 4 days.

### Step 2.2 - Copy And Paste

Evidence:

- `AN-CLIP-001` through `AN-CLIP-003`

Requirements:

- `FR-CLIP-001` through `FR-CLIP-004`

Tasks:

1. Implement contextual copy decision table.
2. Implement clean export projection.
3. Add configurable paste transforms.
4. Add raw paste command.
5. Add HTML, RTF, browser, spreadsheet, terminal, and IDE fixtures.
6. Make every paste one undo group.

Exit criteria:

- every transform can be independently enabled/disabled;
- raw paste bypasses all optional transforms;
- source and clipboard tests cover Unicode and CRLF.

Estimated effort: 3 days.

### Step 2.3 - Links

Evidence:

- `AN-TXT-003`

Requirement:

- `FR-EDIT-004`

Tasks:

1. Detect links incrementally.
2. Wait until caret exit before shortening.
3. Build deterministic shortened labels.
4. Assign duplicate suffixes.
5. Persist manual expanded state outside source.
6. Implement Command-click and Command-Shift-click.
7. Disable behavior in code contexts.
8. Add independent automatic-shortening and all-hyperlinks settings.

Exit criteria:

- source URL round-trips exactly;
- duplicate labels remain stable after unrelated edits;
- malicious or invalid schemes do not open.

Estimated effort: 3 days.

### Step 2.4 - Simple Markdown And Code

Evidence:

- `AN-MD-001`
- `AN-CODE-001`

Requirements:

- `FR-EDIT-003`
- `FR-CLIP-001`
- `FR-CMD-004`

Tasks:

1. Implement documented heading, emphasis, strike, underline, comment, inline
   code, and fenced-code grammar.
2. Implement Command-slash line comments.
3. Add code mode header and language parsing.
4. Add syntax-highlighting adapter.
5. Add default language and theme settings.
6. Disable link and paste-indent stripping in code contexts.

Exit criteria:

- unsupported Markdown remains untouched;
- comment toggling is one undo group;
- syntax highlighter cannot mutate source.

Estimated effort: 4 days.

### Step 2.5 - Find And Replace

Evidence:

- `AN-NAV-006`

Requirement:

- `FR-NOTE-008`

Tasks:

1. Add Command-Shift-F panel.
2. Implement matching modes and case toggle.
3. Add regex validation.
4. Expand links while panel is open and restore presentation on close.
5. Implement Tab-to-replace and Enter/Shift-Enter field-specific commands.
6. Ensure replacement is source-coordinate based.

Exit criteria:

- replace-all is one undo group;
- zero-length regex matches cannot loop forever;
- invalid regex never changes source.

Estimated effort: 3 days.

## Phase 3 - Modes And Deterministic Intelligence

### Step 3.1 - Keyword And Slash Command System

Evidence:

- `AN-CMD-001` through `AN-CMD-003`
- `AN-REV-001`

Requirements:

- `FR-CMD-001` through `FR-CMD-003`

Tasks:

1. Implement canonical IDs and alias registry.
2. Enforce exactly one main slash alias per mode.
3. Parse first-line keyword and optional title.
4. Validate alias conflicts.
5. Add slash picker.
6. Add numeric selection.
7. Replace existing mode header atomically.
8. Add global disable setting.

Exit criteria:

- aliases never change stored canonical mode identity unexpectedly;
- command insertion and replacement each form one undo group.

Estimated effort: 3 days.

### Step 3.2 - List Mode

Evidence:

- `AN-LIST-001` through `AN-LIST-003`

Requirements:

- `FR-LIST-001` through `FR-LIST-003`

Tasks:

1. Parse eligible lines.
2. Render source-backed checkbox controls.
3. Parse configurable trailing checked trigger.
4. Exclude comment and heading lines.
5. Disable math/conversions in list mode.
6. Omit checked markers from clean copy according to settings.
7. Preserve existing source when the configured trigger changes.

Exit criteria:

- pointer and keyboard toggles produce identical source edits;
- triggers are omitted from clean copy according to settings.

Estimated effort: 3 days.

### Step 3.3 - Basic Math

Evidence:

- `AN-MATH-001`

Requirement:

- `FR-MATH-001`

Tasks:

1. Write grammar specification before parser code.
2. Add lexer and AST.
3. Add Decimal evaluator.
4. Add trailing-equals detection.
5. Add operator/function set.
6. Add decimal-locale interpretation.
7. Add significant digits from zero through seven.
8. Add independent thousands-separator display.
9. Add inline result decorations and copy.

Exit criteria:

- golden fixture covers every documented syntax family;
- invalid input produces diagnostics and never modifies source;
- no `eval`, JavaScript, or LLM is used.

Estimated effort: 5 days.

### Step 3.4 - Units And Currency

Evidence:

- `AN-MATH-003`

Requirements:

- `FR-MATH-003`
- `FR-MATH-004`

Tasks:

1. Create versioned unit/currency fixture schemas.
2. Add documented unit categories and aliases.
3. Map compatible units to Foundation Measurement.
4. Reject incompatible dimensions.
5. Enforce no arithmetic after conversion in parity mode.
6. Add primary symbol and primary/secondary currency settings.
7. Add custom rates.
8. Add disabled, cached, and remote providers.
9. Add opt-in daily refresh without more than one automatic request per day.
10. Display rate age and stale state.

Exit criteria:

- all fixture aliases resolve deterministically;
- network-off tests pass;
- note text is never included in a rate request.

Estimated effort: 5 days.

### Step 3.5 - Variables

Evidence:

- `AN-MATH-004`

Requirement:

- `FR-MATH-005`

Tasks:

1. Parse assignments and references.
2. Build dependency graph.
3. Detect cycles and depth limit.
4. Decide and document duplicate-name policy.
5. Implement three-character autocomplete threshold.
6. Implement Tab and number selection.
7. Drop conversion unit metadata in parity mode.

Exit criteria:

- changing one declaration updates all dependents;
- cycles and duplicates have stable diagnostics;
- autocomplete never inserts an unconfirmed value.

Estimated effort: 4 days.

### Step 3.6 - Sum, Average, Count

Evidence:

- `AN-MATH-002`

Requirement:

- `FR-MATH-002`

Tasks:

1. Implement numeric extraction fixture.
2. Exclude comments.
3. Reject/document fractions.
4. Implement count eligibility.
5. Add aggregate result decoration and copy.
6. Record `FORNOW-DECISION-002` in user-facing scope and omit reading-ease
   metrics until a versioned formula is approved.

Exit criteria:

- golden fixtures cover text, currency, punctuation, blank, comments, invalid
  numbers, and fractions;
- result order is stable.

Estimated effort: 2 days.

## Phase 4 - Power Workflows

### Step 4.1 - Timers

Evidence:

- `AN-TIME-001`
- `AN-TIME-002`

Requirements:

- `FR-TIME-001` through `FR-TIME-003`

Tasks:

1. Implement command parser.
2. Implement timer state machine.
3. Persist timer model.
4. Add stopwatch, countdown, titled countdown, cycles, and pomodoro.
5. Add pause/resume, restart, and stop.
6. Add click, double-click, and Escape interactions.
7. Add menu-bar display.
8. Add separate countdown and pomodoro-break notification, sound, and takeover
   settings.
9. Add pause-on-quit and volume `0...100`.
10. Reconcile clock changes and sleep/wake.
11. Show the timer command tutorial when `timer` is entered at the start of a
    note.

Exit criteria:

- state-machine transition tests are exhaustive;
- restart and relaunch preserve documented semantics;
- denied notifications do not affect timer state.

Estimated effort: 5 days.

### Step 4.2 - OCR

Evidence:

- `AN-OCR-001`
- `AN-OCR-002`

Requirements:

- `FR-OCR-001` through `FR-OCR-003`

Tasks:

1. Accept paste and drag/drop images.
2. Validate format and size.
3. Run local Vision OCR with cancellation.
4. Track insertion-point source version.
5. Insert recognized text as one undoable edit.
6. Add language and error handling.

Exit criteria:

- network monitor confirms no OCR request;
- fixtures cover supported formats, rotated text, CJK, empty images, and
  cancellation.

Estimated effort: 3 days.

### Step 4.3 - AutoPaste

Evidence:

- `AN-AUTO-001`
- `AN-AUTO-002`

Requirements:

- `FR-AUTO-001` through `FR-AUTO-003`

Tasks:

1. Parse `paste` and custom delimiter.
2. Start a visible scoped session.
3. Observe pasteboard change count.
4. Normalize and append text.
5. Prevent self-copy loops and duplicates.
6. Implement every stop path.
7. Stop safely if destination disappears.

Exit criteria:

- monitor is inactive when indicator is absent;
- 1,000 clipboard events create no duplicate or loop;
- destination deletion stops the session.

Estimated effort: 3 days.

### Step 4.4 - Appearance And Settings

Evidence:

- `AN-UI-001`
- `AN-NOTE-SET-001`
- `AN-REV-002`
- manual Themes and Visuals sections

Requirements:

- `FR-UI-001` through `FR-UI-003`
- `FR-EDIT-007`
- `FR-NOTE-009`

Tasks:

1. Add semantic light/dark themes.
2. Store independent light-mode and dark-mode theme selections.
3. Add blank, lined, dotted, small-grid, and large-grid paper.
4. Add subtle, clear, and bold paper opacity.
5. Add separate lined-paper and blank-paper list spacing.
6. Add XS, S, M, L, XL, and optional double size.
7. Add Command-plus/minus.
8. Add reduced transparency and high-contrast behavior.
9. Add validated keyword/shortcut settings.
10. Add macOS 15+ translucent mode only after opaque themes pass.
11. Add opacity `0...90` and mismatch preview warning.
12. Add a natural/LTR/RTL text layout direction override that never rewrites
    source.

Exit criteria:

- all themes pass contrast checks;
- longest setting labels fit supported window sizes;
- settings cannot make global invocation unreachable.

Estimated effort: 4 days.

## Phase 5 - Export, Lifecycle, And Release

### Step 5.1 - Quick Export

Evidence:

- `AN-EXP-001`
- `AN-EXP-002`
- `AN-EXPORT-003`

Requirements:

- `FR-EXP-001` through `FR-EXP-004`

Tasks:

1. Implement canonical export document.
2. Add Command-S quick destination.
3. Add text and Markdown atomic file writers.
4. Add first-line title and keyword omission settings.
5. Add Obsidian URL adapter.
6. Add Bear URL adapter.
7. Add Apple Shortcut adapter.
8. Add allowlisted custom URL templates with content/title/date placeholders.
9. Implement query encoding and documented path compatibility transforms.
10. Add ZIP export-all.
11. Add destination availability diagnostics.

Exit criteria:

- every adapter consumes the same canonical document;
- failures preserve source;
- invalid or oversized custom templates produce no external action;
- file output round-trips UTF-8 and unsafe filename characters.

Estimated effort: 4 days.

### Step 5.2 - Expiration And Bulk Deletion

Evidence:

- `AN-LIFE-001`
- `AN-NOTE-SET-001`

Requirements:

- `FR-NOTE-006`
- `FR-NOTE-005`
- `FR-NOTE-010`

Tasks:

1. Add today, one-week, one-month, one-year, and never expiration choices.
2. Compute explicit `expiresAt`.
3. Run idempotent expiration at launch and scheduled intervals.
4. Add bulk-delete-by-last-modified.
5. Create safety backup before a confirmed bulk deletion.
6. Add clear count and irreversible-action copy.

Exit criteria:

- clock changes do not double-delete;
- bulk-delete predicate has preview tests;
- cancellation leaves all notes unchanged.

Estimated effort: 2 days.

### Step 5.3 - In-App Backup Management

Evidence:

- `AN-BACK-001`

Requirements:

- `FR-BACK-001`
- `FR-BACK-002`

Tasks:

1. Integrate validated backup spike.
2. Add all documented frequency choices and retention settings.
3. Add a command to reveal the notes and backup folder.
4. Add backup list with date, size, and schema.
5. Add manual backup.
6. Add guarded restore under `FORNOW-DECISION-001`.
7. Add emergency rollback and recovery report.

Exit criteria:

- full destructive restore rehearsal passes;
- every restore path creates an emergency current-state backup;
- no manual Finder replacement is necessary.

Estimated effort: 3 days.

### Step 5.4 - URL Schemes

Evidence:

- `AN-URL-001`

Requirements:

- `FR-URL-001`
- `FR-URL-002`

Tasks:

1. Define ForNow routes and versioning.
2. Add strict decoding and payload limits.
3. Implement open/create/append/overwrite/promote/pin/toggle/search.
4. Serialize search callbacks with ID, content, and last-modified fields.
5. Add callback allowlist.
6. Add note-ID validation.
7. Add developer-only reload behind a disabled-by-default flag.
8. Validate SQLite integrity before reload.
9. Publish examples and security notes.

Exit criteria:

- malformed URLs produce no mutation;
- callbacks cannot target arbitrary executable schemes;
- route tests cover Unicode and oversized payloads.

Estimated effort: 3 days.

### Step 5.5 - Accessibility And Keyboard Audit

Evidence:

- `AN-ACC-001`

Tasks:

1. Test full keyboard workflow.
2. Test VoiceOver editor, search, slash picker, results, checkboxes, timers,
   settings, and errors.
3. Add reduced motion.
4. Add reduced transparency.
5. Validate focus restoration.
6. Validate minimum hit areas.
7. Validate contrast for every theme.

Exit criteria:

- no frequent workflow requires a pointer;
- no interactive decoration is invisible to VoiceOver;
- focus does not escape modal or command surfaces.

Estimated effort: 3 days.

### Step 5.6 - Performance And Reliability

Tasks:

1. Add launch, hotkey, input, parsing, search, backup, and memory benchmarks.
2. Run 24-hour timer and AutoPaste soak tests.
3. Run randomized editor mutation tests.
4. Run 100,000-note database fixture tests.
5. Run repeated sleep/wake.
6. Run 1,000 show/hide cycles.
7. Inspect logs for note content.
8. Test no-network operation.

Release budgets:

- cold launch to ready: under 500 ms target;
- hotkey to caret: p95 under 150 ms;
- typing event synchronous work: p95 under 4 ms;
- warm search first page: under 50 ms;
- idle memory: target under 100 MB;
- no unbounded growth during 24-hour soak.

Exit criteria:

- all budgets pass or have an approved documented exception;
- no known data-loss bug remains open.

Estimated effort: 4 days.

### Step 5.7 - Packaging And Release

Evidence:

- `AN-UPD-001`
- `AN-SUP-001`
- `AN-DIST-001`
- `FORNOW-DECISION-003`

Requirements:

- `FR-UPD-001`
- `FR-SUP-001`
- `FR-DIST-001`
- `FR-PRIV-001`

Tasks:

1. Create app icon and original visual identity.
2. Configure bundle ID, versioning, entitlements, and privacy descriptions.
3. Enable hardened runtime.
4. Sign and notarize universal archive.
5. Create DMG.
6. Add a direct-distribution update feed.
7. Ask for automatic-check consent on the second successful launch.
8. Keep manual check, automatic check, and automatic install as separate paths.
9. Add Homebrew cask only after signed release is stable.
10. Document Setapp as out of 1.0 scope unless a distribution agreement exists.
11. Add preference-reset instructions that preserve notes and backups.
12. Add direct executable diagnostic-launch instructions.
13. Verify logs contain no note, clipboard, URL payload, or secret content.
14. Write install, update, uninstall, backup, and recovery instructions.
15. Run clean-machine installation and upgrade-preservation tests.
16. Create release checklist and rollback procedure.

Exit criteria:

- Gatekeeper accepts a clean download;
- declining automatic checks produces no update request;
- check and install settings operate independently;
- update preserves notes and settings;
- preference reset preserves notes and backups;
- diagnostic logs pass privacy inspection;
- uninstall instructions distinguish app, settings, notes, and backups;
- release artifact checksum is published.

Estimated effort: 3-5 days.

## 1.0 Release Gate

Release only when:

1. Phase 0 through Phase 5 steps are `DONE`.
2. Traceability validation passes.
3. Test matrix has no missing 1.0 requirements.
4. No P0/P1 defect is open.
5. Backup restore rehearsal passes on the release candidate.
6. Accessibility audit passes.
7. No generative AI or account is required.
8. Offline smoke test passes.
9. Clean-room review confirms no copied branding or proprietary asset.

## Phase 6 - Post-1.0

### Step 6.1 - Slotted Notes

Evidence:

- `AN-BETA-001`

Tasks:

1. Validate official beta behavior again at implementation time.
2. Define slot count and assignment behavior as a ForNow decision.
3. Add direct shortcuts.
4. Preserve ordinary recency navigation.
5. Add migrations and sync-ready slot conflicts.

### Step 6.2 - iCloud And iOS

Evidence:

- `AN-BETA-002`
- `FORNOW-DECISION-007` through `FORNOW-DECISION-009`

Requirements:

- `FR-IOS-SYNC-001`
- the iOS 1.0 requirements in `docs/ios/traceability.yml`

Tasks:

1. Execute `docs/ios/05_IOS_IMPLEMENTATION_PLAYBOOK.md` in order.
2. Add tombstones, hybrid logical clocks, sync metadata, ingestion receipts,
   and the Spotlight outbox.
3. Implement the private CloudKit custom zone with `CKSyncEngine`.
4. Apply the documented edit/edit and edit/delete recovery-note policy.
5. Add local-only mode, later iCloud enablement, account-loss handling, and
   restore-as-merge.
6. Build the iOS editor and system-surface spikes after macOS 1.0 shared
   packages are stable.
7. Run the complete iOS test matrix, including two-device, clock-skew,
   seven-day offline, migration, backup, privacy, accessibility, and App Store
   validation cells.

Deliverables:

- the five iOS design/requirements/architecture/test/playbook documents;
- `docs/ios/traceability.yml` with no orphan 1.0 requirement;
- reproducible iPhone project and CI jobs;
- production-ready sync engine and migration;
- TestFlight release candidate with JavaScript extensions absent.

Exit criteria:

- every `release: ios-1.0` traceability entry is green;
- CloudKit conflict fixtures preserve all user-authored text;
- local-only mode works with iCloud and network disabled;
- backup restore merges safely with synchronized data;
- the app-only SQLite writer invariant holds across widgets, intents, and the
  share extension;
- privacy, accessibility, physical-device, performance, and App Store gates
  pass.

Do not advertise end-to-end encryption unless its exact protection model has
been independently verified.

### Step 6.3 - Extensions

Evidence:

- `AN-EXT-001`
- `AN-EXT-002`

Tasks:

1. Define the versioned manifest schema per `AN-EXT-001`: name, version,
   author, category, dataScope, endpoints, requiredAPIKeys, dependencies,
   isService, and ordered files.
2. Implement the JavaScriptCore ES6 sandbox with sequential file loading.
3. Implement the `::` palette with filtering, typed parameter forms, and the
   four documented command types (insert, replaceLine, replaceAll, openURL).
4. Enforce immutable input scopes: none, line, full.
5. Return results as source-edit operations with status, message, payload.
6. Add the Keychain `{{API_KEY}}` placeholder bridge with structural endpoint
   validation, redirect revalidation, and host-verified extension identity
   (`AN-EXT-002`, `FORNOW-DECISION-010`).
7. Add the MathEvaluator bridge backed by the shared math engine, and the
   preferences API (`AN-EXT-004`).
8. Add the service-extension dependency model; centralize AI access in one
   service consistent with `05_AI_POLICY.md`.
9. Add the extensions folder, explicit reload, catalog browsing, and logging
   panel.
10. Add execution time, memory, and output limits.
11. Security review before public installation support.

Deliverables:

- versioned manifest schema and validator with fixtures;
- sandboxed runtime with scope enforcement;
- `::` palette UI;
- Keychain secret bridge and network allowlist;
- MathEvaluator and preferences bridges;
- extension manager with folder, reload, catalog browsing, and logging
  panel.

Tests:

- `UT-EXT-001A` through `UT-EXT-004C`, `ET-EXT-002`, `IT-EXT-004`, and
  `ST-EXT-003` per test matrix section 19;
- hostile-extension fixtures: scope escape, lookalike host, path-boundary
  escape, redirect escape, identity spoofing, oversized output, infinite loop;
- replay fixtures: identical manifest plus input snapshot produces
  identical source edits across runs and machines.

Exit criteria:

- every test-matrix extension row passes;
- a hostile extension cannot read out-of-scope text, reach undeclared
  endpoints, or access secrets;
- malformed extensions quarantine without affecting built-in behavior;
- command execution is reproducible from manifest plus input snapshot.

### Step 6.4 - Custom Themes

Evidence:

- `AN-UI-002`

Requirement:

- `FR-UI-004`

Tasks:

1. Publish a versioned JSON schema.
2. Reveal the custom theme directory from settings.
3. Decode themes into semantic tokens without code or remote assets.
4. Quarantine invalid files with actionable diagnostics.
5. Add explicit reload and built-in fallback.
6. Validate community themes as untrusted local input.

### Step 6.5 - Raycast And Alfred Integrations

Evidence:

- `AN-URL-001`

Requirement:

- `FR-INT-001`

Tasks:

1. Publish stable URL examples for create, search, and pin.
2. Build reference Raycast and Alfred integrations without database access.
3. Add version compatibility checks.
4. Publish setup, privacy, upgrade, and uninstall instructions.
5. Test against malformed callback data and an unavailable ForNow app.

### Step 6.6 - Optional In-Product AI

Prerequisite:

- Core 1.0 is stable;
- extension or integration permission model exists;
- `05_AI_POLICY.md` is satisfied.

Possible opt-in commands:

- summarize selected text;
- rewrite selected text;
- convert selection to checklist;
- translate selection;
- extract structured fields.

AI must never replace math, OCR, link parsing, search, timers, persistence, or
backup.

## Estimated Schedule

For one experienced macOS engineer working full time:

- Phase 0: 2 weeks.
- Phase 1: 1.5 weeks.
- Phase 2: 2.5 weeks.
- Phase 3: 3 weeks.
- Phase 4: 2 weeks.
- Phase 5: 3 weeks.

Production-quality 1.0 estimate: **14-15 weeks**, including risk spikes and
release hardening.

An AI coding agent may shorten mechanical implementation time, but it does not
remove the spike, manual-platform, accessibility, soak-test, or release gates.
