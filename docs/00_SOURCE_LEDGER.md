# AntiNote Evidence Ledger

## Purpose

This file prevents implementation by assumption. It records what AntiNote
officially documents, what was observed on its live website, and what remains
an inference. ForNow requirements and implementation tasks cite these evidence
IDs rather than relying on memory.

Research date: **2026-08-02**

## Evidence Levels

- `A`: Explicitly documented in the official user manual.
- `B`: Explicitly described on an official product, changelog, press, or
  extension page.
- `C`: Engineering inference based on documented behavior. It must be
  validated by a prototype and must never be presented as an AntiNote fact.

## Authoritative Sources

- User manual: https://antinote.io/user-manual
- Product page: https://antinote.io/
- Changelog: https://antinote.io/changelog
- Extensions: https://antinote.io/extensions
- Press kit: https://antinote.io/presskit
- Extension repository:
  https://github.com/johnsonfung/antinote-extensions

The official manual is authoritative for stable interaction behavior. The
changelog is authoritative for version-specific and beta behavior. Marketing
copy may explain intent but does not override the manual.

## Product Intent

### AN-POS-001 - Temporary scratchpad, not permanent archive

- Level: `A/B`
- Source: Product page; manual introduction; press kit.
- Confirmed behavior: Notes are intended for temporary working thoughts and
  are designed to complement a permanent note system.
- ForNow consequence: Do not make folders, tags, backlinks, or knowledge graph
  features part of 1.0.

### AN-POS-002 - Local-first storage

- Level: `A/B`
- Source: Product FAQ; press kit; manual storage section.
- Confirmed behavior: Stable desktop notes are stored locally. Export is the
  path into permanent systems.
- ForNow consequence: Core 1.0 has no login and no required network service.

### AN-POS-003 - Native and lightweight

- Level: `B`
- Source: Press kit.
- Confirmed behavior: AntiNote describes itself as a native Swift/SwiftUI
  application with local SQLite storage.
- ForNow consequence: Use native macOS frameworks and avoid Electron/WebView
  application architecture.

## Note Lifecycle And Navigation

### AN-NAV-001 - Single-note primary surface

- Level: `A`
- Source: User manual, navigation and notes sections.
- Confirmed behavior: The main experience is one active note rather than a
  permanently visible notebook sidebar.
- ForNow consequence: The editor remains the primary surface. Search and note
  management appear on demand.

### AN-NAV-002 - Previous and next note navigation

- Level: `A`
- Source: User manual, navigation section.
- Confirmed behavior: Users navigate between nearby notes using horizontal
  gestures and keyboard commands.
- Confirmed detail: Command-left-bracket goes to the previous note and
  Command-right-bracket goes to the next note.
- ForNow consequence: Provide both trackpad and keyboard navigation.

### AN-NAV-003 - Create at the newest edge

- Level: `A`
- Source: User manual, creating notes section.
- Confirmed behavior: Moving beyond the newest note creates a new blank note.
- ForNow consequence: The newest-edge gesture is a creation command, not an
  inert overscroll effect.

### AN-NAV-004 - Empty notes are disposable

- Level: `A`
- Source: User manual, deleting notes section.
- Confirmed behavior: Blank notes are removed automatically when abandoned.
- ForNow consequence: A blank draft must not accumulate in storage.

### AN-NAV-005 - Recency and promotion

- Level: `A`
- Source: User manual, promote/jump-to-front section.
- Confirmed behavior: Notes can be moved to the front of the working order.
- Confirmed detail: Command-1 jumps to the newest note and Command-Shift-1
  promotes the current note.
- ForNow consequence: Store explicit recency/order metadata rather than
  deriving all order only from creation time.

### AN-NAV-006 - Search and find/replace

- Level: `A`
- Source: User manual, search and find/replace sections.
- Confirmed behavior: Users can search across notes and find or replace inside
  the current note.
- Confirmed detail: Cross-note search uses Command-F, arrow keys move through
  results, Enter promotes the selected result to the front, and Escape closes
  search.
