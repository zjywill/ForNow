# ForNow Product Specification

## 1. Product Definition

ForNow is a local-first macOS scratchpad for information that is useful now but
does not yet deserve permanent organization.

It is optimized for:

- temporary calculations;
- meeting fragments;
- short checklists;
- copied snippets and links;
- OCR from screenshots;
- quick timers;
- staging text before exporting it to a permanent destination.

It is not:

- a personal knowledge base;
- a document editor;
- a collaborative workspace;
- a task management platform;
- a cloud account service;
- an AI chat application.

Evidence: `AN-POS-001`, `AN-POS-002`, `AN-AI-001`.

## 2. Product Principles

### PR-001 - Immediate capture

The user must be able to invoke ForNow, type, and dismiss it without navigating
through a document hierarchy.

### PR-002 - Source text integrity

The saved text is always understandable without ForNow. Visual decorations may
enhance it but may not become the only representation of user data.

### PR-003 - Temporary by design, backup protected

The application may remove blank and expired notes automatically, but
periodic backups provide the recovery path for non-empty user data.

### PR-004 - Keyboard first, pointer complete

All frequent workflows are available from the keyboard. Pointer interactions
remain discoverable and accessible.

### PR-005 - Local by default

Typing, calculation, OCR, search, storage, backup, and export work offline.

### PR-006 - Deterministic core

Core behavior is implemented by parsers, state machines, and operating-system
frameworks. A generative model is never required to interpret or preserve a
note.

## 3. Primary User Journeys

### Journey J-001 - Capture and dismiss

1. User presses the global shortcut.
2. ForNow appears in the current workspace.
3. The editor is focused and the insertion point is restored.
4. User types.
5. Autosave commits the change.
6. User presses the shortcut again or focuses another app.
7. ForNow hides according to its configured policy.

References: `AN-WIN-001`, `AN-WIN-003`, `AN-TXT-001`.

### Journey J-002 - Create a disposable note

1. User moves beyond the newest note or invokes New Note.
2. A transient blank note appears immediately.
3. The note is not treated as durable user data until it contains meaningful
   content.
4. If the user leaves it blank, it disappears.
5. If the user types, it receives a durable ID and is saved.

References: `AN-NAV-003`, `AN-NAV-004`.

### Journey J-003 - Return to a recent note

1. User navigates left/right or invokes cross-note search.
2. Current edits are committed before selection changes.
3. The target note appears with its previous selection and scroll position when
   available.
4. Promote moves it to the newest/front position without changing content.

References: `AN-NAV-002`, `AN-NAV-005`, `AN-NAV-006`.

### Journey J-004 - Calculate without leaving the note

1. User selects Math through `/` or enters the configured mode keyword.
2. The parser evaluates complete expression lines.
3. Results appear as non-source editor decorations.
4. Editing an input updates dependent results.
5. Clicking or keyboard-focusing a result copies its canonical value.
6. Saving and exporting preserve source text, not decoration artifacts.

References: `AN-CMD-001`, `AN-CMD-002`, `AN-MATH-001`,
`AN-MATH-004`, `AN-MATH-005`.

### Journey J-005 - Collect clipboard items

1. User explicitly starts AutoPaste.
2. A persistent visual indicator appears.
3. ForNow observes clipboard change identifiers.
4. New text is normalized and appended using the selected capture policy.
5. Duplicate clipboard events are ignored.
6. User stops AutoPaste.
7. Clipboard observation stops immediately.

References: `AN-AUTO-001`, `AN-AUTO-002`.

### Journey J-006 - Promote temporary text to permanent storage

1. User invokes Export.
2. ForNow produces a canonical clean-text projection.
3. User selects a file or supported destination.
4. The destination adapter reports success or a recoverable error.
5. Export never deletes the source note automatically.

References: `AN-EXP-001`, `AN-EXP-002`.

## 4. Functional Requirements

### Application Invocation

#### FR-WIN-001 - Global toggle shortcut

