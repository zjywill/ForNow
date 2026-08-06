# Step 0.4 - Window And Spaces Spike

- Status: `VERIFYING`
- Started: 2026-08-03
- Completed: pending
- Evidence reviewed: `AN-WIN-001` through `AN-WIN-005`
- Requirements: `FR-WIN-001` through `FR-WIN-005`
- Tests: `UT-WIN-001`, `IT-WIN-001`, `MT-WIN-001`, `UT-WIN-002`,
  `UIT-WIN-002`, `MT-WIN-002`, `UT-WIN-003`, `UIT-WIN-003`,
  `MT-WIN-003`, `MT-WIN-004A` through `MT-WIN-004H`, `UIT-WIN-005A`,
  `UIT-WIN-005B`, `IT-WIN-005`

## Files Changed

- `Packages/ForNowWindowing/`
- `Spikes/WindowSpike/`
- `Tests/WindowSpikeTests/`
- `docs/decisions/ADR-002_WINDOW_LEVELS_AND_SPACES.md`
- `docs/progress/WINDOW_SPIKE_MANUAL_MATRIX.md`
- `docs/progress/assets/window-spike-dropdown-min.png`
- `docs/progress/assets/window-spike-fullscreen-dropdown.png`
- `docs/progress/assets/window-spike-standard.png`
- `docs/progress/assets/window-spike-transitions.log`
- `project.yml`
- `scripts/test-window-spike.sh`

## Commands Run

```bash
swift build --package-path Packages/ForNowWindowing
scripts/format.sh --fix
scripts/test-window-spike.sh
xcrun xcresulttool get test-results summary --path <WindowSpike.xcresult>
xcodebuild -quiet -project ForNow.xcodeproj \
  -scheme WindowSpike \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build
open -n DerivedData/Build/Products/Debug/WindowSpike.app
system_profiler SPDisplaysDataType
screencapture -x /tmp/fornow-fullscreen-dropdown-nonactivating.png
cp /tmp/fornow-fullscreen-dropdown-nonactivating.png \
  docs/progress/assets/window-spike-fullscreen-dropdown.png
```

## Automated Test Results

- `WindowSpikeTests`: 10 passed, 0 failed, 0 skipped on macOS 26.6.
- Option-A default and macOS 15.0/15.1 diagnostic policy passed.
- A rejected shortcut retained the previous binding; an accepted candidate
  replaced it.
- Dock/Menu/Both/Neither policy and dropdown dimension clamps passed.
- Pin level and full-screen collection behavior remained independent.
- Owned-panel suspension prevented auto-hide until release.
- Local, global, status-item, and close paths emitted flush before hide/close.
- 1,000 repeated show events produced focus-only effects after the first show.
- Synthetic dual-display frames, including a negative origin, remained visible.

## Manual Test Results

- Option-A registered on macOS 26.6.
- With Finder foreground, the first Option-A flushed 61 UTF-16 source units and
  hid the window. The second showed it, made the app frontmost, and focused the
  editor without an extra click.
- Text entered immediately before switching standard -> floating -> dropdown
  remained exact in all three presentations. This reverified the direct
  `NSTextView.string` synchronization fix for the lost-final-character race.
- CoreGraphics reported one on-screen app window after 20 consecutive global
  toggles. Command-O and Command-W flushed 85 and 109 UTF-16 source units,
  respectively, before hiding or closing; Option-A then restored the exact
  source and editor focus.
- The runtime SwiftUI application menu exposed Toggle Window (Command-O) and
  Pin Window (Command-P). Command-P changed the standard window from
  CoreGraphics layer 0 to layer 3 and back without changing its Space policy.
- The dropdown's configured 560 by 560 frame and adjusted dimensions changed
  the actual AppKit frame. Its minimum 360 by 280 frame retained every control
  without clipping; see `assets/window-spike-dropdown-min.png`.
- Dock, Menu Bar, Both, and Neither changed the real Dock item and status item
  as specified. Neither retained all in-window commands and accepted typing
  immediately after an Option-A invocation.
- The real status item hid and restored the same window and editor focus.
- With auto-hide enabled, settings, save, and permission panels each retained
  the main window after Finder became active. Releasing the last suspension
  then flushed and hid the window.
- Standard placement was fully visible on the active display.
- Accessibility reported the source text area as focused after global show.
- A second real Desktop was created and selected through Mission Control.
  Standard moved to the active ordinary Space after hide/show; floating and
  dropdown were assigned to both Space IDs 1 and 59 and remained on-screen at
  CoreGraphics layers 3 and 25. All modes preserved the same English/CJK
  source and returned editor focus.
- Safari remained `AXFullScreen=true` in Space 70 while key-capable
  nonactivating floating and dropdown panels joined that Space, overlaid it,
  and focused the editor. Standard correctly remained outside the full-screen
  Space. See `assets/window-spike-fullscreen-dropdown.png`.
- Stage Manager was verified first with `GloballyEnabled=0` and then through
  the real first-run confirmation with `GloballyEnabled=1`. All three modes
  passed invocation and focus checks in both states; 20 additional Stage
  Manager-on toggles left one visible window. Stage Manager was restored off.
- See `WINDOW_SPIKE_MANUAL_MATRIX.md` for the pending physical dual-display
  cell.

## Deviations And Open Questions

- The first mode-change exercise exposed a real race: rebuilding the hosting
  view before SwiftUI published the final keystroke lost that character. The
  coordinator now synchronizes directly from `NSTextView.string` before every
  flush and presentation rebuild. Real standard/floating/dropdown
  reverification now passes.
- Real dropdown testing exposed two layout constraints that the placement unit
  test could not see: a universal 620-point content minimum overrode configured
  width, and a 280-point content minimum added the title-bar height to the
  requested frame. The dropdown now uses a responsive 360-point content width
  and lets `NSWindow.minSize` own the 280-point frame-height limit.
- The coordinator's hand-built `NSMenu` was overwritten by SwiftUI after app
  launch, so Command-O and Command-P were absent at runtime. They now use a
  SwiftUI `CommandGroup` and have real menu and shortcut evidence.
- The first valid Safari full-screen run exposed a policy defect rather than a
  shortcut defect: the log showed `showWindow` but `active-space=false` for an
  ordinary activating `NSPanel`. Adding `.nonactivatingPanel` and explicitly
  allowing the panel to become key produced `active-space=true`; CoreGraphics
  then assigned the panel to Safari's Space 70. Both menu-style modes were
  reverified after the fix.
- Only physical simultaneous dual-display testing remains pending. The current
  machine exposes one Screen Sharing Virtual Display; synthetic placement does
  not count as a manual replacement.
- On 2026-08-04 the product owner directed Phase 1 implementation to continue
  with `MT-WIN-004C` explicitly marked pending. This is a scheduling exception,
  not evidence that the cell passed: Step 0.4 remains `VERIFYING`, ADR-002
  remains `PROPOSED`, and the cell is still required before the 1.0 release
  gate.
- Swift 6.3.3 IRGen crashed when actor-isolated instance methods were passed
  directly as SwiftUI `Binding` setters. Explicit closures avoid the compiler
  bug without changing behavior.