- Confirmed detail: Find/replace uses Command-Shift-F and supports case
  sensitivity, contains, whole-word, line-prefix, line-suffix, and regex
  matching. Opening it expands all links.
- ForNow consequence: Cross-note search and in-note find are separate commands,
  separate UI states, and separate acceptance-test groups.

### AN-NAV-007 - Cursor entry after navigation

- Level: `A`
- Source: User manual, "Entering a note after swiping".
- Confirmed behavior: After note navigation, Down or Right enters at the start
  of the note; Up or Left enters at the end.
- ForNow consequence: Navigation focus has a deliberate pre-edit state. Arrow
  keys are directional entry commands before ordinary caret movement resumes.

## Window And Invocation

### AN-WIN-001 - Global hotkey

- Level: `A/B`
- Source: User manual, global hotkey section; product page.
- Confirmed behavior: A configurable global shortcut shows the scratchpad from
  other applications.
- Confirmed detail: The documented default is Option-A and the application must
  already be running.
- Confirmed detail: Option-only shortcuts are unavailable on macOS 15.0 and
  15.1, restored in 15.2, and can be worked around by adding Command or Control.
- ForNow consequence: Invocation must work without first activating the app
  through Dock or menu bar, and registration failures need OS-specific
  diagnostics.

### AN-WIN-002 - Multiple presence modes

- Level: `A/B`
- Source: User manual, interface settings; product page.
- Confirmed behavior: Dock, menu, and dropdown-style presentation modes are
  supported.
- Confirmed detail: Dock, pseudo menu, both, and neither are selectable.
  Traditional menu mode uses a dropdown whose width and height are configurable.
- Confirmed detail: In neither mode the system menu is absent, so equivalent
  commands remain available inside the application.
- ForNow consequence: Window placement and application presence must be
  modeled independently from note content.

### AN-WIN-003 - Pin and close on focus loss

- Level: `A`
- Source: User manual, pin and auto-close settings.
- Confirmed behavior: The window may remain above other windows or hide when
  focus moves elsewhere.
- Confirmed detail: Command-P toggles pin.
- ForNow consequence: Pinning and auto-close are explicit, persisted settings.

### AN-WIN-004 - Full-screen application support

- Level: `A/B`
- Source: User manual, app management; product page.
- Confirmed behavior: Pseudo Menu and Traditional Menu modes can show over
  full-screen applications. Pin itself is documented as not supporting full
  screen. "Neither" mode has a documented full-screen exit bug in v1.1.7.
- ForNow consequence: Test collection behavior separately for each presence
  mode. Do not use one generic "full-screen supported" requirement.

### AN-WIN-005 - Show, hide, and close commands

- Level: `A`
- Source: User manual, "Close and open window".
- Confirmed behavior: Command-W closes the window, Command-O toggles it while
  focused, and the global hotkey toggles it from any application. The window
  appears in the currently active Space.
- ForNow consequence: `close`, `localToggle`, and `globalToggle` are separate
  actions even if they share visibility-state transitions.

## Text, Clipboard, And Links

### AN-TXT-001 - Plain text is the underlying format

- Level: `A/B`
- Source: User manual, text formatting section; product page.
- Confirmed behavior: The product presents lightweight formatting while
  retaining a plain-text-oriented workflow.
- ForNow consequence: Persist source text and derive visual presentation.

### AN-TXT-002 - Markdown-aware presentation

- Level: `A`
- Source: User manual, text formatting section.
- Confirmed behavior: Common Markdown syntax receives visual treatment.
- ForNow consequence: Formatting is syntax-aware but ForNow is not a general
  rich-text document editor.

### AN-TXT-003 - Link shrinking

- Level: `A/B`
- Source: User manual, links section; product page.
- Confirmed behavior: Long links may be shown in shortened form while
  retaining the original destination.
- Confirmed detail: Links shorten only after the caret leaves them.
- Confirmed detail: Command-click opens a link. Command-Shift-click toggles
  expanded/shortened state, and manually expanded state persists.
