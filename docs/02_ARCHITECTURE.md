# ForNow Technical Architecture

## 1. Baseline

- Product: native macOS scratchpad.
- Deployment target: macOS 14+.
- Toolchain: Swift 6 language mode, Xcode 26 project.
- Architectures: arm64 and x86_64 release builds.
- UI: SwiftUI application shell with AppKit for the editor and panels.
- Storage: SQLite through GRDB 7.x.
- Global shortcut: KeyboardShortcuts 2.x behind an internal adapter.
- OCR: Vision.
- Notifications: UserNotifications.
- Unit conversion: Foundation `Measurement`.
- Expression evaluation: a small internal grammar, optionally backed by the
  MIT-licensed Expression package behind an adapter.
- Networking: URLSession, only for explicitly enabled currency rates and later
  integrations.
- Secrets: Keychain.
- Dependency management: Swift Package Manager with exact major-version
  ranges and `Package.resolved` committed.

Dependency versions must be checked again when Step 0.1 starts. As of the
research date, GRDB 7.10.0 and KeyboardShortcuts 2.4.0 are current public
releases, but the repository must pin the versions actually validated by CI.

## 2. Repository Structure

```text
ForNow/
├── ForNow.xcodeproj
├── App/
│   ├── ForNowApp.swift
│   ├── AppDelegate.swift
│   ├── AppEnvironment.swift
│   ├── Commands/
│   ├── MenuBar/
│   ├── Settings/
│   └── Resources/
├── Packages/
│   ├── ForNowCore/
│   ├── ForNowPersistence/
│   ├── ForNowEditor/
│   ├── ForNowModes/
│   ├── ForNowWindowing/
│   ├── ForNowIntegrations/
│   └── ForNowDesign/
├── Tests/
├── UITests/
├── PerformanceTests/
├── scripts/
└── docs/
```

## 3. Package Responsibilities

### ForNowCore

Contains:

- domain IDs and value types;
- Note, NoteOrder, Timer, Theme, and settings models;
- use-case protocols;
- state machines;
- errors and diagnostics;
- clock, UUID, and filesystem abstractions for testing.

Must not import:

- SwiftUI;
- AppKit;
- GRDB;
- Vision;
- network implementation types.

### ForNowPersistence

Contains:

- GRDB records and migrations;
- repositories implementing Core protocols;
- FTS index maintenance;
- backup creation and restore;
- export snapshots;
- transactional ordering and lifecycle operations.

Must not:

- expose GRDB rows to the application layer;
- render text;
- know about window state;
- perform network requests.

### ForNowEditor

Contains:

- `NSTextView` subclass or coordinator;
- TextKit 2 integration;
- source-selection mapping;
- undo grouping;
- line decoration rendering;
- pointer and accessibility interaction for decorations;
- drag, drop, copy, and paste interception;
- search highlights.

Must not:

- write directly to SQLite;
- parse currencies or timers;
- own application settings;
- call AI services.

### ForNowModes

Contains:

- mode-header parser;
- slash command catalog;
- Markdown parser;
- link detector;
- checklist parser;
- math tokenizer, parser, evaluator, and dependency graph;
- aggregate modes;
- timer command parser;
- diagnostic formatting.

All public operations should be pure functions or deterministic actors with
explicit inputs.

### ForNowWindowing

Contains:

- window/panel creation;
- Space and full-screen collection behavior;
- placement and screen clamping;
- visibility state machine;
- global shortcut adapter;
- auto-hide suspension tokens;
- pin mode;
- Dock/menu bar presence mode.

Must not:

- load note rows itself;
- interpret editor source;
- initiate exports.

### ForNowIntegrations

Contains:

- Vision OCR;
- clipboard observation;
- local notifications;
- currency-rate providers;
- file export;
- Apple Notes, Bear, and Obsidian adapters;
- custom URL export adapter;
- URL router;
- update checker and installer adapter for direct-distribution builds;
- later CloudKit and extension adapters.

Every integration is behind a protocol and has an offline or unavailable
implementation.

### ForNowDesign

Contains:

- semantic colors;
- typography tokens;
- paper-style definitions;
- versioned custom-theme decoder and validator;
- icon usage;
- motion definitions;
- accessibility variants.

No product behavior belongs in this package.

## 4. Domain Models

### Note

```swift
struct Note: Sendable, Equatable, Identifiable {
    let id: NoteID
    var body: String
    var createdAt: Date
    var modifiedAt: Date
    var orderKey: Int64
    var expiresAt: Date?
    var slotIndex: Int?
    var lastSelection: SourceSelection?
    var lastScrollAnchor: SourceOffset?
}
```

