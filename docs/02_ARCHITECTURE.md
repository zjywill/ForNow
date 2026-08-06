# ForNow Technical Architecture

## 1. Baseline

- Product: native macOS scratchpad.
- Deployment target: macOS 14+.
- Toolchain: Swift 6 language mode, Xcode 26 project.
- Architectures: arm64 and x86_64 release builds.
- UI: SwiftUI application shell with AppKit for the editor and panels.
- Storage: SQLite through GRDB 7.x.
- Global shortcut: KeyboardShortcuts 1.x behind an internal adapter.
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
research date, GRDB 7.10.0 was current. Implementation-time verification on
2026-08-03 found GRDB 7.11.1 and KeyboardShortcuts 1.10.0 as the current public
releases; the upstream KeyboardShortcuts project has no stable 2.x tag. The
repository must pin the versions actually validated by CI.

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

### Application Composition

`AppEnvironment` is the `@MainActor` composition root. It owns protocol-typed
references to the repository, wall clock, UUID generator, parser, window
coordinator, clipboard, OCR, notification, currency-rate, and lifecycle-logging
services. There are three explicit variants:

- production uses the deferred-open GRDB repository, system clock and UUIDs,
  Vision OCR, UserNotifications, and the SwiftUI window coordinator;
- preview uses only deterministic in-memory or disabled dependencies;
- test accepts an override for every dependency and defaults to deterministic
  in-memory or disabled dependencies.

Currency rates and clipboard reads remain disabled in the production default
until the user explicitly enables their owning feature. Constructing an
environment never opens a database, reads the clipboard, requests notification
permission, or starts a network request.

Startup prepares the repository before starting clipboard, notification, and
window services. Shutdown first flushes all pending repository drafts, then
stops the window, notification, and clipboard services, and finally closes the
repository. A repository that failed before preparation is not flushed or
closed, allowing a failed launch to terminate cleanly. Lifecycle logging accepts
only a closed event enum; there is no API that accepts note source text.

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

`MeaningfulContentPolicy` classifies source as blank, provisional marked text,
or meaningful. Empty source and source containing only spaces, tabs, or
newlines are blank. A valid mode alias without a title or non-whitespace body is
also control-only blank content; a titled header, a header with body text, or an
invalid alias is meaningful. The standard alias set is explicit and later
custom alias settings replace that set rather than adding parser conditionals.

IME marked text updates the visible in-memory source but cannot make a note
durable until the text system commits the composition. The AppKit editor sends
both its exact `NSTextView.string` and `hasMarkedText()` state to the note
session. A committed meaningful edit retains the transient UUID and schedules
the exact source through the debounced repository. Returning to blank cancels
the pending draft; navigation, hide, window close, and termination also remove
any row that may already have been published for that now-empty note.

### Navigation, Ordering, And Deletion

Repositories return notes by descending `orderKey`. Previous moves toward an
older note and next moves toward a newer note. Moving next beyond the newest
durable note creates exactly one transient blank note; moving previous from
that blank returns to the newest durable note. Oldest and repeated blank-edge
operations are idempotent.

Every navigation, jump, and promotion first cancels the pending application
save task, classifies the latest committed editor source, schedules or discards
that source, and flushes the repository before reading the destination order.
The transient-to-durable transition keeps the same UUID. Command-1 loads the
newest note. Command-Shift-1 promotes the current note by assigning a new
transactional monotonic `orderKey`; timestamps never determine tie order.

Command-left-bracket and Command-right-bracket use the same previous/next
session operations as horizontal two-finger gestures. The editor accumulates
horizontal-dominant deltas and emits one navigation at a 60-point threshold.
After a switch, the editor enters a one-shot directional state: Down or Right
places the caret at source start, while Up or Left places it at source end.
Other key input cancels the state and ordinary caret movement resumes.

Command-D discards a blank note immediately. A meaningful note uses a
Cancel-first AppKit sheet unless the persisted suppression preference is set.
Return activates Cancel, Delete is marked destructive, and checking "Do not ask
again" takes effect only after a confirmed deletion. Settings exposes an
in-app reset for the suppression preference. Confirmed deletion removes the
active row and its FTS row; recovery remains a backup-restore operation.

### Cross-Note Search