- Confirmed detail: Duplicate URLs receive a visible numeric suffix.
- Confirmed detail: Link features are disabled in code notes and fenced code
  blocks.
- Confirmed detail: Settings independently disable automatic shortening or all
  hyperlink behavior.
- ForNow consequence: Display text, stored URL, duplicate display identity, and
  per-link expansion state must remain separable.

### AN-CLIP-001 - Copy selection or whole note

- Level: `A`
- Source: User manual, copy section.
- Confirmed behavior: Copy uses the selection when one exists; otherwise it
  copies the complete note.
- Confirmed detail: With no selection, a caret inside a fenced code block
  copies that block; a caret inside backticks copies the inline-code content.
- ForNow consequence: Command-C with no selection is intentionally overridden
  through an explicit context-priority decision table.

### AN-CLIP-002 - Clean exported clipboard text

- Level: `A`
- Source: User manual, copy section.
- Confirmed behavior: Whole-note copy removes mode/control syntax where
  appropriate and expands shortened links.
- ForNow consequence: Implement a deterministic `ExportProjection` instead of
  copying rendered attributed text.

### AN-CLIP-003 - Normalized and raw paste paths

- Level: `A`
- Source: User manual, paste section.
- Confirmed behavior: Normal paste cleans incoming content; a modified paste
  command preserves the original text more closely.
- ForNow consequence: Paste normalization is a reversible policy with a
  separate raw-paste command.

## Command And Mode System

### AN-CMD-001 - First-line keyword selects note behavior

- Level: `A`
- Source: User manual, keywords section.
- Confirmed behavior: A keyword at the beginning of a note selects a
  specialized interpretation mode.
- ForNow consequence: Parsing starts with a mode header grammar.

### AN-CMD-002 - Slash command picker

- Level: `A`
- Source: User manual, slash command section.
- Confirmed behavior: A slash-triggered interface helps users insert or switch
  modes.
- Confirmed detail: Each mode has one main alias shown by the slash picker.
  Number keys select entries and an existing mode keyword is replaced.
- ForNow consequence: Mode discovery must not rely on memorizing keywords.

### AN-CMD-003 - Customizable keywords and shortcuts

- Level: `A/B`
- Source: User manual settings; product page.
- Confirmed behavior: Keywords and shortcuts can be customized.
- Confirmed detail: All keyword behavior can be disabled from settings.
- ForNow consequence: Separate canonical mode IDs from user-facing aliases.

## Lists

### AN-LIST-001 - List conversion

- Level: `A`
- Source: User manual, list section.
- Confirmed behavior: A list mode turns lines into a lightweight list
  workflow.
- ForNow consequence: List parsing is line based and mode scoped.

### AN-LIST-002 - Interactive checklist items

- Level: `A`
- Source: User manual, list/checklist sections.
- Confirmed behavior: List items can be checked and unchecked.
- ForNow consequence: Checkbox interaction must mutate only the corresponding
  source line and remain undoable.

### AN-LIST-003 - Checked-item operations

- Level: `A`
- Source: User manual, list and copy sections.
- Confirmed behavior: Every non-empty line becomes a checklist item. A
  configurable trailing trigger such as `/x` marks an item checked and is
  omitted from copied text.
- Confirmed detail: Lines beginning with `//`, `#`, `##`, or `###` are not
  checklist items.
- Confirmed detail: Math and conversions are disabled in list notes.
- ForNow consequence: Checklist eligibility and copied output are deterministic
  line-parser policies.

## Calculations

### AN-MATH-001 - Contextual inline calculations

- Level: `A/B`
- Source: User manual, calculations section; product page.
- Confirmed behavior: Expressions typed in notes can produce contextual
  results.
- Confirmed detail: A trailing equals sign requests evaluation. Words,
  punctuation, and currency symbols are stripped where applicable.
