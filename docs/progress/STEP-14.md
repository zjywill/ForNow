# Step 1.4 - Global Invocation And Presence Modes

- Status: `DONE`
- Started: 2026-08-04
- Completed: 2026-08-04
- Evidence: `AN-WIN-001` through `AN-WIN-005`
- Requirements: `FR-WIN-001` through `FR-WIN-005`
- Tests: `UT-WIN-001`, `IT-WIN-001`, `MT-WIN-001`, `UT-WIN-002`,
  `UIT-WIN-002`, `MT-WIN-002`, `UT-WIN-003`, `UIT-WIN-003`,
  `MT-WIN-003`, `MT-WIN-004A` through `MT-WIN-004H`, `UIT-WIN-005A`,
  `UIT-WIN-005B`, `IT-WIN-005`, `PT-WIN-001`, `PT-TOGGLE-001`

## Files Changed

- `Packages/ForNowWindowing/Sources/ForNowWindowing/WindowCoordinator.swift`
- `Packages/ForNowWindowing/Sources/ForNowWindowing/GlobalShortcut.swift`
- `Packages/ForNowWindowing/Sources/ForNowWindowing/WindowVisibilityStateMachine.swift`
- `App/AppDelegate.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/ForNowApp.swift`
- `App/ForNowCommands.swift`
- `App/SettingsView.swift`
- `App/WindowSettingsStore.swift`
- `Tests/ForNowTests/AppEnvironmentTests.swift`
- `docs/02_ARCHITECTURE.md`

## Behavior Contract

- `SwiftUIWindowCoordinator` is the only owner of the main AppKit window.
  SwiftUI declares Settings and application commands, not a competing main
  `WindowGroup`.
- Standard uses `NSWindow`; pseudo-menu and traditional dropdown use key-capable
  nonactivating `NSPanel` policies. Presentation rebuilds retain the same
  `NoteSessionModel` and exact source.
- Option-A is the default global shortcut. Replacements are preflighted before
  KeyboardShortcuts persists them; conflict or platform failure retains the
  previous binding and reports a specific diagnostic.
- Presentation mode, Dock/menu-bar presence, pin, auto-hide, and dropdown size
  round-trip through an independently versioned `WindowConfiguration`.
- Dock, Menu Bar, Both, and Neither are independent presence modes. Neither
  exposes every required note/window command plus Settings inside the window.
- Command-O and the global shortcut toggle visibility. Command-W closes the key
  Settings window first, otherwise the main window. Command-P toggles pin.
- Hide, close, and presentation rebuild read the live `NSTextView.string`,
  commit marked text, prepare the note, and await repository flush. Failure
  keeps the main window visible.
- Show/hide and close/reopen reuse one main window and restore source, selection,
  and editor focus. Serialized transitions prevent rapid toggles from bypassing
  a pending flush.
- Settings and delete confirmation acquire owned-panel tokens. Auto-hide is
  evaluated only after all tokens are released; pin suppresses focus-loss hide.
- Placement targets the current display, clamps to its visible frame, and uses
  independently configurable dropdown width and height.
- Hotkey-to-caret logs contain numeric duration only and retain at most 200
  in-memory samples.

## Automated Evidence

- Main application tests: 34 passed, 0 failed, 0 skipped in the last integrated
  Step 1.4 run.
- `UT-WIN-002` wrote window settings and loaded them through a second
  UserDefaults-backed store and application environment.
- `UIT-WIN-002` changed standard -> pseudo-menu -> dropdown, awaited each
  source flush, and preserved exact source through all three projections.
- `IT-WIN-005` completed 1,000 hide/show cycles with 1,000 flushes, one window
  creation, one visible window, and an unchanged selection.
- `WindowSpikeTests`: 10 passed, including shortcut diagnostics, presence,
  dropdown clamping, pin/Space policy separation, owned-panel suspension,
  flush-first transitions, and synthetic placement.
- Editor projection tests: 14 passed. Persistence tests: 16 passed.
- Traceability, generated-project comparison, Debug and Release builds, and
  formatting passed in the final gate run.
- The final unified-log privacy scan found none of the Step 1.3, Step 1.4, or
  end-to-end source fixtures in the ForNow process logs.
- Signed UI tests are unavailable on this host because it has zero valid Apple
  Development identities. The same application paths were exercised through
  macOS Accessibility; this environment limitation does not waive manual tests.

## Real Application Evidence

- Exact fixture `FORNOW_STEP14_20260804_1102_中文_🪟` persisted with ID
  `F5490FA1-8E31-4E64-B885-72EBCF9ACB25` during the exercise.
- Command-O hide/show and global Option-A restore preserved the exact source and
  focused editor. Command-W closed the main window; Command-O reopened the same
  note. Standard, pseudo-menu, and traditional dropdown retained exact source.
- Real Settings changed dropdown dimensions from 560 by 560 to 580 by 540.
  Neither exposed Previous, Next, Newest, Promote, Delete, Toggle, Pin, and
  Settings. Its native Settings link opened the real Settings scene.
- Auto-hide remained suspended while Settings was open and hid after the token
  was released. Pin prevented focus-loss hide after Finder activation.
- Dock produced one menu bar and a Dock item; Menu Bar produced a status item
  and no Dock item after activation-policy propagation; Neither showed neither
  external surface; Both showed both.
- The shortcut was changed from Option-A to Option-Command-B. The replacement
  toggled the window and Option-A stopped responding. Option-A was then restored.
- Command-W closed Settings while preserving the main window, then closed the
  main window on the next invocation.
- Ten real Option-A show samples measured 12.886542 ms minimum,
  15.984875 ms p95, and 15.984875 ms maximum, below the 150 ms budget.
- The fixture row was deleted after verification. Production note and FTS
  counts returned to zero and `PRAGMA quick_check` returned `ok`. Window mode,
  presence, pin, auto-hide, dimensions, and shortcut were restored to defaults.

## Exit Criteria

- Hotkey-to-caret p95 under 150 ms: `PASS` at 15.984875 ms on the development
  machine.
- No duplicate windows after 1,000 toggle cycles: `PASS` with one creation and
  one visible window.
- Current note survives every hide/show path: `PASS` in automated and real
  application exercises.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`
under the owner-approved Phase 0 continuation exception. Synthetic placement
and a virtual display are not substitutes. Step 0.4 remains `VERIFYING`,
ADR-002 remains `PROPOSED`, and this test is still required before the 1.0
release gate.