`NoteSearchModel` is the single owner of the cross-note search presentation,
query generation, loaded pages, selected result, loading state, and error state.
Command-F presents it inside the existing main window and acquires an owned
command-picker suspension token. Dismissal releases that token and explicitly
restores the editor as first responder.

Opening search first asks `WindowCoordinator` to commit marked text, read the
live `NSTextView.string`, prepare the current note, and await its repository
flush. The initial empty query therefore includes the edit that immediately
preceded Command-F. Each query change cancels the prior task and advances a
generation token; a late page can update visible results only if both generation
and normalized query still match.

Search reads `NoteSearchPage` values in 50-note pages. Empty input covers all
active rows in working order. Nonempty input uses the persistence search policy
below. Result presentation derives an 80-character first-line title, a bounded
context excerpt, and modification date without changing note source. Identical
titles remain distinguishable by context and date.

The focused native `NSSearchField` intercepts Up, Down, Enter, and Escape through
`NSControlTextEditingDelegate`, because the AppKit field editor receives these
commands instead of the search field view itself. Each result has a native
`NSAccessibility` button representation whose label includes title, context,
and modification time and whose value reports selection. Enter calls the same
`promoteAndOpen(noteID:)` session operation as Command-Shift-1, preserving UUID
and using one transactional monotonic ordering update.

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

`LifecycleSettings` is versioned and stores new-note-on-launch, the reopen
policy (`always`, 3 minutes, 30 minutes, 1 hour, 1 day, or `never`), and note
count visibility, plus delete-warning suppression. The last-window-close date
uses a separate UserDefaults key and is recorded by the window-close path rather
than inferred from process termination. Threshold comparisons are inclusive; a
backward clock change does not create a new note.

The Step 3.3 `MathSettings` version-1 payload stores only result digits and the
independent thousands-grouping switch. Step 3.4 migrates it to version 2 by
supplying defaults for primary and secondary currency, primary symbol, automatic
refresh, and custom rates, then rewriting the decoded payload. Version 2 rejects
digits outside `0...7`, currencies absent from the bundled ISO fixture, malformed
symbols, nonpositive or same-currency custom rates, duplicate directed pairs,
and more than 128 custom rates. Unsupported or malformed payloads fall back to
defaults, and a failed write rolls the published application value back.

`PasteSettings` is stored in a separate versioned UserDefaults payload. The
composition root loads it before the window coordinator creates the editor and
publishes later changes to both the active editor and the store. Preview and
test environments use an injected in-memory store. The five fields remain
independent; no preset or aggregate switch mutates another field.

Window presentation state is persisted independently from lifecycle state as a
versioned `WindowConfiguration`. It stores presentation mode, application
presence, pin, auto-hide, and dropdown dimensions under one UserDefaults key.
The global shortcut is not duplicated in that payload: KeyboardShortcuts owns
its versioned binding, while `ValidatedGlobalShortcut` preflights replacements
and keeps the previous binding when registration fails.

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
- run integrity and note/FTS parity checks through the pool's writer connection
  so the check observes the latest committed WAL state instead of a stale reader
  snapshot;
- use FTS5 `unicode61` token matching for ordinary queries and a deterministic
  literal `instr(body, query)` fallback when the query contains CJK scalars;
- execute search pages with a bounded `LIMIT` of at most 200 and one look-ahead
  row for `hasMore`, so the UI never materializes the full result set before its
  first frame;
- migrations are forward-only and tested from every shipped schema;
- no UI code constructs SQL;
- database access occurs through one `DatabasePool`.

The first forward migration adds a nonnegative `source_revision` column with a
zero default. This version lets asynchronous projections reject stale results
without changing note identity or working order.

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

The production AppKit host performs no parsing in `textDidChange`. It captures
the new source and UTF-16 version, immediately reports the source to the note
session, then submits a snapshot to `ProjectionParsePipeline`. The pipeline is
an actor that cancels the prior request, parses in a detached user-initiated
task, and gates completion by both request identity and source version. A final
validator discards out-of-bounds decorations and emits source-free diagnostics.
Pipeline telemetry contains only counters, versions, durations, and decoration
counts; it never contains note text.

Selection and vertical scroll offset remain source-coordinate metadata on each
note. Navigation flushes those values with the source, and a monotonically
increasing restoration token reapplies them only when a different note is
loaded. Visible adornments are overlay views above the text layout and children
of one native accessibility group named `Editor decorations`; neither the views
nor their accessible labels enter `Note.body` or the undo manager.