Rules:

- `body` is source text only.
- `orderKey` is monotonic and assigned transactionally.
- `slotIndex` is reserved for post-1.0 slotted notes.
- Selection restoration is best-effort and clamped to current source length.

### TransientNote

```swift
struct TransientNote {
    var body: String
    var createdAt: Date
}
```

It becomes a durable Note when source text passes `MeaningfulContentPolicy`.
Whitespace-only content does not persist.

### Timer

```swift
struct NoteTimer: Sendable, Equatable, Identifiable {
    let id: TimerID
    let noteID: NoteID
    var kind: TimerKind
    var title: String?
    var phase: TimerPhase
    var state: TimerState
    var startedAt: Date?
    var accumulated: Duration
    var workDuration: Duration?
    var restDuration: Duration?
}
```

Timer display always derives from monotonic elapsed time while the process is
alive and reconciles against wall-clock timestamps after relaunch.

### Settings

Split settings by ownership:

- `WindowSettings`;
- `EditorSettings`;
- `PasteSettings`;
- `ModeSettings`;
- `MathSettings`;
- `TimerSettings`;
- `AppearanceSettings`;
- `LifecycleSettings`;
- `ExportSettings`;
- `PrivacySettings`.

Settings use versioned Codable structures stored in UserDefaults. Secrets and
tokens never use UserDefaults.

Required setting contracts:

- `WindowSettings`: Option-A default hotkey, presence mode, pin, auto-hide,
  dropdown width, and dropdown height;
- `EditorSettings`: link shortening enabled, hyperlink features enabled,
  keyword omission on copy, checklist-trigger omission, code defaults, and
  text layout direction override;
- `PasteSettings`: independent leading whitespace, list-number, bullet,
  Markdown, and empty-line transforms;
- `ModeSettings`: alias sets, exactly one main slash alias per mode, keyword
  master switch, and checklist trigger;
- `MathSettings`: significant digits `0...7`, thousands grouping, primary
  symbol, primary/secondary currency, daily refresh, and custom rates;
- `TimerSettings`: quit behavior, menu-bar display, countdown and break
  notification/takeover/sound switches, and volume `0...100`;
- `AppearanceSettings`: independent light/dark theme IDs, paper type, paper
  opacity, text size, double size, translucency, and opacity `0...90`;
- `LifecycleSettings`: resume-note policy, expiration interval, note count,
  backup frequency, and retention count;
- `ExportSettings`: quick destination, title/keyword policy, Obsidian vault,
  and validated custom URL template;
- `PrivacySettings`: update-check consent and automatic-install preference.

## 5. SQLite Schema

Initial migration:

```sql
CREATE TABLE note (
    id TEXT PRIMARY KEY NOT NULL,
    body TEXT NOT NULL,
    created_at REAL NOT NULL,
    modified_at REAL NOT NULL,
    order_key INTEGER NOT NULL UNIQUE,
    expires_at REAL,
    slot_index INTEGER UNIQUE,
    selection_start INTEGER,
    selection_length INTEGER,
    scroll_offset INTEGER
);

CREATE INDEX note_modified_at_idx ON note(modified_at);
CREATE INDEX note_expires_at_idx ON note(expires_at);

CREATE VIRTUAL TABLE note_fts USING fts5(
    note_id UNINDEXED,
    body,
    tokenize = 'unicode61'
);

CREATE TABLE timer (
    id TEXT PRIMARY KEY NOT NULL,
    note_id TEXT NOT NULL REFERENCES note(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    title TEXT,
    phase TEXT NOT NULL,
    state TEXT NOT NULL,
    started_at REAL,
    accumulated_seconds REAL NOT NULL,
    work_seconds REAL,
    rest_seconds REAL
);

CREATE TABLE metadata (
    key TEXT PRIMARY KEY NOT NULL,
    value BLOB NOT NULL
);
```

Database rules:

- enable WAL;
- enable foreign keys;
- set a bounded busy timeout;
- all order changes use one write transaction;
- update `note` and `note_fts` in the same transaction;
- migrations are forward-only and tested from every shipped schema;
- no UI code constructs SQL;
- database access occurs through one `DatabasePool`.

## 6. Editor Architecture

### 6.1 Why AppKit

The editor needs:

- marked text and input-method correctness;
- exact selections;
- custom copy and paste;
- undo grouping;
- click targets attached to source ranges;
- syntax and search highlights;
- drag/drop images;
- large-text performance;
- accessibility elements for computed results.