- Source: `AN-WIN-001`.
- The default shortcut is Option-A.
- The shortcut is available while the application process is running.
- The shortcut toggles visibility.
- Show must activate the editor without an extra click.
- Hide must not discard unsaved text.
- The shortcut is user configurable.
- Shortcut conflicts produce a clear error and preserve the previous binding.
- On macOS 15.0 and 15.1, an Option-only registration failure explains the
  platform limitation and recommends adding Command or Control or upgrading to
  macOS 15.2 or newer.

#### FR-WIN-002 - Window modes

- Source: `AN-WIN-002`.
- Support `standard`, `menuBarPanel`, and `dropdownPanel`.
- Window mode changes must not recreate note data.
- Dock and pseudo-menu presence support Dock, Menu Bar, Both, and Neither.
- Neither mode retains in-app access to commands otherwise exposed by the
  system menu.
- Traditional menu dropdown width and height are configurable and clamped to
  the visible screen.

#### FR-WIN-003 - Pin and auto-hide

- Source: `AN-WIN-003`.
- Command-P toggles pin.
- Pin keeps the window above ordinary application windows.
- Auto-hide closes or orders out the panel after focus leaves the app.
- Auto-hide must be suspended while a system panel opened by ForNow is active.

#### FR-WIN-004 - Spaces and full screen

- Source: `AN-WIN-004`.
- Invocation targets the currently active Space.
- Menu-style panels appear above full-screen applications when configured.
- Pinning and full-screen presentation are treated as separate capabilities.
- Moving between displays must keep the window inside a visible screen frame.

#### FR-WIN-005 - Local show, global show, and close

- Source: `AN-WIN-005`.
- Command-W closes the current window.
- Command-O toggles visibility while ForNow is focused.
- The configured global shortcut toggles visibility from other apps.
- All three paths flush pending source edits before hiding or closing.

### Notes

#### FR-NOTE-001 - Durable note identity

- Source: `AN-NAV-001`, `AN-BETA-002`.
- Every non-empty note has a stable UUID.
- IDs do not change when ordering, exporting, restoring, or synchronizing.

#### FR-NOTE-002 - Transient blank note

- Source: `AN-NAV-003`, `AN-NAV-004`.
- A new blank note may exist in memory without immediate persistence.
- Typing meaningful content persists it.
- Leaving it blank removes it without creating a persistent row.

#### FR-NOTE-003 - Navigation

- Source: `AN-NAV-002`, `AN-NAV-007`.
- Previous and next commands have keyboard and trackpad paths.
- Command-left-bracket navigates to the previous note and
  Command-right-bracket navigates to the next note.
- Navigation commits the current edit transaction.
- Boundary behavior is deterministic and covered by tests.
- Immediately after navigation, Down/Right enters at the start and Up/Left
  enters at the end before ordinary caret movement resumes.

#### FR-NOTE-004 - Ordering and promotion

- Source: `AN-NAV-005`.
- Notes maintain a user-visible working order.
- Command-1 jumps to the newest note.
- Command-Shift-1 promotes the current note to the newest position.
- Promote assigns a new monotonic ordering token.
- Equal modification timestamps do not produce unstable ordering.

#### FR-NOTE-005 - Confirmed permanent deletion

- Source: `AN-LIFE-002`.
- Command-D requests deletion.
- A non-empty note requires confirmation unless the user has explicitly
  suppressed the warning.
- Confirmed deletion removes the note from the active store.
- Recovery is available only through backups unless ForNow later adopts a
  separately documented trash improvement.

#### FR-NOTE-006 - Expiration

- Source: `AN-LIFE-001`.
- Expiration choices are today, one week, one month, one year, or never.
- Expiration processing is idempotent.
- A clock change may delay expiration but must not duplicate deletion events.

#### FR-NOTE-007 - Search

- Source: `AN-NAV-006`.
- Command-F opens cross-note search.
- Search covers active non-deleted notes.
- Empty search displays all notes.
- Results show enough context to distinguish similar notes.
- Arrow keys navigate results.
- Enter promotes the result to the front and opens it.
- Escape closes search.
- Search is cancellable and keyboard navigable.

#### FR-NOTE-008 - Find and replace

