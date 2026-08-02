# AntiNote v1.1.7 Manual Walkthrough

## Purpose

This is a section-by-section implementation reference based on the official
AntiNote user manual as reviewed on 2026-08-02. It is a paraphrased behavior
index, not a copy of the manual. The linked official section remains the
authority.

For every row:

- `Evidence` describes AntiNote v1.1.7.
- `ForNow scope` says when the behavior should be implemented.
- `Requirement` points to the controlling ForNow specification.
- If the manual does not specify an edge case, it must be entered in the open
  questions register instead of guessed.

## Basics

### Navigation

Source: https://antinote.io/user-manual#navigation

#### Swipe

- Evidence: Two-finger horizontal swipes and Command-bracket shortcuts navigate
  previous/next.
- Evidence: Passing the newest edge creates a note; leaving an empty note
  deletes it automatically.

#### Jump To Front

- Evidence: Command-1 jumps to the newest note.

#### Promote

- Evidence: Command-Shift-1 promotes the current note.

#### Delete

- Evidence: Command-D permanently deletes after a warning.

#### Entering A Note

- Evidence: Immediately after navigation, Down/Right enters at the start;
  Up/Left enters at the end.

- ForNow scope: Alpha.
- Requirement: `FR-NOTE-002` through `FR-NOTE-005`, `FR-NOTE-003`.

### Global Hotkey

Source: https://antinote.io/user-manual#global-hotkey

- Evidence: Default is Option-A and can be customized.
- Evidence: The app must already be running.
- Evidence: Option-only global shortcuts were unavailable on macOS 15.0 and
  15.1 and restored in 15.2; adding Command or Control is the workaround.
- ForNow scope: Alpha.
- Requirement: `FR-WIN-001`.
- Test note: Include OS-version-specific registration diagnostics.

### Link Shortening

Source: https://antinote.io/user-manual#link-shortening

- Evidence: Shortening is visual; full source remains stored and copied.
- Evidence: Shortening waits for the caret to leave the URL.
- Evidence: Command-click opens; Command-Shift-click expands or shortens.
- Evidence: Manual expansion persists.
- Evidence: Duplicate URLs receive a display suffix.
- Evidence: Code notes and Markdown code blocks disable link features.
- Settings: disable auto-shortening; disable all hyperlink features.
- ForNow scope: 1.0 editor phase.
- Requirement: `FR-EDIT-002`, `FR-EDIT-004`.

### Copy

Source: https://antinote.io/user-manual#copy

- Evidence: Whole-note copy omits the mode keyword by default but retains an
  optional title.
- Evidence: Checklist triggers are omitted by default.
- Evidence: Links copy in expanded form.
- Evidence: Clicking math results copies the result.
- Evidence: With no selection, contextual priority is inline code, fenced code
  block, then whole note.
- Settings: omit keywords; omit checklist triggers.
- ForNow scope: 1.0 editor phase.
- Requirement: `FR-CLIP-001`, `FR-CLIP-002`, `FR-MATH-006`.

### Paste

Source: https://antinote.io/user-manual#paste

- Evidence: Normal paste removes formatting, list numbering/bullets, and line
  edge whitespace according to settings.
- Evidence: Markdown and empty-line stripping are optional.
- Evidence: Command-Shift-V bypasses transformations.
- Settings: leading whitespace, list number, bullet, Markdown, and empty-line
  stripping are independent switches.
- ForNow scope: 1.0 editor phase.
- Requirement: `FR-CLIP-003`, `FR-CLIP-004`.

## Keywords

### Intro

Source: https://antinote.io/user-manual#keywords

#### Keyword Activation

- Evidence: A keyword in the first line activates a specialized note mode.

#### Optional Title

- Evidence: A colon adds a visible title.

#### Customize Keywords

- Evidence: Each mode may have multiple aliases but one main slash-menu alias.
- Settings: customize aliases; disable all keywords.

#### Slash Command