SwiftUI `TextEditor` does not expose enough control. Use an `NSTextView` hosted
inside `NSViewRepresentable`.

### 6.2 Source And Projection

```text
Note.body
   |
   v
SourceSnapshot(version, text, changedRange)
   |
   +-> ModeHeaderParser
   +-> MarkdownParser
   +-> LinkParser
   +-> ChecklistParser
   +-> MathParser/Evaluator
   +-> TimerCommandParser
   |
   v
EditorProjection(version, decorations, diagnostics, semanticLines)
   |
   v
TextKit decoration layer
```

`EditorProjection` never replaces `Note.body`.

### 6.3 Source Coordinates

Define:

```swift
struct SourceOffset: Sendable, Hashable {
    let utf16Offset: Int
}

struct SourceRange: Sendable, Hashable {
    let location: SourceOffset
    let length: Int
}
```

AppKit operates in UTF-16 offsets, so the editor boundary uses validated UTF-16
coordinates. Domain parsers may use native Swift indices internally, but every
conversion is centralized and tested.

### 6.4 Decorations

```swift
enum EditorDecoration {
    case style(SourceRange, TextStyle)
    case link(SourceRange, LinkPresentation)
    case checkbox(SourceRange, CheckboxPresentation)
    case result(anchor: SourceOffset, CalculationPresentation)
    case diagnostic(SourceRange, DiagnosticPresentation)
    case timer(anchor: SourceOffset, TimerPresentation)
}
```

Rules:

- decorations include the source version that produced them;
- stale-version decorations are discarded;
- decoration updates do not enter the undo manager;
- interactive decorations call domain commands using source ranges;
- result values are never inserted into `textStorage`;
- accessibility exposes decorations as adjacent semantic elements.

### 6.5 Incremental Parsing

On edit:

1. Capture source mutation and new source version.
2. Commit immediate `NSTextView` source state.
3. Determine affected line range.
4. Parse mode header synchronously because it changes the whole interpretation.
5. Parse lightweight current-line features synchronously if under budget.
6. Parse full-note aggregates and dependency graph off the main actor.
7. Apply projection only if source version still matches.
8. Debounce persistence separately from parsing.

Performance budgets:

- synchronous edit processing: p95 below 4 ms;
- ordinary line projection: p95 below 8 ms;
- full-note math projection for 10,000 lines: below 150 ms off-main;
- no parser task may block text input.

### 6.6 Copy Decision Table

Priority:

1. Non-empty selection -> selection export projection.
2. Caret inside inline code -> inline-code source.
3. Caret inside fenced code block -> block source without fences when policy
   requires.
4. Caret on/clicked result -> canonical result.
5. Otherwise -> whole-note clean export projection.

Each branch has unit and integration tests.

### 6.7 Paste Pipeline

```text
Pasteboard payload
  -> type selection
  -> string decoding
  -> line-ending normalization
  -> optional leading/trailing trim
  -> optional bullet stripping
  -> optional number stripping
  -> optional Markdown stripping
  -> optional blank-line stripping
  -> one editor replacement
  -> one undo group
```

Raw paste uses only payload decoding and line-ending normalization.

## 7. Mode And Parser Architecture

### Mode Header

```swift
struct ModeHeader {
    let modeID: ModeID
    let matchedAlias: String
    let title: String?
    let sourceRange: SourceRange
}
```

Alias matching:

- first eligible source line only;
- exact normalized alias before optional colon;
- aliases match case-insensitively by default (`AN-REV-001`);
- longest-match wins only after collision validation;
- an invalid or disabled alias yields plain mode.

### Math

Pipeline:

```text
source line
 -> comment exclusion
 -> trailing-equals detection
 -> assignment split
 -> unit/currency target split
 -> tokenization
 -> expression AST
 -> variable dependency resolution
 -> Decimal evaluation
 -> conversion
 -> locale-aware formatting
 -> result decoration
```

Use `Decimal` for user-facing decimal arithmetic where possible. Define
overflow, division-by-zero, NaN, and precision behavior explicitly.

AST:

```swift
indirect enum ExpressionNode {
    case decimal(Decimal)
    case variable(VariableID)
    case unary(UnaryOperator, ExpressionNode)
    case binary(BinaryOperator, ExpressionNode, ExpressionNode)
    case function(FunctionID, [ExpressionNode])
}
```

Never use `NSExpression`, JavaScript evaluation, or `eval` for note math.

### Variables

Build a graph each source version:

- assignment declaration nodes;
- reference edges;
- stable source order;
- duplicate-name diagnostic policy;
- depth-first cycle detection;
- topological evaluation;
- bounded maximum dependency depth.

### Unit Aliases

Store aliases in versioned JSON fixtures:

```text
Resources/Units/v1/distance.json
Resources/Units/v1/area.json
Resources/Units/v1/volume.json
Resources/Units/v1/mass.json
Resources/Units/v1/temperature.json
Resources/Currencies/iso-4217.json
```

Each fixture contains:

- canonical ID;
- aliases;
- symbols;
- regional spellings;
- Foundation unit mapping;
- provenance;
- last review date.

### Timers

Timer commands produce commands, not direct UI changes:

```swift
enum TimerCommand {
    case startStopwatch(title: String?)
    case startCountdown(Duration, title: String?)
    case startCycle(work: Duration, rest: Duration, title: String?)
    case pauseOrResume
    case restart
    case stop
}
```

The `TimerStateMachine` is the only owner of valid transitions.

## 8. Window Architecture

### Components

- `WindowCoordinator`: one authority for visibility and placement.
- `WindowModeFactory`: standard window, floating panel, menu bar dropdown.
- `GlobalShortcutService`: package adapter.
- `AutoHideCoordinator`: focus-loss handling with suspension tokens.
- `ScreenPlacementService`: active Space/display placement and clamping.

### Visibility State

Every transition is serialized on `@MainActor`.

```swift
enum VisibilityState {
    case hidden
    case showing
    case focused
    case visibleUnfocused
    case hiding
}
```

`show()`:

1. Resolve active display.
2. Move or clamp the window.
3. Order front regardless of current app.
4. Activate ForNow according to mode.
5. Focus editor.
6. Restore note selection.

`hide()`:

1. Cancel transient menus.
2. Commit editor source.
3. Flush persistence.
4. Order out or close according to mode.
5. Preserve note and selection identity.

### Auto-Hide Suspension

System panels, settings, command picker, permission prompts, and export dialogs
receive a reference-counted suspension token. Auto-hide resumes only after all
tokens are released.

## 9. Persistence And Backup

### Autosave

- source changes update an in-memory draft immediately;
- database save is debounced 250 ms;
- navigation, hide, close, and termination force a flush;
- writes are serialized by a repository actor;
- database failures leave the in-memory source intact and show a persistent
  error with retry/export options.

### Backup

Default:

- interval: 3 hours;
- retained copies: 12;
- trigger after a successful write and interval eligibility;
- use SQLite online backup API through GRDB;
- write to temporary path, verify open/integrity, then atomically rename;
- include schema version and checksum manifest.

Restore:

1. Stop editor writes.
2. Validate backup manifest and SQLite integrity.
3. Create emergency backup of current database.
4. Close database pool.
5. Atomically replace database.
6. Reopen and run migrations.
7. Verify note count and sample checksums.
8. Roll back to emergency backup if any step fails.

## 10. Integrations

### OCR

`OCRService` accepts immutable image data and returns recognized text plus
confidence metadata. The editor owns only progress and final insertion.

Limits:

- maximum pixel area;
- maximum encoded byte size;
- explicit supported UTTypes;
- cancellation;
- no disk persistence unless required by Vision, and temporary files are
  deleted.

### AutoPaste

`PasteboardMonitor`:

- polls `NSPasteboard.general.changeCount` only while active;
- reads only supported text types;
- stores no historical clipboard outside the destination note;
- ignores its own write tokens;
- stops on destination loss or app termination.

### Currency

```swift
protocol CurrencyRateProvider {
    func rates(base: CurrencyCode) async throws -> RateSnapshot
}
```

Implementations:

- `DisabledCurrencyRateProvider`;
- `CachedCurrencyRateProvider`;
- one explicitly selected remote provider;
- `FixtureCurrencyRateProvider` for tests.

No provider is contacted before user opt-in.

### Export

```swift
protocol ExportDestination {
    func export(_ document: ExportDocument) async throws -> ExportReceipt
}
```

Adapters:

- Text file;
- Markdown file;
- ZIP archive;
- Obsidian URL;
- Bear URL;
- Apple Shortcut;
- validated custom URL template.

The custom template adapter:

- substitutes only `{CONTENT}`, `{TITLE}`, and `{DATE}`;
- distinguishes query values from URL path content;
- percent encodes query values exactly once;
- transforms ampersand to plus and percent to the literal string ` percent`
  only in substituted path content;
- enforces an allowlist and maximum URL size before opening a destination.