Performance budgets:

- synchronous edit processing: p95 below 4 ms;
- ordinary line projection: p95 below 8 ms;
- full-note math projection for 10,000 lines: below 150 ms off-main;
- no parser task may block text input.

### 6.6 Link Presentation

Link detection is a cancellable, source-versioned projection operation. The
detector accepts only structurally valid HTTP and HTTPS URLs with a non-empty
host. Opening repeats the same validation immediately before passing the URL to
`NSWorkspace`; unsupported, malformed, whitespace-bearing, and control-bearing
values produce no open action.

A `code` mode header disables link detection for the complete note. Backtick
and tilde fenced-code ranges, including unclosed fences through end of source,
are excluded before link decorations are emitted. These exclusions are active
before the later Markdown presentation step and never rewrite source.

Each detected link separates four values:

- the exact source URL used for copy and open;
- a deterministic shortened label made from host, optional port, and a `/...`
  tail hint;
- a one-based occurrence index for the same exact source URL;
- a stable identity made from the SHA-256 digest of the exact URL bytes and the
  occurrence index.

The occurrence index and its visible `· n` suffix remain stable across edits
that do not add, remove, or reorder the same source URL. The suffix remains
visible in shortened and expanded presentations. SHA-256 here is an identity
and privacy boundary, not an authenticity claim: persisted display state does
not duplicate a note's plaintext URL.

The link overlay yields to source while a caret is at either URL boundary or
inside the URL, or while a selection intersects it. It appears only after the
selection leaves the source range. Automatic shortening off shows the full
source URL through the same overlay; all-hyperlink features off rebuilds the
projection without link decorations and disables every link action. The two
settings are independent versioned `EditorSettings` values loaded before the
window creates its editor.

Click and Command-click open the validated exact URL. Command-Shift-click
toggles the identity in a note-UUID-scoped set without changing `Note.body`,
text storage, selection, or undo history. The expanded-state store is a
separate versioned UserDefaults payload containing only note UUIDs, URL
digests, and occurrence indexes. It survives navigation and relaunch; a link's
context menu copies the exact source URL.

### 6.7 Markdown And Code Presentation

`LimitedMarkdownParser` recognizes only the documented source grammar: heading
levels one through three, `**bold**`, `*italic*`, `~~strikethrough~~`,
`__underline__`, single-backtick inline code, backtick or tilde fenced code, and
lines whose first non-whitespace characters are `//`. Unsupported headings,
quotes, triple emphasis, Markdown links, and every other syntax remain ordinary
source. Code spans and fences exclude nested Markdown parsing; an unclosed fence
owns source through end of note.

The parser emits UTF-16 source ranges and semantic `TextStyle` decorations.
`ProjectionEditorContainer` maps those styles to TextKit temporary attributes
only. Fonts, colors, backgrounds, strike, underline, and syntax token colors
never enter `NSTextStorage`, `Note.body`, copy output, or undo history. Comment
lines are excluded before checkbox and calculation decorations are emitted.

Command-slash sends `toggleComment:` through the first responder. The line
command clamps the current source selection, expands it to complete CRLF-aware
line ranges, inserts `// ` after indentation or removes the existing marker,
and maps the source-coordinate selection across all changes. The editor applies
the result as one `NSTextView` replacement, producing one Undo and one Redo
action for a current line or multiline selection. Marked IME text blocks the
command rather than forcing an early commit.

`CodeContextParser` recognizes a case-insensitive first-line `code` header with
an optional colon language. Missing language uses the configured default;
unknown explicit language is plain text. Fences accept matching backtick or
tilde runs of at least three characters and a supported language alias. Swift,
Python, JavaScript, TypeScript, JSON, shell, and plain text are explicit; the
built-in highlighter is behind `CodeSyntaxHighlighting`, returns source ranges
only, and resolves strings and comments before numbers and keywords.

Code notes suppress ordinary Markdown and every link decoration. A selection
inside a fenced range also disables link handling and leading-whitespace
stripping for normal paste; raw paste remains unchanged. Contextual copy from a
code note returns its whole body before inline-backtick rules, while fenced-code
copy returns only the fenced body. `EditorSettings` version 2 stores default
language and highlight theme beside the existing independent link preferences;
version-1 payloads decode with code defaults without losing link choices.