- Source: `AN-NAV-006`.
- Find operates inside the current source text.
- Replace participates in the editor undo stack.
- Derived decorations are never search or replacement targets.
- Matching modes include contains, whole word, line prefix, line suffix, and
  regular expression, with an independent case-sensitive toggle.
- Opening find/replace temporarily expands shortened links.
- Tab in the search field opens the replace field.
- Enter and Shift-Enter navigate forward/backward in search and perform
  replace/replace-all in the replacement field.

#### FR-NOTE-009 - Resume note policy

- Source: `AN-NOTE-SET-001`.
- Settings control whether launch creates a new note.
- Settings control whether reopening after `always`, 3 minutes, 30 minutes,
  1 hour, or 1 day creates a new note, or never does.
- The last-window-close timestamp is persisted independently from app quit.
- Note-count visibility is configurable.

#### FR-NOTE-010 - Bulk deletion by modification date

- Source: `AN-NOTE-SET-001`.
- Settings accept a cutoff date and preview the number of matching notes.
- Only notes with `modifiedAt` earlier than the confirmed cutoff are deleted.
- Confirmation creates a safety backup before mutation.
- Cancellation or backup failure leaves all notes unchanged.

### Editor

#### FR-EDIT-001 - Plain-text source

- Source: `AN-TXT-001`.
- `Note.body` contains only source text.
- No rendering-only answer or control label may be serialized into `body`.

#### FR-EDIT-002 - Source projection

- Source: `AN-TXT-002`, `AN-TXT-003`, `AN-MATH-001`.
- Parsing produces immutable decorations with source ranges.
- Decorations must survive unrelated edits and be discarded when their source
  range becomes invalid.
- Selection, copy, undo, and accessibility use source coordinates.

#### FR-EDIT-003 - Markdown presentation

- Source: `AN-TXT-002`, `AN-MD-001`.
- Recognize `#`, `##`, and `###` headings, bold, italic, strikethrough,
  underline, inline code, fenced code, and `//` comment lines.
- Command-slash toggles comment state for the current or selected lines.
- Comment lines are excluded from list items and calculations.
- Syntax remains visible enough that exported source is predictable.
- Unsupported Markdown remains ordinary text.

#### FR-EDIT-004 - Link presentation

- Source: `AN-TXT-003`.
- Detect valid HTTP/HTTPS links.
- Automatic display shortening is independently configurable.
- A separate setting disables all hyperlink detection, opening, shortening,
  and link interaction while preserving source text.
- Shortening runs only after the insertion point leaves the URL.
- Clicking opens the exact stored URL.
- Copying returns the exact stored URL.
- Command-click opens the link.
- Command-Shift-click toggles expanded state.
- Manually expanded state persists until toggled again.
- Duplicate displayed URLs receive stable display suffixes.
- Link behavior is disabled in code notes and fenced code blocks.

#### FR-EDIT-005 - Undo

- Source: product-quality requirement derived from all editor functions.
- One user action creates one understandable undo group.
- Parser refresh and decoration updates create no undo entries.
- Checkbox toggles, OCR insertion, replace-all, and paste are undoable.

#### FR-EDIT-006 - International text

- Source: product-quality requirement.
- All ranges are handled as `String.Index` or correctly converted UTF-16
  ranges at AppKit boundaries.
- Chinese input methods, marked text, Emoji, and combining characters must not
  corrupt source ranges.

#### FR-EDIT-007 - Layout direction override

- Source: `FORNOW-DECISION-006`, `FORNOW-DECISION-016`; informed by `AN-REV-002`.
- Settings can force left-to-right or right-to-left text layout; the default
  follows the natural direction of the content.
- The override changes presentation only and never rewrites source text.

### Clipboard

#### FR-CLIP-001 - Contextual copy

- Source: `AN-CLIP-001`.
- With a non-empty selection, copy only the selection.
- Without a selection and with a caret inside inline code, copy the inline code.
- Without a selection and with a caret inside a fenced code block, copy that
  block.
- Otherwise, copy the complete clean export projection.

#### FR-CLIP-002 - Clean projection

- Source: `AN-CLIP-002`.
- Remove mode control lines only when the export policy declares them
  non-content.