- Evidence: Slash at the beginning of a line opens the main keyword list.
- Evidence: Number keys choose a command and an existing keyword is replaced.

- ForNow scope: 1.0 command phase.
- Requirement: `FR-CMD-001` through `FR-CMD-003`.

### List

Source: https://antinote.io/user-manual#list

- Evidence: `list` activates the mode and a colon adds a title.
- Evidence: Every non-empty eligible line becomes a checklist item.
- Evidence: A configurable trailing trigger checks an item.
- Evidence: `//` creates a non-item comment.
- Evidence: `#`, `##`, and `###` create non-item headings.
- Evidence: Math and conversions are disabled in list notes.
- ForNow scope: 1.0 mode phase.
- Requirement: `FR-LIST-001` through `FR-LIST-003`.

### Math

Source: https://antinote.io/user-manual#math

- Evidence: `math` activates the mode; a colon adds a title.
- Evidence: `//` excludes a line.
- Evidence: A trailing equals sign requests calculation.
- Evidence: Grammar includes arithmetic, alternate multiply/divide symbols,
  powers, parentheses, colloquial percentages, roots, logarithms, ceiling,
  floor, and factorial-like operations.
- Evidence: Decimal-comma locales are supported.
- Evidence: Space-separated thousands are not supported in v1.1.7.
- Settings: significant digits from 0 through 7; thousands separator toggle.
- ForNow scope: 1.0 math phase.
- Requirement: `FR-MATH-001`.

### Currency Conversion

Source: https://antinote.io/user-manual#math

- Evidence: Source and target currency codes can be explicit.
- Evidence: A bare configured symbol implies the primary currency.
- Evidence: Missing target implies conversion from primary to secondary.
- Evidence: Rates update daily and custom rates are supported.
- Evidence: Conversion cannot be combined with further arithmetic in v1.1.7.
- Settings: update daily, custom rates, primary symbol, primary currency,
  secondary currency.
- ForNow scope: 1.0 optional-network phase.
- Requirement: `FR-MATH-004`.
- Dataset rule: Currency codes and aliases must live in a versioned fixture,
  with provenance and update date.

### Measurement Conversion

Source: https://antinote.io/user-manual#math

- Evidence: Categories include distance, area, volume, mass, and temperature.
- Evidence: Multiple names, abbreviations, symbols, regional spellings, and
  regional units are accepted.
- Evidence: Conversion cannot be combined with further arithmetic in v1.1.7.
- ForNow scope: 1.0 math phase.
- Requirement: `FR-MATH-003`.
- Dataset rule: Unit aliases are data fixtures, not parser conditionals.

### Variables

Source: https://antinote.io/user-manual#math

- Evidence: A name may be assigned a literal or calculated value.
- Evidence: Dependencies update reactively.
- Evidence: Names may contain spaces.
- Evidence: Autocomplete begins after three matching characters.
- Evidence: Tab chooses a sole/first match; number keys choose displayed
  alternatives.
- Evidence: A conversion assignment stores its numeric result but drops unit or
  currency metadata.
- ForNow scope: 1.0 math phase after basic calculations and conversions.
- Requirement: `FR-MATH-005`.

### Sum

Source: https://antinote.io/user-manual#sum

- Evidence: `sum` scans numbers after stripping other material.
- Evidence: Comment lines are excluded.
- Evidence: Fractions are not supported in v1.1.7.
- ForNow scope: 1.0 aggregate phase.
- Requirement: `FR-MATH-002`.

### Average

Source: https://antinote.io/user-manual#average

- Evidence: `avg` averages detected numbers.
- Evidence: Comment lines are excluded.
- Evidence: Fractions are not supported in v1.1.7.
- ForNow scope: 1.0 aggregate phase.
- Requirement: `FR-MATH-002`.

### Count

Source: https://antinote.io/user-manual#count

- Evidence: `count` counts each non-empty line after the first.
- Evidence: Comment lines are excluded.
- Evidence: The UI also discusses reading-ease metrics whose exact formula can
  differ between products.