### 6.8 Find And Replace

`FindReplaceEngine` operates only on an immutable source snapshot and returns
UTF-16 `SourceRange` values. Contains and whole-word matching use escaped
regular expressions, line-prefix and line-suffix matching inspect line content
without its terminator, and regular-expression mode compiles the user's pattern
before any mutation is planned. Case sensitivity is an independent request
field for every mode. Foundation's finite match enumeration handles zero-length
regular-expression results without an application-managed cursor loop.

`FindReplaceModel` owns panel state, validation errors, the selected source
match, and forward/backward wrapping. Replace Current compares the live editor
source with the snapshot before changing it and advances beyond the inserted
replacement even when that replacement still matches the query. Replace All
builds one complete replacement source by applying matched ranges in reverse,
then asks `NSTextView` for one full-source replacement. The result is one editor
undo action; an invalid expression produces no plan and cannot mutate source.

`EditorFindReplaceTarget` is the only bridge to the production editor. It reads
the live source and selection, applies bounded source-coordinate replacements,
and temporarily asks the existing link projection to treat every link identity
as expanded. Dismissal removes only that temporary policy, so automatic
shortening and note-scoped manual expansion return to their prior states and no
presentation value enters source or persistence.

Command-Shift-F and Command-F own mutually exclusive panels and share the
window coordinator's command-picker auto-hide suspension. Native AppKit fields
route Enter and Shift-Enter to next/previous match in the find field and to
Replace/Replace All in the replacement field. Tab reveals and focuses replace;
Escape dismisses and restores editor focus. The panel stays inside the main
window instead of creating a second window or persistence owner.

### 6.9 Copy Decision Table

Priority:

1. Non-empty selection -> selection export projection.
2. Caret inside inline code -> inline-code source.
3. Caret inside fenced code block -> block source without fences when policy
   requires.
4. Caret on/clicked result -> canonical result.
5. Otherwise -> whole-note clean export projection.

Each branch has unit and integration tests.

`ProjectionTextView` intentionally enables Copy through responder-chain
validation even when the selection is empty. Otherwise AppKit disables the
menu item before the no-selection branches can run. A non-empty source
selection still wins when a result or link adornment's copy button is used.
Clean whole-note export removes only configured control syntax, retains an
optional mode title, expands visual links back to their source URL, and leaves
other user whitespace unchanged.

### 6.10 Paste Pipeline

```text
Pasteboard payload
  -> type selection
  -> string decoding
  -> line-ending normalization
  -> optional number stripping
  -> optional bullet stripping
  -> optional leading-whitespace stripping
  -> optional Markdown stripping
  -> optional blank-line stripping
  -> one editor replacement
  -> one undo group
```

Raw paste uses only payload decoding and line-ending normalization.

Type selection prefers a plain string, then HTML, then RTF. HTML and RTF style
is discarded during decoding, while an attributed hyperlink becomes either its
full URL or `label (URL)`. The normal path also applies the same smart-link rule
to Markdown links. Both normal and raw paths finish with one `NSTextView`
replacement, so one Undo restores the complete pre-paste source and one Redo
reapplies it.

Command-Shift-V sends `pasteRaw:` through the first responder. Both paste
actions remain enabled when a handler exists so unsupported or unreadable
pasteboard content reaches the pipeline and produces a source-free `Paste
Failed` alert instead of silently doing nothing. Clipboard text is never passed
to lifecycle logging or diagnostics.

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

### Alias Registry And Slash Picker

`ModeID` is the stored canonical identity and has eight stable values: `plain`,
`list`, `math`, `sum`, `average`, `count`, `code`, and `timer`. Versioned
`ModeSettings` owns every alias set, exactly one main slash alias per mode, and
the global interpretation switch. `ModeAliasRegistry` normalizes aliases with
POSIX case folding and canonical Unicode composition, then rejects unsupported
versions, missing or repeated modes, empty or invalid aliases, duplicate aliases,
cross-mode collisions, and a main alias outside its owning set. A custom alias
therefore changes only lookup and presentation; it cannot create a new mode or
silently change canonical behavior.

