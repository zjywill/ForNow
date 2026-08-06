# ADR-002 - Window Levels And Spaces

- Status: `PROPOSED`
- Date: 2026-08-03
- Step: 0.4
- Requirements: `FR-WIN-001` through `FR-WIN-005`

## Context

ForNow has three presentation modes and four application-presence modes. A
single generic panel policy cannot simultaneously provide ordinary document
window behavior, current-Space invocation, a floating palette, and an overlay
above another application's full-screen Space. Pinning is also distinct from
full-screen eligibility.

## Proposed Policy

| Mode | AppKit type | Level | Collection behavior |
|---|---|---|---|
| `standard` | `NSWindow` | `.normal`, or `.floating` when pinned | `.managed`, `.moveToActiveSpace` |
| `menuBarPanel` | Key-capable nonactivating `NSPanel` | `.floating` | `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.transient`, `.ignoresCycle` |
| `dropdownPanel` | Key-capable nonactivating `NSPanel` | `.statusBar` | `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.transient`, `.ignoresCycle` |

`moveToActiveSpace` and `canJoinAllSpaces` are intentionally never combined.
Pin changes the standard window level only. It does not add
`fullScreenAuxiliary`, so the full-screen capability remains mode-specific.

Menu-style panels include the `.nonactivatingPanel` style and use an `NSPanel`
subclass whose `canBecomeKey` is true and `canBecomeMain` is false. Collection
behavior alone was insufficient: an ordinary activating panel received the
global invocation over full-screen Safari but remained outside the active
full-screen Space. The nonactivating style lets the panel join that Space while
still making its editor the key responder.

Dock and status-item presence are independent from the presentation type:

| Presence | Activation policy | Status item |
|---|---|---|
| Dock | `.regular` | absent |
| Menu Bar | `.accessory` | present |
| Both | `.regular` | present |
| Neither | `.accessory` | absent |

Neither mode retains Toggle, Close, Pin, Settings, Save, Permission, and global
shortcut controls inside the visible window.

## Placement

Invocation selects the screen containing the pointer, clamps requested size to
that screen's `visibleFrame`, and clamps the final origin on both axes.
Standard and floating panels center in the visible frame. Dropdown panels
anchor below the status item when one exists and otherwise use the current
screen's horizontal center. Negative display origins are supported.

The application does not link or call private Spaces APIs. AppKit collection
behavior remains the shipping source of truth for active-Space and full-screen
placement. The manual spike used read-only CoreGraphics/SkyLight diagnostics to
correlate test window IDs with Space IDs; that diagnostic code is not part of
any application or package target.

## Shortcut Registration

KeyboardShortcuts remains the event adapter. A Carbon registration preflight
runs before changing its stored shortcut because KeyboardShortcuts 1.10 does
not expose `RegisterEventHotKey` failures. A failed preflight preserves the
previous binding. macOS 15.0 and 15.1 failures for Option without Command or
Control receive the documented upgrade/modifier diagnostic.

## Auto-Hide

Visibility is a deterministic state machine. Every hide or close effect emits
`flushPendingSource` first. Settings, save, and permission surfaces acquire an
identified suspension before opening and release it on completion or close.
Auto-hide runs only after the last suspension is released, the app is inactive,
the window is visible, and pin is off.

## Acceptance Contract

Accept this policy only after the Step 0.4 automated tests and manual matrix
pass. In particular:

- repeated invocation leaves one visible spike window;
- show activates the app and focuses its source editor;
- mode changes preserve the latest `NSTextView.string`;
- every computed frame is contained by a visible screen;
- menu-style panels work above a full-screen application;
- an owned panel prevents auto-hide until its suspension is released.

`MT-WIN-004C` remains pending because no second simultaneous physical display
is currently application-visible. The 2026-08-04 owner-approved continuation
of Phase 1 does not accept this ADR; acceptance still requires that cell to
pass.