- ForNow scope: Item count in 1.0; reading metrics deferred by
  `FORNOW-DECISION-002`.
- Requirement: `FR-MATH-002`.

### Code

Source: https://antinote.io/user-manual#code

- Evidence: `code` activates snippet mode.
- Evidence: A language after the colon selects syntax highlighting.
- Evidence: Missing language uses a configured default.
- Evidence: Syntax theme is configurable.
- Evidence: Contextual no-selection copy copies the current code block.
- Evidence: Indent stripping and hyperlink features are disabled.
- ForNow scope: 1.0 code phase.
- Requirement: `FR-EDIT-003`, `FR-CLIP-001`.

## Extras

### Search

Source: https://antinote.io/user-manual#search

- Evidence: Empty query shows all notes.
- Evidence: Query filters to notes containing the term.
- Evidence: Command-F opens; arrows navigate; Enter promotes and opens; Escape
  closes.
- ForNow scope: Alpha.
- Requirement: `FR-NOTE-007`.

### Find And Replace

Source: https://antinote.io/user-manual#find-and-replace

- Evidence: Supports case toggle, contains, whole word, line prefix, line
  suffix, and regex.
- Evidence: Opening expands all links.
- Evidence: Command-Shift-F opens.
- Evidence: Enter/Shift-Enter semantics change by search versus replacement
  field.
- ForNow scope: 1.0 editor phase.
- Requirement: `FR-NOTE-008`.

### Screenshot To Text

Source: https://antinote.io/user-manual#screenshot-to-text

- Evidence: Dragging or pasting an image inserts recognized plain text.
- Evidence: Processing uses local Apple Vision without a server.
- Evidence: Accepted formats are JPG, JPEG, PNG, and static GIF.
- ForNow scope: 1.0 integration phase.
- Requirement: `FR-OCR-001` through `FR-OCR-003`.

### AutoPaste

Source: https://antinote.io/user-manual#autopaste

- Evidence: Entering `paste` starts capture.
- Evidence: Copied text is appended as plain text.
- Evidence: Newline is default; parentheses define a custom delimiter.
- Evidence: Escape, repeated command, or blinking-icon click stops capture.
- ForNow scope: 1.0 integration phase.
- Requirement: `FR-AUTO-001` through `FR-AUTO-003`.

### Timer

Source: https://antinote.io/user-manual#timer

- Evidence: Timer commands may occur at the start of any new line.
- Evidence: Supports stopwatch, countdown, titled countdown, custom work/rest,
  standard 25/5, pause/resume, restart, and stop.
- Evidence: Single click pauses; double-click and Escape stop.
- Settings: quit-time pause, menu-bar display, end notification, full-screen
  takeover, sound, pomodoro break equivalents, and volume.
- ForNow scope: 1.0 timer phase.
- Requirement: `FR-TIME-001` through `FR-TIME-003`.

### Simple Markdown

Source: https://antinote.io/user-manual#simple-markdown

- Evidence: Supports three heading levels, bold, italic, strikethrough,
  underline, and comment lines.
- Evidence: Comments are excluded from lists and calculations.
- Evidence: Command-slash toggles comments for current/selected lines.
- ForNow scope: 1.0 editor phase.
- Requirement: `FR-EDIT-003`.

### URL Schemes

Source: https://antinote.io/user-manual#url-schemes

- Evidence: Parameters must be percent encoded.
- Evidence: Routes cover open, create, append, overwrite, promote/open, pin
  toggle, hotkey trigger, search callbacks, and database reload.
- Evidence: Search callback returns note ID, content, and last-modified value.
- ForNow scope: 1.0 after stable persistence APIs.
- Requirement: `FR-URL-001`, `FR-URL-002`.

## Themes And Visuals

### Color Themes

Source: https://antinote.io/user-manual#themes

- Evidence: Separate themes can be selected for light and dark system modes.
- ForNow scope: 1.0 visual phase.
- Requirement: `FR-UI-001`.