- Confirmed detail: Operators include ordinary arithmetic, powers,
  parentheses, percentages, factorial-like operations, square/cube roots,
  logarithms, ceiling, and floor.
- Confirmed detail: Decimal-comma locales are supported, while space-separated
  thousands are documented as unsupported in v1.1.7.
- Confirmed detail: Significant digits are configurable from zero through
  seven and thousands-separator display can be toggled.
- ForNow consequence: Calculation results are editor decorations linked to
  source ranges, with a versioned and testable grammar.

### AN-MATH-002 - Aggregate modes

- Level: `A`
- Source: User manual, sum/average/count sections.
- Confirmed behavior: `sum` and `avg` strip non-numeric material and aggregate
  numbers. Fractions are documented as unsupported. `count` counts every
  non-empty line after the mode header, excluding comment lines.
- ForNow consequence: Aggregate evaluation receives the complete note model,
  while ordinary math evaluates line by line.

### AN-MATH-003 - Units and conversions

- Level: `A/B`
- Source: User manual, conversions section; product page.
- Confirmed behavior: Unit and contextual conversions are supported.
- Confirmed detail: Currency rates update daily, primary/secondary currency
  settings fill omitted codes, a configured bare symbol identifies the primary
  currency, and custom rates are supported.
- Confirmed detail: Distance, area, volume, mass, and temperature conversions
  accept multiple aliases and symbols.
- Confirmed limitation: A conversion cannot be embedded inside a larger
  arithmetic calculation in v1.1.7.
- ForNow consequence: Keep numeric expression parsing separate from unit and
  currency conversion providers, and make the unsupported-composition rule
  explicit.

### AN-MATH-004 - Reactive variables

- Level: `A/B`
- Source: User manual, reactive variables section; product page.
- Confirmed behavior: Named values can be referenced by later expressions and
  dependent answers react to changes.
- Confirmed detail: Names may contain spaces. Autocomplete appears after at
  least three matching characters; Tab and number keys select suggestions.
- Confirmed detail: Conversion results stored in variables retain only their
  numeric value, not unit or currency metadata.
- ForNow consequence: Build a dependency graph, detect cycles, evaluate in
  stable source order, and model autocomplete independently from evaluation.

### AN-MATH-005 - Result interaction

- Level: `A`
- Source: User manual, calculations section.
- Confirmed behavior: A displayed answer can be copied through direct
  interaction.
- ForNow consequence: Decorations require accessibility labels, pointer
  interaction, and keyboard alternatives.

## Timers

### AN-TIME-001 - Countdown and stopwatch workflows

- Level: `A`
- Source: User manual, timer section.
- Confirmed behavior: Timer-oriented commands support countdown and elapsed
  time workflows.
- Confirmed detail: `timer` starts a stopwatch; decimal or `m:ss` values start a
  countdown; two numeric values start work/rest cycles; `timer pomo` starts
  25/5; `p`, `r`, `s`, and `0` pause/resume, restart, and stop.
- Confirmed detail: Timer commands may begin any new line rather than requiring
  the first line.
- Confirmed detail: Click pauses, double-click stops, and Escape stops a running
  timer.
- ForNow consequence: Timer state is persistent application data, not merely a
  UI animation, and command parsing is line-scoped.

### AN-TIME-002 - Timer visibility outside the editor

- Level: `A/B`
- Source: User manual, timer behavior; product page.
- Confirmed behavior: Active timer status can remain visible outside the note.
- Confirmed detail: Settings independently control quit-time pausing, menu-bar
  time, end notification, full-screen takeover, sound, pomodoro break behavior,
  and volume.
- ForNow consequence: Menu bar state, notifications, takeover presentation,
  and sound consume the same timer model as the editor.

## OCR And Clipboard Capture

### AN-OCR-001 - Screenshot or image to text

- Level: `A/B`
- Source: User manual, screenshot-to-text section; product page.
- Confirmed behavior: Pasted or dropped images can be converted to text.
- Confirmed detail: v1.1.7 documents JPG, JPEG, PNG, and static GIF input.
- ForNow consequence: Use local Vision recognition, validate the documented
  formats, and insert a single undoable text edit at the current insertion
  point.