`ModeHeaderParser` recognizes only the first source line. It returns the
canonical ID, matched alias, optional title, and UTF-16 alias, header, and body
ranges. The same parser feeds projection, code-context copy and paste, link
suppression, clean export, and meaningful-content classification. Turning the
master switch off makes apparent headers ordinary source everywhere without
rewriting the note. Loading settings during application startup updates that
classification policy without incrementing the editor revision, so a stored
note cannot be mistaken for prelaunch input.

`SlashCommandEngine` allows `/` at an empty line start or at the alias start of
an existing first-line mode header. Filter state lives in `SlashCommandModel`,
outside `NSTextView`, `Note.body`, SQLite, and the undo manager. Up, Down, Tab,
Return, Escape, Backspace, printable text, and visible number keys route through
the editor while the picker is active. Selection creates one source-coordinate
edit plan: it replaces only an existing alias and preserves its title, inserts
at source start when invoked from a later empty line, or inserts directly at an
empty first line. The editor checks the expected source, performs one bounded
replacement in one undo group, and restores focus after dismissal.

The picker is a height-bounded, scrollable in-window overlay with SF Symbols,
the source-free filter value, selected-row state, and native accessibility
labels and values. It owns a reference-counted command-picker auto-hide
suspension. Search, find/replace, Settings, window hide/close, app resignation,
settings changes, and shutdown dismiss it and release that suspension. The
versioned UserDefaults store validates before writing; Settings keeps invalid
drafts visible with an explicit conflict error and leaves the last valid
registry active.

### List Mode

`ListModeParser` runs only when `ModeHeaderParser` resolves the first source
line to canonical mode ID `list`. It scans the header's UTF-16 body range and
emits a `ListModeItem` for every non-empty content line except a leading-
whitespace `//` comment or a Markdown heading at levels one through three.
Blank lines remain untouched separators, and four or more leading hashes are
ordinary item content.

The checked marker belongs to `ModeSettings.checklistTrigger`. Registry
validation rejects an empty marker, leading or trailing whitespace, embedded
whitespace, and control characters. A line is checked only when the exact
configured marker is separated from item content by horizontal whitespace and
ends the line, allowing trailing spaces or tabs. Marker recognition therefore
never consumes a literal marker embedded in user text.

Projection converts each item into a source-coordinate checkbox decoration.
The item text and optional marker remain in `NSTextStorage`; a gutter control is
laid out beside the first item glyph and exposes native `AXCheckBox`, `Checked`,
and `Unchecked` semantics without contributing source characters, copy text, or
selection offsets. A list header disables calculation and conversion result
decorations for the complete note.

Pointer activation and Space on a focused gutter checkbox both call
`ListModeTogglePlanner`. The planner validates the expected source and exact
item range, inserts ` <marker>` at the content-line end or removes only the
recognized whitespace-plus-marker range, and maps the current UTF-16 selection
across that single bounded edit. The editor applies the plan as one replacement
and one undo group; Undo and Redo restore both exact source and selection.

Clean export independently controls marker omission through
`EditorSettings.omitsChecklistTriggersOnExport`. When enabled, it reparses the
current List Mode body with the current marker and removes markers only from
eligible list items. Disabling the setting preserves all markers. Changing the
configured marker invalidates and reparses projection and export state, but
never migrates, normalizes, or rewrites existing source or SQLite/FTS content.

### Math

The frozen Basic Math grammar is `docs/math/GRAMMAR_V1.md`, identified as
`fornow-math-expression-v1`. `BasicMathDocumentParser` runs only when the first
source line resolves through the current `ModeSettings` to canonical mode ID
`math`. It ignores the header, comments, lines without a trailing equals sign,
and every non-math mode. Its active pipeline is:

```text
canonical math body line
 -> trailing-equals detection
 -> locale-profile tokenization
 -> expression AST
 -> Decimal evaluation
 -> canonical value + independent display formatting
 -> result decoration or source-free diagnostic
```

The lexer emits UTF-16 source ranges, applies longest-match rules for `**` and
`!!`, validates period-decimal or comma-decimal grouping, and rejects spaces or
tabs used as thousands separators. It recognizes the frozen arithmetic,
percentage, factorial, root, logarithm, ceiling, and floor syntax. One line is
bounded to 512 tokens and 64 parser levels; factorial operands are nonnegative
integers no greater than 1,000.