- A mode header's optional title after the colon remains content and is
  preserved.
- Expand shortened visual links.
- Preserve user-authored whitespace unless normalization is explicitly part of
  the selected export target.

#### FR-CLIP-003 - Normal paste

- Source: `AN-CLIP-003`.
- Prefer plain string clipboard content.
- Normalize line endings.
- Strip rich-text-only style.
- Apply smart link and whitespace cleanup through separately testable rules.
- Independent settings control stripping of leading whitespace (for example
  tabs), list numbers, bullets, Markdown, and empty lines.

#### FR-CLIP-004 - Raw paste

- Source: `AN-CLIP-003`.
- A separate command inserts source clipboard text with minimal processing.
- It still converts unsafe or unsupported binary payloads into a clear error.

### Commands And Modes

#### FR-CMD-001 - Canonical mode IDs

- Source: `AN-CMD-001`, `AN-CMD-003`.
- Modes have stable IDs such as `plain`, `list`, `math`, `sum`, `average`,
  `count`, `code`, and `timer`.
- User aliases map to IDs and cannot collide silently.
- Each mode has exactly one main alias used by the slash picker.
- A global setting can disable all keyword interpretation without changing
  source text.

#### FR-CMD-002 - Mode header

- Source: `AN-CMD-001`, `FORNOW-DECISION-004`; informed by `AN-REV-001`.
- Only the configured leading region can select a mode.
- Alias matching is case-insensitive by default.
- Invalid keywords remain ordinary content.
- Removing the mode header returns the note to plain mode without data loss.

#### FR-CMD-003 - Slash picker

- Source: `AN-CMD-002`.
- `/` at an eligible location opens a command menu.
- The menu supports keyboard filtering, selection, dismissal, and VoiceOver.
- Number keys select displayed entries.
- Selecting a mode replaces an existing mode header when present.
- Selecting a mode performs one undoable source edit.

#### FR-CMD-004 - Code mode

- Source: `AN-CODE-001`.
- A `code` mode header with an optional language after the colon enables
  syntax highlighting for that language.
- Without a language, the configured default language applies.
- Default language and highlighting theme are configurable settings.
- Code notes disable paste indent stripping and all hyperlink features while
  preserving source text.

### Lists

#### FR-LIST-001 - Line items

- Source: `AN-LIST-001`.
- Non-empty content lines become list items in list mode.
- Blank lines remain meaningful separators.
- Comment lines and heading lines are not list items.
- Math and conversion evaluation is disabled in list mode.

#### FR-LIST-002 - Checkbox toggle

- Source: `AN-LIST-002`.
- Pointer and keyboard actions toggle a source-backed checked marker.
- Toggle is one undo group.
- Toggling does not move the insertion point unexpectedly.

#### FR-LIST-003 - Checked marker and clean copy

- Source: `AN-LIST-003`.
- The trailing checked marker is user configurable.
- A checked marker changes only the corresponding source line.
- Clean copy omits checked markers when the export setting is enabled.
- Changing the configured marker does not silently rewrite existing source.

### Math

#### FR-MATH-001 - Expression parser

- Source: `AN-MATH-001`.
- Arithmetic precedence is deterministic.
- Parse failures show a non-destructive diagnostic.
- Evaluation never modifies source automatically.
- A trailing equals sign requests evaluation.
- The accepted operator/function grammar is versioned and fixture tested.
- Decimal-comma locales are supported.
- Space-separated thousands are rejected in parity mode with a diagnostic.
- Significant-digit display is configurable from zero through seven.
- Thousands-separator display is independently configurable.

#### FR-MATH-002 - Aggregate modes

- Source: `AN-MATH-002`, `FORNOW-DECISION-002`.
- Sum and average consume valid numeric line results.
- Sum and average strip non-numeric text using documented rules.
- Fractions are rejected in parity mode rather than silently miscalculated.
- Count includes each non-empty non-comment line after the header.
- Invalid lines do not crash or poison unrelated results.
- Grade Level and Reading Ease are deferred by `FORNOW-DECISION-002` until a
  versioned formula and independent fixtures exist.

#### FR-MATH-003 - Units

