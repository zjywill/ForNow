# ForNow Quick Export V1

- Contract: `fornow-quick-export-v1`
- Status: `FROZEN`
- Date: 2026-08-06
- Decision: `FORNOW-DECISION-017`
- Requirements: `FR-EXP-001`, `FR-EXP-002`, `FR-EXP-003`, `FR-EXP-004`

## Source Boundary

Every destination consumes an `ExportDocument` built from a snapshot of
`Note.body`. Export never reads attributed editor storage, rendered Markdown,
checkbox controls, computed-result labels, shortened links, or other
decorations. Export may derive a clean payload, title, filename, or URL, but it
never writes those values back to the note, SQLite, FTS, selection, or Undo.

Before a command takes its snapshot, the App flushes marked-text-safe editor
state through the ordinary repository path. A failed or cancelled export leaves
the source note and repository unchanged.

## Versioned Settings

`ExportSettings` version 1 stores:

- a quick destination, defaulting to Plain Text;
- whether mode keywords are omitted, defaulting to on;
- whether the first non-empty first line is used as the title, defaulting to on;
- an optional Obsidian vault;
- an Apple Shortcut name, defaulting to `ForNow Export to Apple Notes`;
- one version-1 custom URL template.

Malformed or unsupported settings fall back to version-1 defaults. Invalid
custom templates cannot be saved as the active quick destination. A failed
settings write restores the previously published settings.

## Canonical Document

The editor package builds the canonical document in this order:

1. Start with exact canonical source text.
2. Always remove recognized checklist trigger markers from list items.
3. When keyword omission is enabled, remove the recognized mode keyword while
   retaining any human title after the keyword. Code-mode headers are removed.
4. Preserve original URLs, Markdown punctuation, Unicode, line endings, and all
   other source characters.
5. When first-line title is enabled and the first line is non-empty after
   trimming horizontal whitespace, store that trimmed line as `title` and the
   exact remainder after its line ending as `content`.

The document also retains the full cleaned text. TXT, Markdown, ZIP entries,
and Apple Shortcut input use that full text so first-line title extraction never
drops content. Obsidian, Bear, and custom URL adapters may use separate `title`
and `content` fields from the same document.

## Files And ZIP

TXT uses `.txt`; Markdown uses `.md`; both are UTF-8 without a byte-order mark.
Writers create a unique temporary file in the destination directory and commit
it with a same-volume move. The default policy fails if the destination exists.
Replacement is allowed only after the save panel has returned an explicitly
approved existing destination. Temporary files are removed after every error.

Suggested filename bases preserve Unicode, replace path separators, colons,
control characters, and NUL with `-`, trim whitespace and terminal dots, and
limit the result to 180 UTF-8 bytes without splitting an extended grapheme
cluster. An empty result becomes `Untitled`. Export-all processes notes in
repository order and resolves duplicate
entry names deterministically as `Name.txt`, `Name 2.txt`, and so on.

Export-all creates one deflated UTF-8 `.txt` entry per exported note using
ZIPFoundation 0.9.20. The archive itself uses the same temporary-file commit and
overwrite policy as single-file export.

## Application Adapters

- Obsidian uses `obsidian://new` with optional `vault`, `name`, and `content`
  query values.
- Bear uses `bear://x-callback-url/create` with `title` and `text` query values.
- Apple Notes uses `shortcuts://run-shortcut` with configured shortcut `name`,
  `input=text`, and the full cleaned text in `text`.

Query values are supplied to `URLComponents` as decoded values, then assigned as
strict RFC 3986 percent-encoded query items exactly once. Only unreserved
characters remain literal, so plus signs are encoded as `%2B`.
Before opening, every adapter asks Launch Services whether a handler exists. A
missing handler or shortcut configuration returns actionable setup guidance and
performs no external action.

## Custom URL Templates

A version-1 custom template:

- uses one of `bear`, `craft`, `dayone`, `drafts`, `obsidian`, `shortcuts`,
  `things`, `ulysses`, or `x-drafts`;
- contains only `{CONTENT}`, `{TITLE}`, and `{DATE}` placeholders;
- places placeholders only in path, query-value, or fragment components;
- contains no placeholder in scheme, user, password, host, or port;
- is no longer than 4,096 UTF-8 bytes before substitution;
- produces an absolute URL no longer than 8,192 UTF-8 bytes.

`{DATE}` is the export instant formatted as Gregorian `yyyy-MM-dd` in UTC.
Query values are decoded, substituted, and assigned through `URLComponents` as
strict percent-encoded query items so input percent and plus signs are encoded
exactly once. `{CONTENT}` path values first
replace `&` with `+` and `%` with the literal string ` percent`, including the
leading space, then percent-encode as one path segment. Fragment substitutions
use strict percent encoding without the path compatibility transform.

Unknown, unbalanced, host-level, relative, oversized, or disallowed templates
are rejected before Launch Services is consulted. Rendering and availability
must both succeed before the URL opener is called.

## Acceptance Mapping

- `UT-EXP-001A` through `UT-EXP-001F`: exact canonical source snapshot, Unicode
  and line endings, mode-keyword policy, first-line title, original links,
  checklist triggers, and source immutability.
- `IT-EXP-002A` through `IT-EXP-002H` and `ST-EXP-002`: TXT, Markdown, atomic
  commit, explicit overwrite, UTF-8 round-trip, unsafe filenames, ZIP entries,
  duplicate names, cleanup, and failure preservation.
- `UT-EXP-003` and `IT-EXP-003A` through `IT-EXP-003F`: URL construction,
  Obsidian, Bear, Apple Shortcut, missing handlers, configured Command-S routing,
  and source preservation.
- `UT-EXP-004A` through `UT-EXP-004J`, `IT-EXP-004`, and `ST-EXP-004`: all
  placeholders, UTC date, query/path/fragment encoding, path compatibility,
  allowlist, component restrictions, invalid syntax, template size, rendered
  URL size, opener gating, and source preservation.