The Basic Math AST is deliberately platform-neutral:

```swift
indirect enum ExpressionNode {
    case decimal(Decimal)
    case unary(MathUnaryOperator, ExpressionNode)
    case binary(MathBinaryOperator, ExpressionNode, ExpressionNode)
    case function(MathFunctionID, ExpressionNode)
    case percentage(ExpressionNode)
    case factorial(MathFactorialKind, ExpressionNode)
}
```

Ordinary arithmetic, integral powers, percentages, factorials, ceiling, and
floor use Foundation `Decimal` operations and inspect every calculation status.
Roots, logarithms, and non-integral powers alone cross a bounded `Double` bridge;
non-finite input or output and failed conversion back to `Decimal` become stable
diagnostics. Division by zero, domain errors, overflow, underflow, invalid input,
and resource limits never emit a result.

`BasicMathFormatter` keeps two outputs separate. The canonical copy value is
locale-independent, ungrouped, and uses a period decimal separator. Display
rounding uses decimal half-even with zero through seven maximum fractional
digits, while thousands grouping is an independent setting. Neither display
choice changes the AST value or canonical copy value.

`ProductionProjectionParser` maps a successful line to a `.result` anchored
immediately after the source equals sign. The visible button therefore contains
only the formatted result, not a second equals sign. Its accessibility label
announces the source expression and display result. With no source selection,
activation copies the canonical value; the existing section 6.9 priority still
lets a non-empty source selection win. Diagnostics remain separate projection
objects with stable codes, bounded UTF-16 ranges, accessible error messages, and
no source text in telemetry.

Step 3.4 inserts unit and currency target recognition around the unchanged Basic
Math V1 expression engine. Step 3.5 wraps that evaluator in a document-scoped
assignment and dependency pass. The active pipeline is:

```text
source line
 -> assignment candidate and colon-prose disambiguation
 -> whole-document reference graph
 -> dependency substitution
 -> trailing-equals detection
 -> unit/currency target split
 -> Basic Math V1 expression AST and evaluation
 -> conversion
 -> result decoration
```

The conversion parser accepts `in` and `to`, evaluates arithmetic only before
the source unit or currency, and rejects arithmetic after the target. Unit
results use Foundation `Measurement`; currency results resolve a direct custom
rate, then an inverse custom rate, then a provider cross-rate. Display text
includes the target and rate date/state, while copied text contains only the
canonical value and target symbol or code.

Never use `NSExpression`, JavaScript evaluation, `eval`, an LLM, or a network
service for Basic Math.

### Variables

`fornow-variables-v1` rebuilds an immutable graph for every source version:

- assignment declaration nodes;
- longest complete, case-insensitive reference edges with folded whitespace;
- forward and backward references in stable source order;
- a duplicate-name error policy with no cursor-dependent shadowing;
- depth-first cycle detection;
- topological evaluation;
- a maximum dependency path of 64 and 128 selected declarations;
- transitive dependency IDs attached to result projections.

A first colon creates only an assignment candidate. A name referenced elsewhere
is always selected; otherwise the right side must contain only frozen math,
unit/currency, or declared-variable vocabulary. Other prose continues through
Basic Math, preserving inputs such as `Lunch: $10 + USD 20 dollars =` without
consuming the declaration limit. Conversion declarations retain only their
canonical Decimal value in the graph, so references never inherit unit,
currency, or rate metadata.

`VariableAutocompleteEngine` derives up to nine source-ordered candidates from
an empty Math-body selection after three matching letters or digits. The AppKit
panel is an accessibility group outside `Note.body`; showing or dismissing it
does not mutate source. Tab, displayed number keys, and pointer activation apply
one source/version-validated `NSTextView` replacement. Automatic undo
registration is disabled for that replacement and an explicit inverse action is
registered in its own group, keeping one-step completion Undo separate from the
user's preceding paste or typing.

### Aggregate Modes

`fornow-aggregates-v1` is a complete-note pass selected only by canonical `sum`,
`average`, or `count` mode identity. It runs separately from the line-oriented
Basic Math and variable graph pipelines:

```text
canonical note
 -> mode header and body range
 -> source-ordered non-empty, non-comment body lines
 -> locale numeric extraction or Count eligibility
 -> checked Decimal aggregation
 -> one result anchored after the header + source-free diagnostics
```