- Source: `AN-MATH-003`.
- Units are parsed after numeric expression evaluation.
- Incompatible dimensions produce a diagnostic.
- Display formatting is locale aware while source interpretation remains
  deterministic.
- Supported categories include distance, area, volume, mass, and temperature.
- A conversion may not be composed with additional arithmetic in parity mode.

#### FR-MATH-004 - Currency

- Source: `AN-MATH-003`.
- Currency conversion is optional network functionality.
- The result identifies rate timestamp and stale-cache state.
- No network means cached rate or a clear unavailable result.
- Primary and secondary currency preferences fill omitted source or target
  codes.
- A configurable primary symbol identifies the primary currency when no code is
  supplied.
- When enabled, remote rates refresh at most once per day; manual and cached
  providers remain usable without automatic refresh.
- User-defined rates override provider rates through explicit precedence.

#### FR-MATH-005 - Variables

- Source: `AN-MATH-004`.
- Assignments create named values.
- References create dependency edges.
- Duplicate names follow a documented nearest-prior or error policy.
- Cycles produce diagnostics rather than infinite evaluation.
- Names may contain spaces.
- Matching autocomplete begins after three characters.
- Tab accepts a sole or first result; displayed number keys accept a specific
  result.
- Conversion assignments retain only numeric values in parity mode.

#### FR-MATH-006 - Result interaction

- Source: `AN-MATH-005`.
- Results can be focused and copied.
- VoiceOver announces expression, result, unit, and error state.
- Results remain absent from persisted source.

### Timer

#### FR-TIME-001 - Persistent timer model

- Source: `AN-TIME-001`, `FORNOW-DECISION-013`.
- Timer state stores type, duration, start instant, accumulated elapsed time,
  state, and linked note ID.
- Display derives from timestamps rather than decrementing persisted counters.
- Timer commands may begin on any new line.
- Supported commands cover stopwatch, decimal-minute and `m:ss` countdown,
  titled countdown, custom work/rest cycle, standard 25/5 cycle,
  pause/resume, restart, and stop.
- Entering `timer` at the beginning of a note displays the command tutorial.

#### FR-TIME-002 - Pause, resume, reset, complete

- Source: `AN-TIME-001`, `FORNOW-DECISION-013`.
- Each transition is validated by a state machine.
- Repeated commands are idempotent or produce a documented no-op.
- Single click pauses/resumes, double-click stops, and Escape stops a running
  timer.

#### FR-TIME-003 - External visibility

- Source: `AN-TIME-002`, `FORNOW-DECISION-013`.
- Active status may appear in the menu bar.
- Completion may produce a local notification after permission is granted.
- Denied notification permission does not break timer completion.
- Settings independently control pause-on-quit, menu-bar display, countdown
  notifications, countdown full-screen takeover, countdown sound, pomodoro
  break notifications, pomodoro break takeover, pomodoro break sound, and
  sound volume from zero through 100 percent.

### OCR

#### FR-OCR-001 - Image input

- Source: `AN-OCR-001`, `FORNOW-DECISION-014`.
- Accept supported clipboard and drag/drop image types.
- Parity formats are JPG, JPEG, PNG, and static GIF.
- Clipboard TIFF representations may be normalized to PNG as transport, but a
  TIFF file remains unsupported.
- Reject animated GIFs, malformed data, images above 20 MiB, and images above
  40 megapixels with a recoverable error.

#### FR-OCR-002 - Local recognition

- Source: `AN-OCR-002`, `FORNOW-DECISION-014`.
- Recognition uses on-device Vision APIs.
- No image or recognized text is transmitted.
- Language selection follows user settings and detected content.
- The default is automatic detection. System-preferred and explicit English,
  Simplified Chinese, Traditional Chinese, Japanese, Korean, French, German,
  and Spanish choices are persistent.
- System-preferred selection maps language families to identifiers explicitly
  supported by the active Vision revision.
- Starting a new request cancels and invalidates the prior request.

#### FR-OCR-003 - Atomic insertion

- Source: `AN-OCR-001`, `FORNOW-DECISION-014`.
- Recognition displays cancellable progress.
- Successful text inserts at the captured source position when still valid,
  otherwise at the current insertion point after user confirmation.