### AN-OCR-002 - Local processing

- Level: `A`
- Source: User manual, OCR privacy description.
- Confirmed behavior: OCR is described as local and does not require sending
  note content to a server.
- ForNow consequence: OCR must remain on-device in 1.0.

### AN-AUTO-001 - Explicit AutoPaste mode

- Level: `A/B`
- Source: User manual, AutoPaste section; product page.
- Confirmed behavior: While enabled, clipboard changes are appended into the
  active note.
- Confirmed detail: Typing `paste` and pressing Enter starts the mode. Escape,
  typing `paste` again, or clicking the blinking icon stops it.
- ForNow consequence: Clipboard monitoring is active only during an explicit
  session and must show a persistent, actionable indicator.

### AN-AUTO-002 - Configurable capture formatting

- Level: `A`
- Source: User manual, AutoPaste settings.
- Confirmed behavior: Captured items have configurable separators or formatting
  behavior.
- Confirmed detail: The default delimiter is a newline; a delimiter can be
  supplied in parentheses, such as `paste(, )`.
- ForNow consequence: Model capture formatting as a parsed policy, not
  hard-coded string concatenation.

## Export, Expiration, And Recovery

### AN-EXP-001 - Plain-text export

- Level: `A`
- Source: User manual, export section.
- Confirmed behavior: Notes can be exported as text-oriented files.
- ForNow consequence: A portable, human-readable export path is mandatory.

### AN-EXP-002 - Export to permanent note tools

- Level: `A/B`
- Source: User manual, export section; product FAQ.
- Confirmed behavior: Notes can be sent to Apple Notes, Obsidian, and Bear.
- ForNow consequence: Integrations are adapters over one canonical export
  projection.

### AN-LIFE-001 - Automatic expiration

- Level: `A/B`
- Source: User manual, auto-delete section; product page.
- Confirmed behavior: Notes may be automatically deleted after a configured
  period.
- ForNow consequence: Expiration is based on explicit timestamps and runs
  safely at launch and while active.

### AN-LIFE-002 - Confirmed permanent deletion

- Level: `A`
- Source: User manual, navigation delete section.
- Confirmed behavior: Command-D permanently deletes the current note after a
  confirmation warning. The warning can be suppressed and reset through a
  defaults command.
- ForNow consequence: Exact parity uses confirmed permanent deletion. A
  recoverable trash would be a deliberate ForNow improvement and must be
  labeled as such rather than attributed to AntiNote.

### AN-BACK-001 - Periodic backup

- Level: `A`
- Source: User manual, storage and backup sections.
- Confirmed behavior: The application performs periodic local backups and
  exposes backup management.
- Confirmed detail: The documented default is every three hours with the newest
  twelve retained. Frequency choices are 10 minutes, 30 minutes, 1 hour,
  3 hours, 12 hours, 1 day, 3 days, 1 week, 1 month, or never. Retention count
  is configurable and settings can reveal the notes/backup folder. Manual
  restore replaces the current SQLite file while the app is quit.
- ForNow consequence: Backups must be atomic, versioned, restore-tested, and
  compatible with an in-app safer restore workflow.

### AN-NOTE-SET-001 - Launch and inactivity note settings

- Level: `A`
- Source: User manual, notes storage settings.
- Confirmed behavior: Users can create a new note on launch, start a new note
  after the window has been closed for a selected duration, show note count,
  and bulk-delete notes unmodified since a selected date.
- Confirmed detail: Expiration choices are today, one week, one month, one
  year, or never.
- ForNow consequence: New-note-on-resume is a policy driven by the last window
  close timestamp, not merely application launch.

### AN-MD-001 - Limited Markdown

- Level: `A`
- Source: User manual, simple Markdown.
- Confirmed behavior: Headings, bold, italic, strikethrough, underline, and
  `//` comments receive lightweight behavior. Command-slash toggles comments
  for current or selected lines.