Sum and Average extract every locale-valid numeric token after treating text,
currency material, brackets, and punctuation as separators. A malformed number
or unsupported fraction excludes its complete line and produces a stable
diagnostic without excluding later valid lines. Sum with no values is zero;
Average with no values is unavailable. Count does not interpret numeric syntax
and includes every non-empty, non-comment body line, including text, fractions,
and malformed numbers.

The pass checks cancellation every 32 lines and numeric candidates and caps both
body lines and accepted values at 10,000. A single result uses
`BasicMathFormatter` for display and canonical copy, while the header anchor,
diagnostics, fixture expectations, and source ranges remain deterministic. The
versioned bundled extraction fixture validates text, currency, punctuation,
blank/comment lines, invalid numbers, fractions, both locale profiles, and Count
eligibility. Per `FORNOW-DECISION-002`, no Grade Level or Reading Ease formula is
present in ForNow 1.0.

### Unit Aliases

Store aliases in versioned JSON fixtures:

```text
Resources/Units/v1/distance.json
Resources/Units/v1/area.json
Resources/Units/v1/volume.json
Resources/Units/v1/mass.json
Resources/Units/v1/temperature.json
Resources/Currencies/iso-4217-v1.json
```

Each unit fixture contains a schema version, fixed category, canonical unit IDs,
display symbols, and normalized aliases. The currency fixture contains a schema
version, uppercase ISO code, display name, and non-conflicting aliases. Startup
validation rejects missing categories, unsupported schema versions, category
mismatches, duplicate IDs/codes/aliases, malformed codes, and unit IDs without a
runtime mapping. Every documented distance, area, volume, mass, and temperature
ID maps explicitly to a Foundation dimension.

### Currency Rates

`CurrencyRateProvider` has disabled, fixture, cached, and ECB implementations.
The ECB adapter sends a body-free GET only to the fixed daily HTTPS endpoint,
accepts XML, caps the streamed response at 1 MB, disables external entity
resolution, and validates the dated-cube structure, codes, rates, and base
conversion. Note source is never passed into this boundary.

Snapshots and the last automatic-attempt date use a separate versioned
UserDefaults cache. Automatic refresh is off by default, runs in the background
after startup only when enabled, records the attempt before requesting, and
makes at most one attempt per rolling 24 hours. Manual refresh is always an
explicit user command. Network failure may retain a compatible cached snapshot;
cancellation never becomes cached success. A cache age of exactly 24 hours is
stale.

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

`TimerClock` is the actor-owned application timer coordinator. It combines the
state machine with a monotonic live anchor, persists only lifecycle checkpoints,
and publishes immutable snapshots and one-shot events. `TimerModel` consumes
those values on the main actor and independently updates the editor decoration,
status item, notifications, sound, and takeover surfaces.

The editor timer button is enabled only while the current timer is running or
paused. In those states it exposes pause/resume and stop accessibility actions;
completed and cancelled buttons remain visible as source-free history but are
disabled, expose no custom actions, and direct users to the restart command.
Escape and double-click route through the same stop transition. The status item
contains timer text only for running or paused state.

## 8. Window Architecture

### Components

- `SwiftUIWindowCoordinator`: the single AppKit owner of the main window,
  visibility transitions, focus restoration, presentation rebuilds, placement,
  presence, and the global shortcut callback.
- `WindowPresentationPolicy`: resolves the standard `NSWindow`, pseudo-menu
  `NSPanel`, and traditional dropdown `NSPanel` level and Space behavior.
- `WindowVisibilityStateMachine`: pure visibility, pin, auto-hide, and owned
  panel transition policy.
- `ValidatedGlobalShortcut`: KeyboardShortcuts adapter with Carbon preflight and
  diagnostics for conflicts and macOS 15.0/15.1 Option-only failures.
- `WindowPlacement`: active-display placement and visible-frame clamping.

`ForNowApp` does not declare a SwiftUI main `WindowGroup`. It declares Settings
and commands while `SwiftUIWindowCoordinator` creates exactly one main AppKit
window and installs an `NSHostingController` supplied by the composition root.
This avoids competing SwiftUI/AppKit window ownership. The Dock and status-item
surfaces are independently selected by `ApplicationPresenceMode`; Neither mode
keeps navigation, note, visibility, pin, delete, and Settings commands inside
the main window.

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