- The final insertion is one undo group.
- Cancellation, an empty result, an invalid UTF-16 range, or active IME marked
  text never creates a partial source edit.

### AutoPaste

#### FR-AUTO-001 - Explicit session

- Source: `AN-AUTO-001`, `FORNOW-DECISION-015`.
- Typing `paste` and pressing Enter starts monitoring.
- A persistent indicator names the destination note.
- Escape, typing `paste` again, or activating the blinking indicator stops it.
- Monitoring also stops on destination deletion or app termination.

#### FR-AUTO-002 - Deduplication

- Source: `AN-AUTO-001`, `FORNOW-DECISION-015`.
- Observe pasteboard change counts.
- Store a bounded hash history for repeated events.
- Copying from ForNow itself does not create an infinite capture loop.

#### FR-AUTO-003 - Capture policy

- Source: `AN-AUTO-002`, `FORNOW-DECISION-015`.
- Policies define prefix, suffix, separator, link treatment, and timestamp
  behavior.
- Newline is the default delimiter.
- A delimiter may be parsed from parentheses after the command.
- Policy formatting has unit tests independent from clipboard observation.

### Export And Recovery

#### FR-EXP-001 - Canonical export document

- Source: `AN-EXP-001`, `AN-CLIP-002`.
- All destinations consume one clean export model.
- Destination adapters may transform the model but not read editor decorations.

#### FR-EXP-002 - File export

- Source: `AN-EXP-001`.
- Support UTF-8 `.txt` and `.md`.
- File writes are atomic and never overwrite without user approval.
- Export-all produces a ZIP containing one text file per exported note.

#### FR-EXP-003 - Application adapters

- Source: `AN-EXP-002`.
- Apple Notes, Bear, and Obsidian are isolated adapters.
- Missing applications produce setup guidance, not silent failure.
- A failed export preserves the source note.
- Command-S invokes the configured quick-export adapter.
- Settings control keyword omission and first-line title behavior.

#### FR-EXP-004 - Custom URL export

- Source: `AN-EXPORT-003`.
- Custom destinations use a versioned template containing only approved URL
  schemes.
- `{CONTENT}`, `{TITLE}`, and `{DATE}` placeholders are substituted from the
  canonical export document and encoded exactly once.
- Query-parameter templates use strict percent encoding.
- For compatibility with documented path templates, ampersands become plus
  signs and percent signs become the literal string ` percent`, including its
  leading space, only inside substituted path content.
- Invalid templates, oversized URLs, or unavailable destinations preserve the
  source note and show a recoverable error.

#### FR-BACK-001 - Backups

- Source: `AN-BACK-001`.
- Create periodic versioned local backups.
- Retention is bounded by count and age.
- Backup creation cannot run concurrently with migration or restore.
- Default policy is every three hours with twelve backups retained.
- Frequency choices are 10 minutes, 30 minutes, 1 hour, 3 hours, 12 hours,
  1 day, 3 days, 1 week, 1 month, or never.
- Settings can reveal the local notes and backup folder.

#### FR-BACK-002 - Restore

- Source: `AN-BACK-001`, `FORNOW-DECISION-001`.
- Validate schema and checksum before restore.
- Create a safety backup of the current store.
- Restore either completes atomically or leaves the current store intact.

### Appearance And Settings

#### FR-UI-001 - Semantic theme

- Source: `AN-UI-001`, `FORNOW-DECISION-016`.
- Themes define semantic colors, not view-specific hard-coded colors.
- Light and dark system appearances store independent theme selections.
- All themes pass text and control contrast checks.

#### FR-UI-002 - Paper style and translucency

- Source: `AN-UI-001`, `FORNOW-DECISION-016`.
- Paper style is independent from color theme.
- Paper choices are blank, lines, dots, small grid, and large grid.
- Paper opacity choices are subtle, clear, and bold.
- List line spacing uses an explicit lined-paper metric and a separate
  blank-paper metric.
- Translucent mode is available only on macOS 15 or newer and exposes background
  opacity from zero through 90 percent.