### URL Router

Requirements:

- versioned route names;
- strict percent decoding;
- payload size limit;
- no arbitrary file writes;
- no arbitrary command execution;
- callback scheme allowlist;
- routes for open, create, append, overwrite, promote/open, pin, visibility,
  search callback, and developer reload;
- reload is disabled by default and validates SQLite integrity before swapping
  visible repository state;
- mutation routes execute through the same use cases as UI commands.

### Updates And Support

- Direct-distribution builds use an `UpdateService` protocol.
- The second successful launch may request consent to automatic checks.
- Check and install preferences remain separate.
- Homebrew builds do not silently install through the direct updater.
- Preference reset deletes only versioned UserDefaults domains owned by ForNow.
- Diagnostic launch uses the ordinary executable and the same privacy-filtered
  logging configuration as a normal launch.

## 11. Concurrency

- UI and AppKit objects: `@MainActor`.
- repository: dedicated actor wrapping GRDB pool.
- parsing: task group or parsing actor with source-version cancellation.
- OCR: cancellable async service.
- currency/network: integration actor.
- timers: one clock actor, UI snapshots published on main actor.

Do not mark types `@unchecked Sendable` unless a written invariant and a
concurrency test accompany it.

## 12. Error Handling

Use domain errors:

```swift
enum ForNowError: Error {
    case persistence(PersistenceFailure)
    case parsing(ParseDiagnostic)
    case permission(PermissionFailure)
    case integration(IntegrationFailure)
    case configuration(ConfigurationFailure)
}
```

Rules:

- parse diagnostics stay inline and do not become app alerts;
- data-write failures persist visibly until resolved;
- permission denial provides a settings path and a non-permission fallback;
- export failures never delete or clear source;
- backup failures do not block editing but remain visible;
- no raw service error or SQL text is shown to users.

## 13. Security And Privacy

- App Sandbox enabled where compatible with planned distribution.
- Hardened runtime and notarization.
- No analytics in 1.0.
- No note text in logs.
- `os.Logger` values containing IDs use privacy annotations.
- URL callbacks are validated.
- Security-scoped bookmarks are used for user-selected export folders.
- Secrets use Keychain.
- OCR remains local.
- Clipboard monitoring is visible and explicitly scoped.
- Currency requests contain only currency codes, never note content.

## 14. Future Sync Boundary

Sync is not implemented in 1.0, but the schema prepares for it:

- stable UUIDs;
- explicit modified timestamps;
- tombstone capability added by migration before sync;
- per-field or per-record revision;
- deterministic conflict policy;
- sync operation log separate from editor autosave.

CloudKit code will implement `SyncEngine` and consume repository change events.
It may not write the database directly.

## 15. Future Extension Boundary

Extensions are post-1.0 and follow the documented AntiNote extension design
(`AN-EXT-001` through `AN-EXT-004`):

- JavaScriptCore ES6 context per invocation;
- versioned manifest: name, version, author, category, dataScope, endpoints,
  requiredAPIKeys, dependencies, isService, and ordered files;
- `::` command palette with typed, defaultable parameters and four command
  types: insert, replaceLine, replaceAll, openURL;
- input scope: none, current line, or full note, declared in the manifest and
  visible to users;
- immutable input snapshot carrying scope-limited text and locale settings;
- returned edits represented as source edit operations with status, message,
  and payload;
- structural endpoint allowlist validation over scheme, normalized host,
  effective port, and path boundaries, including redirect revalidation;
- Keychain-held secrets substituted by the host into `{{API_KEY}}`
  placeholders, never exposed to JavaScript;
- host-mediated, versioned bridges for math evaluation, preferences, and
  service-extension dependencies;
- AI access centralized in one service extension, consistent with
  `05_AI_POLICY.md`;
- execution time, memory, and output limits;
- no filesystem, pasteboard, or process access by default.

Custom themes and launcher integrations are also post-1.0 boundaries:

- custom themes are decoded from a versioned JSON schema into semantic design
  tokens and cannot inject code, URLs, or arbitrary file references;
- Raycast and Alfred integrations consume only the public URL router and never
  write SQLite directly.

## 16. Architecture Exit Criteria

Architecture is accepted only after:

1. Projection spike proves source integrity through edit, undo, copy, and save.
2. Window spike proves current-Space and full-screen behavior.
3. Database spike proves autosave, backup, migration, and restore.
4. All packages compile with Swift 6 concurrency checks.
5. No circular package dependency exists.
6. A test can run every parser without launching AppKit.
7. The application can run with network disabled.