Show after Command-W reuses the same retained `NSWindow` and reopens the current
`NoteSessionModel`. A presentation-mode change builds a new AppKit projection
but retains that same session model and exact source.

`hide()`:

1. Cancel transient menus.
2. Commit editor source.
3. Flush persistence.
4. Order out or close according to mode.
5. Preserve note and selection identity.

Before hide, close, or presentation rebuild, the coordinator reads the live
`NSTextView.string`, commits marked text, prepares the note session, and awaits
the repository flush. Transitions are serialized so a later toggle cannot pass
an earlier flush. A flush failure leaves or restores the window onscreen rather
than discarding source.

### Auto-Hide Suspension

System panels, settings, command picker, permission prompts, and export dialogs
receive a reference-counted suspension token. Auto-hide resumes only after all
tokens are released. Settings and destructive-delete confirmation use this
contract now. Pin and auto-hide remain independent; a pinned window does not
auto-hide on application focus loss.

### Commands And Performance

Command-O toggles the main window, Command-P toggles pin, and Command-W closes
the key Settings window before it targets the main window. The global shortcut
defaults to Option-A and can be replaced in Settings without losing the prior
binding on validation failure. Hotkey-to-caret timing starts at the global
callback and ends only after the editor becomes first responder. Logging emits
the numeric duration only; note source is never included.

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
- convert each backup copy to `journal_mode=DELETE` and remove its sidecars so
  the published `.sqlite` file is self-contained;
- write to temporary path, verify open/integrity, then atomically rename;
- publish the database before its manifest, treating the manifest as the commit
  marker;
- include schema version, database checksum, canonical note checksum, and note
  count in the manifest;
- remove interrupted hidden backup `.tmp` files when the store opens.

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

`OCRService` accepts immutable image data and versioned `OCRSettings`, validates
the encoded payload, and returns recognized text plus confidence metadata. The
production actor uses `VNRecognizeTextRequest` at accurate recognition level
with language correction. Cancellation is routed to `VNRequest.cancel()` and a
main-actor generation token prevents an obsolete request from inserting.

The AppKit editor recognizes image representations before ordinary paste. It
captures an `EditorOCRInsertionAnchor` containing the current source snapshot
version and UTF-16 replacement range. A Finder drop captures its drop position;
clipboard paste captures the current selection. If source changed before the
result returns, the app asks before inserting at the current selection. An
unchanged result inserts at the captured position as one isolated undo edit.

Clipboard TIFF is decoded and re-encoded to PNG before validation because
AppKit commonly exposes copied images as TIFF. File URL inputs retain their
security-scoped access only while bytes are read. The actual ImageIO type,
dimensions, and GIF frame count remain authoritative; filename extensions and
pasteboard declarations cannot bypass validation.

Limits:

- maximum pixel area: 40,000,000;
- maximum encoded byte size: 20 MiB, checked before and after file reads;
- supported decoded types: PNG, JPEG, and one-frame GIF;
- at most one active request, with replacement and user cancellation;
- automatic, system-preferred, and versioned explicit language choices;
- no image or progress-state persistence and no application-created OCR
  temporary files.

### AutoPaste

`SystemClipboardService` owns the AppKit pasteboard boundary. It creates a
main-run-loop timer only while a session is active, records the current
`NSPasteboard.general.changeCount` as the start baseline, reads only `.string`,
and invalidates the timer, callback, baseline, and owned-write counts on stop.
Production startup therefore performs no clipboard polling.

`AutoPasteModel` owns the single application-wide session and snapshots its
destination note ID, display name, and capture policy. It serializes accepted
events, defers a current-note append while AppKit has IME marked text, and stops
instead of recreating a missing destination. Navigation does not retarget an
active session.

Event acceptance normalizes CRLF/CR and removes NUL, compares change counts,
and retains a FIFO window of 64 SHA-256 content hashes. The monitor separately
retains at most 32 application-owned change counts so editor copies cannot feed
back into the session. Clipboard bodies are not used as history or logs.

Every accepted item is formatted through an immutable session policy and
flushed as canonical note source. The fixed V1 behavior is defined by
`docs/autopaste/AUTOPASTE_V1.md` and `FORNOW-DECISION-015`.

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