- A theme whose appearance does not match the current system appearance shows a
  preview warning before translucent mode is enabled.
- Reduced transparency disables or simplifies material effects.

#### FR-UI-003 - Text size and settings validation

- Source: `AN-CMD-003`, `AN-UI-001`, `FORNOW-DECISION-005`, `FORNOW-DECISION-016`.
- Text sizes are XS, S, M, L, and XL, with a separate double-size setting.
- Command-plus and Command-minus increase and decrease text size.
- Quick-action shortcuts (navigation, new note, promote, delete, search, pin,
  text size) are user remappable.
- Shortcut and keyword conflicts are validated before save.
- Invalid custom configuration cannot make the app impossible to invoke.

#### FR-UI-004 - Custom theme import

- Source: `AN-UI-002`.
- Target: `1.x`.
- Custom themes use a documented, versioned JSON schema.
- Settings reveal the custom theme directory and provide an explicit reload
  command.
- Invalid files are isolated with diagnostics and never remove built-in themes.
- Community themes are treated as untrusted local input and receive the same
  validation.

### Automation, Privacy, Updates, And Support

#### FR-URL-001 - Automation routes

- Source: `AN-URL-001`.
- The 1.0 URL router supports open, create with content, append to current,
  overwrite current, promote and open by note ID, toggle pin, and visibility
  toggle.
- Parameters are strictly percent decoded once and have explicit size limits.
- Unknown routes, malformed payloads, and invalid note IDs cause no mutation.
- Mutation routes execute through the same use cases and validation as UI
  commands.

#### FR-URL-002 - Search callback and controlled reload

- Source: `AN-URL-001`.
- Search returns serialized records containing stable note ID, content, and
  last-modified value through an explicitly supplied success callback.
- Callback schemes are allowlisted and callback payload size is bounded.
- Persistence reload is disabled by default, developer scoped, and validates the
  database before replacing visible state.

#### FR-INT-001 - Raycast and Alfred equivalents

- Source: `AN-URL-001`.
- Target: `1.x`.
- Published launcher integrations may create notes with or without content,
  search notes, and toggle pin using only the versioned URL surface.
- Integrations contain no direct database writes and publish setup,
  compatibility, and uninstall instructions.

#### FR-EXT-001 - Extension manifest and runtime

- Source: `AN-EXT-001`.
- Target: `1.x`.
- The manifest schema is versioned and declares name, version, author,
  category, dataScope, endpoints, requiredAPIKeys, dependencies, isService,
  and ordered files.
- The manifest parses and validates before any script executes; invalid
  extensions are quarantined with diagnostics and never affect built-in
  behavior.
- Execution uses a JavaScriptCore ES6 context per invocation with
  sequential file loading.

#### FR-EXT-002 - Extension palette and scopes

- Source: `AN-EXT-003`.
- Target: `1.x`.
- `::` opens the command palette with filtering, typed parameter forms, and
  the four command types: insert, replaceLine, replaceAll, openURL.
- Input scopes none, line, and full are declared per extension, shown to
  users, and enforced with immutable snapshots.
- Command results are source-edit operations carrying status, message, and
  payload; each successful command is one undo group.

#### FR-EXT-003 - Extension network and secrets

- Source: `AN-EXT-002`, `FORNOW-DECISION-010`.
- Target: `1.x`.
- API keys are stored in Keychain and never exposed to JavaScript; the host
  substitutes `{{API_KEY}}` placeholders when executing declared calls.
- Request URLs are parsed and matched against declared scheme, normalized host,
  effective port, and path boundaries; raw string prefix checks are forbidden.
- Redirect targets are revalidated before following. Loopback, private-network,
  file, data, and custom-scheme destinations are denied unless an explicit
  capability permits the exact destination class.
- Extension identity is host-verified and cannot be spoofed.
- Network capability is denied by default without declared endpoints.

#### FR-EXT-004 - Extension bridges and services

- Source: `AN-EXT-004`.
- Target: `1.x`.
- Host bridges (math evaluation, preferences) are versioned APIs backed by
  the shared engines.