### Theme Maker

Source: https://antinote.io/user-manual#theme-maker

- Evidence: Custom themes are JSON files placed in a theme directory and
  reloaded from settings.
- Evidence: Community themes are distributed separately.
- ForNow scope: 1.x.
- Requirement: `FR-UI-004`.

### Paper Types

Source: https://antinote.io/user-manual#paper-types

- Evidence: Blank, lined, dotted, small-grid, and large-grid paper.
- Evidence: Paper opacity has subtle, clear, and bold choices.
- Evidence: List line spacing differs between lined and blank paper.
- ForNow scope: 1.0 visual phase.
- Requirement: `FR-UI-002`.

### Text Size

Source: https://antinote.io/user-manual#text-size

- Evidence: Five named sizes and a double-size setting.
- Evidence: Command-plus/minus adjusts size.
- ForNow scope: 1.0 visual and accessibility phase.
- Requirement: `FR-UI-003`.

### Translucent Mode

Source: https://antinote.io/user-manual#translucent-mode

- Evidence: Beta feature for macOS 15+ using native material.
- Evidence: Background opacity is adjustable from 0 to 90 percent.
- Evidence: Appearance depends on matching system light/dark mode.
- ForNow scope: 1.0 after opaque themes pass contrast testing.
- Requirement: `FR-UI-002`.

## App Management

### Pin

Source: https://antinote.io/user-manual#pin-antinote

- Evidence: Command-P toggles always-on-top.
- Evidence: Pin is documented as not supporting full screen in v1.1.7.
- ForNow scope: Alpha.
- Requirement: `FR-WIN-003`, `FR-WIN-004`.

### Close And Open

Source: https://antinote.io/user-manual#close-and-open

- Evidence: Command-W closes; Command-O toggles while focused; global hotkey
  toggles from anywhere.
- Evidence: Multiple-Space invocation appears in the active Space.
- ForNow scope: Alpha.
- Requirement: `FR-WIN-005`.

### Dock, Menu, Neither

Source: https://antinote.io/user-manual#dock

- Evidence: Dock, pseudo menu, both, or neither are supported.
- Evidence: Neither removes the system menu; functions remain available inside
  the app.
- Evidence: Pseudo and traditional menu modes show over full-screen apps.
- Evidence: Auto-close applies while unfocused and unpinned.
- ForNow scope: Alpha for standard/pseudo; traditional dropdown in 1.0.
- Requirement: `FR-WIN-002` through `FR-WIN-004`.

### Traditional Menu Bar

Source: https://antinote.io/user-manual#traditionalMenuBar

- Evidence: Beta mode drops a note panel from the menu bar icon and supports
  full-screen apps.
- Evidence: Width and height are configurable.
- ForNow scope: 1.0 window phase after standard panel stability.
- Requirement: `FR-WIN-002`, `FR-WIN-004`.

### Raycast And Alfred

Source: https://antinote.io/user-manual#raycast-alfred

- Evidence: Existing integrations create notes, search, and toggle pin.
- ForNow scope: 1.x, implemented over URL schemes.
- Requirement: `FR-INT-001`.

### Download Methods

Source: https://antinote.io/user-manual#downloadMethods

#### Direct

- Evidence: Overwriting an application version preserves license, notes, and
  preferences.

#### Homebrew

- Evidence: A Homebrew cask is documented.

#### Setapp

- Evidence: Setapp distribution is documented for AntiNote.

- ForNow scope: Direct distribution in 1.0; Homebrew after signed-release
  stability; Setapp excluded by `FORNOW-DECISION-003`.
- Requirement: `FR-DIST-001`.

### Terminal Commands

Source: https://antinote.io/user-manual#terminal-commands

#### Reset All Preferences

- Evidence: Preferences can be reset separately from notes.

#### Launch With Logs

- Evidence: Direct executable launch exposes logs for debugging.