- ForNow consequence: Implement only the documented subset in parity scope.

### AN-URL-001 - Automation URL schemes

- Level: `A`
- Source: User manual, URL schemes.
- Confirmed behavior: Schemes open the app, create, append, overwrite, promote
  and open by note ID, toggle pin, trigger the hotkey, search with callback
  JSON, and reload the database after external changes.
- ForNow consequence: Define a versioned URL routing layer and reject unknown or
  malformed commands without mutating data.

### AN-EXPORT-003 - Quick export behavior

- Level: `A`
- Source: User manual, export.
- Confirmed behavior: Command-S invokes the configured quick destination.
  Destinations include plain text, Markdown, Obsidian, Bear, Apple Notes, and
  custom URL schemes. Export-all creates a ZIP containing text files.
- Confirmed detail: Settings control keyword omission, first-line title use,
  Obsidian vault, and custom placeholders for content, title, and date.
- Confirmed detail: Custom templates substitute `{CONTENT}`, `{TITLE}`, and
  `{DATE}`. When content occupies a URL path, ampersands become plus signs and
  percent signs become the literal string ` percent` (including its leading
  space) to match the documented compatibility behavior.
- ForNow consequence: Build one canonical export payload followed by isolated
  destination adapters.

### AN-PRIV-001 - Usage tracking disabled in v1.1.7

- Level: `A`
- Source: User manual, usage activity.
- Confirmed behavior: The manual states that v1.1.7 no longer tracks usage
  activity.
- ForNow consequence: ForNow 1.0 includes no usage analytics.

### AN-UPD-001 - Update consent and controls

- Level: `A`
- Source: User manual, updates section.
- Confirmed behavior: On the second launch the application asks whether it may
  check automatically for updates. Users may also check manually.
- Confirmed detail: Automatic checking and automatic installation are separate
  settings.
- ForNow consequence: Update consent, checking, and installation must remain
  separate state and test surfaces.

### AN-SUP-001 - Preference reset and diagnostic launch

- Level: `A`
- Source: User manual, terminal commands section.
- Confirmed behavior: Preferences can be reset without deleting notes, and the
  application executable can be launched directly to expose diagnostic logs.
- ForNow consequence: Support instructions must distinguish preferences from
  note data, and logs must never include note bodies.

### AN-DIST-001 - Distribution and upgrade preservation

- Level: `A`
- Source: User manual, download methods section.
- Confirmed behavior: Direct, Homebrew, and Setapp distribution are documented
  for AntiNote. Replacing an installed application version preserves its
  license, notes, and preferences.
- ForNow consequence: ForNow upgrades must preserve notes and preferences.
  Distribution channels are a ForNow release decision rather than behavioral
  parity.

## Appearance And Accessibility

### AN-UI-001 - Themes and paper treatments

- Level: `A/B`
- Source: Product page; user manual appearance settings.
- Confirmed behavior: Separate light-mode and dark-mode themes, translucency,
  paper treatments, and text-size controls are supported.
- Confirmed detail: Paper choices are blank, lines, dots, small grid, and large
  grid, with subtle, clear, and bold opacity. List spacing differs on lined
  paper.
- Confirmed detail: Text sizes are XS, S, M, L, and XL, with optional double
  size and Command-plus/minus adjustment.
- Confirmed detail: Translucent mode requires macOS 15 or newer and exposes a
  background opacity range from 0 through 90 percent.
- ForNow consequence: Use semantic color tokens and independent paper-style
  configuration.

### AN-UI-002 - Custom theme ecosystem

- Level: `A/B`
- Source: User manual, product theme maker, and public extension repository.
- Confirmed behavior: Custom and community themes are supported.
- Confirmed detail: A JSON theme is placed in the custom theme directory and
  loaded through an explicit reload command.
- ForNow consequence: Theme import is a later feature with a versioned schema.

### AN-ACC-001 - Keyboard-centered workflow

