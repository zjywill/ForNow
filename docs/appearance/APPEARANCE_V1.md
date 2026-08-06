# ForNow Appearance And Settings V1

- Contract: `fornow-appearance-v1`
- Status: `FROZEN`
- Date: 2026-08-06
- Decision: `FORNOW-DECISION-016`
- Requirements: `FR-UI-001`, `FR-UI-002`, `FR-UI-003`, `FR-EDIT-007`,
  `FR-NOTE-009`

## Source Boundary

Appearance and settings are presentation state. Theme colors, paper marks,
material state, font size, line spacing, layout direction, shortcut labels, and
validation diagnostics never enter `Note.body`, SQLite note or FTS bodies,
clean copy, parser input, or Undo history. Changing any appearance value keeps
the current source version, selection, and canonical source unchanged.

## Versioned State

- `AppearanceSettings` version 1 stores independent light and dark theme IDs,
  paper style and visibility, lined and non-lined list spacing, XS through XL,
  double size, translucency, and background opacity.
- `EditorSettings` version 4 stores natural, left-to-right, or right-to-left
  layout direction. Versions 1 through 3 migrate to natural direction.
- `QuickActionSettings` version 1 stores every quick-action binding. A decoded
  partial binding map fills missing actions from version-1 defaults.
- `LifecycleSettings` version 1 continues to own new-note-on-launch, the reopen
  threshold, note-count visibility, delete-warning suppression, and the
  independently stored last-window-close timestamp required by `FR-NOTE-009`.

Malformed or unsupported appearance and shortcut payloads fall back to
defaults. A failed save restores the previously published runtime value.

## Semantic Themes

| ID | Display name | Intended appearance |
|---|---|---|
| `porcelainLight` | Porcelain | Light |
| `sageLight` | Sage | Light |
| `inkDark` | Ink | Dark |
| `charcoalDark` | Charcoal | Dark |

Each theme defines canvas, primary and secondary text, control fill and text,
accent, paper mark, and selection tokens. Views consume those roles rather
than hard-coded theme-specific colors. Primary text on canvas, secondary text
on canvas, and control text on control fill each require a WCAG contrast ratio
of at least 4.5. Light and dark system appearances select and persist their
theme IDs independently.

## Paper And Typography

Paper is independent from theme:

- blank draws no paper mark;
- lined follows the live text line height and scroll offset;
- dotted uses a 24-point repeat;
- small grid uses an 18-point repeat;
- large grid uses a 32-point repeat.

Subtle, clear, and bold paper visibility use alpha values 0.12, 0.22, and 0.36.
Increase Contrast strengthens the paper mark and adds a defined editor border.
List mode selects its line spacing from the lined setting only for lined paper;
blank, dotted, and both grids use the separate non-lined setting. Compact,
regular, and spacious spacing are 2, 6, and 10 points.

Editor text uses the system font at XS 14, S 16, M 18, L 21, or XL 24 points.
Double size multiplies the selected size by exactly two. Heading presentation
scales relative to the current base size. Command-minus and Command-plus step
within XS through XL, clamp at the ends, and persist without adding Undo.

## Direction

Natural direction follows each paragraph. Forced LTR aligns left and forced
RTL aligns right. Direction is applied as a default and temporary paragraph
style only. In list mode, a visually RTL item places its checkbox in the right
gutter; an LTR item uses the left gutter. Pointer and keyboard checkbox edits
continue to use the original UTF-16 source range.

## Translucency And Accessibility

Opaque semantic themes are the baseline. Translucency is unavailable before
macOS 15. When enabled on macOS 15 or newer, the editor uses native material
behind the semantic canvas and clamps background opacity to 0 through 90
percent. A theme whose intended appearance differs from the active system
appearance requires confirmation before translucency is enabled.

Reduce Transparency disables material and restores a solid canvas while
preserving the setting. Increase Contrast strengthens paper marks and draws an
explicit border. System appearance and Accessibility Display Options changes
re-resolve the presentation live. Appearance changes introduce no decorative
motion and use platform fonts and controls.

The Settings window is 640 points wide and scrollable. The longest appearance
and quick-action labels, XS through XL segmented control, modifier menus, key
fields, opacity slider, validation text, and buttons remain inside that width.
Every key field and modifier menu has an action-specific accessibility label.

## Quick Actions

| Action | Default |
|---|---|
| Previous Note | Command-[ |
| Next Note | Command-] |
| Newest Note | Command-1 |
| New Note | Command-N |
| Promote Note | Command-Shift-1 |
| Delete Note | Command-D |
| Search Notes | Command-F |
| Toggle Pin | Command-P |
| Increase Text Size | Command-+ |
| Decrease Text Size | Command-- |

A binding contains exactly one visible key and at least one of Command,
Control, or Option. Bindings must be unique, must not replace reserved macOS or
editor commands, and must not match the current global invocation shortcut.
The draft displays validation inline and disables Save while invalid. A failed
save keeps the active map. Startup revalidates the independently persisted
quick-action and global-invocation settings; a cross-setting conflict repairs
quick actions to deterministic safe defaults without changing the registered
global invocation.

## Acceptance Mapping

- `UT-UI-001`, `UIT-UI-001`, and `MT-UI-001`: independent themes, semantic
  tokens, contrast, live application, and source invariance.
- `UIT-UI-002A` through `UIT-UI-002J` and `MT-UI-002`: five distinct paper
  renders, visibility, spacing, material availability, 0 through 90, mismatch
  confirmation, accessibility fallback, and persistence.
- `UT-UI-003`, `UIT-UI-003`, and `MT-UI-003`: size stepping, double size,
  remapping, conflict recovery, longest labels, and active-binding retention.
- `UT-EDIT-007` and `ET-EDIT-007`: migration, natural/LTR/RTL presentation,
  RTL checkbox gutter, exact source, and empty Undo history.
- `UT-NOTE-009A` through `UT-NOTE-009F` and `IT-NOTE-009`: launch/reopen
  thresholds, independent close timestamp, and note-count visibility.