- ForNow scope: Release engineering.
- Requirement: `FR-SUP-001`.

## Notes Management

### Storage

Source: https://antinote.io/user-manual#notes-storage

- Evidence: Stable v1.1.7 notes are local SQLite data and not sent to a server.
- Evidence: Notes may be exported individually or in bulk.
- Settings: new note on launch; bulk delete by last modification date; new note
  after configured closed duration; note-count display.
- ForNow scope: Alpha persistence and 1.0 settings.
- Requirement: `FR-NOTE-001`, `FR-NOTE-009`, `FR-NOTE-010`.

### Expiration

Source: https://antinote.io/user-manual#expiring-notes

- Evidence: Unmodified notes auto-delete after a selected duration.
- Settings: today, one week, one month, one year, or never.
- ForNow scope: 1.0 lifecycle phase.
- Requirement: `FR-NOTE-006`.

### Auto-Backup

Source: https://antinote.io/user-manual#auto-backup

- Evidence: Default backup interval is three hours and default retention is
  twelve copies.
- Evidence: Frequency and retention are configurable.
- Evidence: Manual recovery replaces the SQLite file while the app is quit.
- ForNow scope: Alpha backup foundation; in-app restore in 1.0.
- Requirement: `FR-BACK-001`, `FR-BACK-002`,
  `FORNOW-DECISION-001`.

## Export

### Quick Export

Source: https://antinote.io/user-manual#quick-export

- Evidence: Command-S triggers the configured destination.
- Evidence: Default is plain text.
- Settings: destination, keyword omission, first-line-as-title.
- ForNow scope: 1.0 export phase.
- Requirement: `FR-EXP-001` through `FR-EXP-003`.

### Send To

Source: https://antinote.io/user-manual#quick-export

#### Export To Plain Text

- Evidence: Plain text writes a `.txt` file.

#### Export To Markdown

- Evidence: Markdown writes a `.md` file.

#### Send To Obsidian

- Evidence: Obsidian uses a URL scheme.
- Evidence: Obsidian supports a target vault.

#### Send To Bear

- Evidence: Bear uses a URL scheme.

#### Send To Apple Notes

- Evidence: Apple Notes uses Apple Shortcuts.

- ForNow scope: 1.0, with adapters delivered independently.
- Requirement: `FR-EXP-002`, `FR-EXP-003`.

### Custom Export

Source: https://antinote.io/user-manual#export-custom

- Evidence: Custom URL schemes substitute content, title, and date.
- Evidence: Special escaping is required when content is placed in a URL path.
- ForNow scope: 1.0 export phase after URL-template security review.
- Requirement: `FR-EXP-004`.

### Export All

Source: https://antinote.io/user-manual#export-all

- Evidence: Bulk export produces a ZIP of text files.
- ForNow scope: 1.0 recovery/export phase.
- Requirement: `FR-EXP-002`.

## Privacy And Updates

### Updates

Source: https://antinote.io/user-manual#updates

- Evidence: Automatic update checks are offered after the second launch.
- Evidence: Checking and installing are separate settings.
- ForNow scope: Release engineering.
- Requirement: `FR-UPD-001`.

### Usage Activity

Source: https://antinote.io/user-manual#usage-activity

- Evidence: v1.1.7 states that usage activity is no longer tracked.
- ForNow scope: 1.0 has no analytics.
- Requirement: `FR-PRIV-001`.

## AI Conclusion

Generative AI is not necessary to reproduce the documented application:

- Math is deterministic parsing and evaluation.
- Unit conversion is deterministic data and Foundation measurement logic.
- Currency conversion is a rate-data service, not a language model.
- OCR is local Apple Vision recognition.
- Search is literal text search.
- Markdown, links, timers, clipboard capture, export, and backup are ordinary
  application logic.

AI may help build the software, but the coding process must follow the evidence
IDs and requirement/test mappings in this repository. An in-product AI command
system is optional post-1.0 functionality and is not part of parity scope.