- Level: `A/B`
- Source: User manual shortcut references across features.
- Confirmed behavior: Core workflows have keyboard commands.
- ForNow consequence: Every pointer action requires an equivalent keyboard
  path where practical.

## ForNow Product Decisions

These entries describe deliberate ForNow behavior. They are not AntiNote facts.

### FORNOW-DECISION-001 - Guarded in-app backup restore

- Decision: ForNow 1.0 provides a validated in-app restore flow in addition to
  documenting manual file replacement.
- Reason: Schema validation, an emergency backup, and atomic rollback reduce
  avoidable data-loss risk.
- Constraint: The exported backup remains an ordinary local SQLite artifact and
  can still be restored manually while the app is quit.

### FORNOW-DECISION-002 - Count reading metrics deferred

- Decision: ForNow 1.0 implements the documented item count but does not claim
  parity for Grade Level or Reading Ease.
- Reason: The manual explicitly notes formula variation without defining the
  formula used.
- Revisit: Add a versioned formula and independent fixtures before exposing
  reading metrics.

### FORNOW-DECISION-003 - Distribution channels are product specific

- Decision: Direct signed distribution is required for 1.0 and Homebrew follows
  after the signed release is stable. Setapp is not a 1.0 requirement.
- Reason: Setapp availability depends on a commercial distribution agreement,
  not application behavior.
- Constraint: Every supported upgrade path preserves notes and preferences.

## Sync, Slots, And Extensions

### AN-BETA-001 - Slotted notes

- Level: `B`
- Source: Changelog, 2.0 beta entries.
- Confirmed behavior: Beta versions add stable, directly addressable note
  slots alongside recency-based notes.
- ForNow consequence: Reserve `slotIndex` in the model but defer UI until 1.x.

### AN-BETA-002 - iCloud and iOS work

- Level: `B`
- Source: Changelog and product FAQ.
- Confirmed behavior: Beta development includes iCloud synchronization and iOS
  support.
- ForNow consequence: Keep identity and persistence sync-ready, but do not make
  sync a 1.0 dependency.

### AN-EXT-001 - Manifest-based JavaScript extensions

- Level: `B`
- Source: Extensions page and public extension repository.
- Confirmed behavior: Extensions declare metadata, command triggers, input
  scope, and code.
- ForNow consequence: A future extension manifest must be versioned and parsed
  before script execution.

### AN-EXT-002 - Restricted network and secret access

- Level: `B`
- Source: Extensions page.
- Confirmed behavior: Extension networking and API secrets are explicitly
  configured rather than implicitly available.
- ForNow consequence: Use endpoint allowlists, Keychain-backed secrets, and
  denied-by-default capabilities.

## AI

### AN-AI-001 - Generative AI is not a core note dependency

- Level: `A`
- Source: User manual FAQ/search result for AI.
- Confirmed behavior: The official manual states that core note content is not
  sent to AI services and the core app does not require generative AI.
- ForNow consequence: No generative model is allowed in the 1.0 critical path.

### AN-AI-002 - OCR is local machine learning, not generative AI

- Level: `A`
- Source: User manual, OCR section.
- Confirmed behavior: Image text recognition is performed locally using
  platform vision capabilities.
- ForNow consequence: Describe OCR accurately as on-device recognition, not as
  an AI assistant feature.

## Open Questions

The following behavior is not sufficiently specified by public documentation
and must not be invented:

- Exact swipe velocity and distance thresholds.
- Exact note ordering tie-break rules.
- Exact cursor behavior around every rendered answer and shortened link.
- Exact math grammar and precedence for every natural-language expression.
- Exact normalization rules for all pasted HTML and rich text sources.
- Exact conflict behavior for simultaneous iCloud edits.
- Exact timer persistence behavior across shutdown and clock changes.
- Exact accessibility behavior of rendered answers and checklist controls.

Each open question must be resolved by one of:

1. An explicit product decision for ForNow.
2. A controlled trial observation recorded with date and version.
3. A technical prototype followed by a documented design decision.
