# ForNow AutoPaste V1 Contract

- Contract ID: `fornow-autopaste-v1`
- Decision: `FORNOW-DECISION-015`
- Evidence: `AN-AUTO-001`, `AN-AUTO-002`
- Requirements: `FR-AUTO-001`, `FR-AUTO-002`, `FR-AUTO-003`

This contract freezes behavior that the public evidence leaves unspecified. It
does not claim undocumented AntiNote parity.

## Command Grammar

AutoPaste commands are case-insensitive and must occupy one source line. The
accepted forms are:

```text
paste
paste(<separator>)
```

- Trailing spaces and tabs are ignored. Leading spaces or tabs are not accepted.
- The separator is literal, may be empty, and is limited to 256 UTF-16 code
  units. Newlines are not accepted inside a command.
- Lookalikes, extra tokens, and unmatched parentheses remain ordinary source.
- Pressing Return commits a valid command once. Loading or reparsing persisted
  source never starts a session.
- The command line remains canonical note source in SQLite, FTS, clean copy,
  and export.

Submitting a command while AutoPaste is active stops the current session. It
does not change the destination or immediately start another session.

## Scoped Session

ForNow V1 has at most one AutoPaste session application-wide. Starting a
session fixes these values until it stops:

- the destination note ID;
- the display name;
- prefix, suffix, separator, link treatment, and timestamp policy.

The destination name is the first non-empty source line that is not an
AutoPaste command, truncated to 60 characters. If no such line exists, the
indicator uses `Untitled note`. Navigation does not retarget an active session.

Starting monitoring records the current pasteboard `changeCount` as a baseline.
Text already on the pasteboard is not captured. The persistent bottom status
names the fixed destination, reports the accepted capture count, and provides
two accessible stop buttons. The clipboard icon pulses unless Reduce Motion is
enabled.

## Observation And Ordering

`SystemClipboardService` creates a main-run-loop timer only for an active
session. The default interval is 250 milliseconds and is clamped to no less
than 50 milliseconds. Each poll:

1. compares `NSPasteboard.general.changeCount` with the last observed value;
2. ignores a registered application-owned change count;
3. reads only the pasteboard `.string` representation;
4. forwards the text and change count to the session.

Accepted events are appended sequentially in observation order. A capture for
the visible destination waits while AppKit reports IME marked text. A capture
for a background destination reads the latest repository value before appending.
Each accepted append is flushed before the next event is processed.

The destination's creation time, expiration, slot, selection, and scroll state
are preserved. If the fixed destination is deleted or cannot be read, the
session stops and never recreates it.

## Normalization And Policy

Captured text is canonicalized before hashing and formatting:

- CRLF and CR become LF;
- NUL characters are removed;
- an empty normalized result is ignored.

Newline is the default separator. Settings also provide blank line, space, and
comma-space presets. A command separator overrides the preset for that session.
The first capture does not add a second delimiter when the committed command
already ends with the active delimiter.

Prefix and suffix are applied to each item and are each limited to 1,024 UTF-16
code units. Optional timestamps use UTC ISO 8601 at the observation time.
Markdown-style HTTP and HTTPS links can be preserved, converted to readable
`label (destination)` text, or reduced to the destination. Session settings are
a snapshot; changing Settings affects the next session.

## Deduplication And Privacy

The session remembers only the last observed change count and a bounded history
of 64 SHA-256 hashes of normalized text. A repeated change count, a text hash
still in that window, or an empty normalized value is ignored. Hash eviction is
FIFO so memory use does not grow with session duration.

ForNow-owned copy operations register their final pasteboard change count. The
monitor keeps at most 32 such counts and consumes a match without reading or
appending it. No clipboard body history is persisted or logged; accepted text
exists only as canonical destination-note content and transient pending work.

## Stop And Failure Semantics

Escape, a repeated command, either status control, destination deletion,
destination loss, app termination, or an append failure stops AutoPaste.
Stopping invalidates the polling timer immediately, clears the callback,
baseline, owned-write tokens, queued clipboard bodies, and session state. An
append failure presents a recoverable source-free alert.

At application startup and whenever the status indicator is absent, the
production monitor has no timer and performs zero polling work.

## Acceptance Contract

Step 4.3 remains complete only while verification proves:

- exact command parsing, every stop path, fixed-destination navigation, visible
  status, and destination deletion behavior;
- inactive zero-poll behavior, start-time baseline behavior, change-count and
  content deduplication, application-owned copy suppression, and bounded hashes;
- 1,000 application-layer poll events produce exactly the expected unique note
  lines with no self-copy content or loop;
- 10,000 distinct policy-layer events retain at most 64 hashes;
- default and custom delimiters, affixes, links, timestamps, and normalization
  remain independent from pasteboard observation;
- SQLite, FTS, and clean copy contain canonical source only.