- Service extensions export functions through declared dependencies.
- AI access is centralized in one service extension consistent with
  `05_AI_POLICY.md`.

#### FR-UPD-001 - Update consent and controls

- Source: `AN-UPD-001`.
- On the second successful launch, direct-distribution builds ask whether
  automatic update checks may be enabled.
- Manual checking remains available regardless of automatic-check preference.
- Automatic checking and automatic installation are separate settings.
- Declining automatic checks sends no update request and does not prevent later
  opt-in.

#### FR-SUP-001 - Preference reset and diagnostic launch

- Source: `AN-SUP-001`.
- Support documentation provides a supported way to reset preferences without
  deleting notes or backups.
- The application can be launched directly for diagnostic logging.
- Diagnostic logs include no note body, clipboard text, URL payload content, or
  secrets.

#### FR-DIST-001 - Distribution and upgrade preservation

- Source: `AN-DIST-001`, `FORNOW-DECISION-003`.
- Direct signed distribution is required for 1.0.
- A Homebrew cask may be published only after the signed release is stable.
- Setapp is explicitly outside 1.0 scope unless a distribution agreement is
  approved.
- Replacing or updating the application preserves notes, backups, and
  preferences.

#### FR-PRIV-001 - No usage analytics

- Source: `AN-PRIV-001`.
- ForNow 1.0 includes no usage-activity collection or analytics SDK.
- Network inspection during offline core workflows must show no analytics
  request.

## 5. State Models

### Application Visibility

```text
hidden -> showing -> focused -> hiding -> hidden
                    |      |
                    |      +-> systemPanelActive
                    +-> backgroundVisible (pinned)
```

Rules:

- Only one visibility transition runs at a time.
- Hiding flushes pending note edits.
- Opening a save panel, settings window, or permission panel suspends auto-hide.

### Note Lifecycle

```text
transientBlank -> activePersisted -> pendingDeleteConfirmation
       |                 |                         |
       +-> discarded     +-> expired               +-> permanentlyDeleted
                               |
                               +-> permanentlyDeleted
```

Rules:

- `transientBlank` has no database or backup entry.
- `pendingDeleteConfirmation` changes no data until confirmed.
- Explicit and expiration deletion remove the active record.
- Recovery of deleted content is performed through a database backup, not a
  note-level trash state.

### Timer Lifecycle

```text
idle -> running -> paused -> running
  |        |          |
  |        +-> completed
  +-> cancelled

completed -> reset -> idle
```

### AutoPaste Lifecycle

```text
inactive -> requestingAccess -> active -> stopping -> inactive
                                   |
                                   +-> destinationUnavailable -> inactive
```

## 6. Data Retention And Privacy

- Note text stays local in 1.0.
- OCR is on-device.
- Clipboard observation is session scoped.
- Currency conversion is the only planned 1.0 feature that may use a network
  provider, and it is optional.
- No analytics SDK is included in 1.0.
- Crash reports, if later added, are opt-in and must remove note text.
- API keys for future integrations are stored in Keychain.
- AI provider access is absent from core 1.0.

## 7. Explicit Non-Goals For 1.0

- Collaboration and sharing.
- End-to-end encrypted cloud sync.
- iPhone and iPad clients.
- JavaScript extension execution.
- Generative rewrite, summarize, translate, or chat.
- Attachments other than transient OCR image input.
- Folders, backlinks, tags, graph views, publishing, and web access.

## 7.1 Documented Automation Surface

The 1.0 automation contract is defined by `FR-URL-001` and `FR-URL-002`.
Launcher-specific packaging is post-1.0 under `FR-INT-001`.

## 8. Product Completion Definition

ForNow 1.0 is product-complete only when:

1. Every 1.0 `FR-*` requirement is implemented or explicitly deferred.
2. Every implemented requirement maps to passing tests in the test matrix.
3. The Phase 0 editor and window prototypes have been integrated, not replaced
   by unvalidated alternatives.
4. Backup restore has passed a destructive rehearsal using disposable data.
5. No core workflow requires an account, network, or generative model.
6. A new user can invoke, type, navigate, calculate, copy, and dismiss the app
   using only the keyboard.
