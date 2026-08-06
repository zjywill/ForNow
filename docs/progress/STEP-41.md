# Step 4.1 - Timers

- Status: `DONE`
- Started: 2026-08-06
- Completed: 2026-08-06
- Evidence: `AN-TIME-001`, `AN-TIME-002`
- Requirements: `FR-TIME-001`, `FR-TIME-002`, `FR-TIME-003`
- Decision: `FORNOW-DECISION-013`
- Required tests: `UT-TIME-001A` through `UT-TIME-001L`, `IT-TIME-001`,
  `UT-TIME-002A` through `UT-TIME-002N`, `ET-TIME-002`, `IT-TIME-003A`
  through `IT-TIME-003J`, `UIT-TIME-003`, and `MT-TIME-003`

## Files Changed

- `docs/timers/TIMER_V1.md`
- `docs/decisions/ADR-004_TIMER_CLOCK_AND_COMMANDS.md`
- `App/TimerModel.swift`
- `App/TimerSettingsStore.swift`
- `App/AppDelegate.swift`
- `App/AppEnvironment.swift`
- `App/ContentView.swift`
- `App/SettingsView.swift`
- `Packages/ForNowCore/Sources/ForNowCore/Timer.swift`
- `Packages/ForNowCore/Sources/ForNowCore/TimerClock.swift`
- `Packages/ForNowCore/Sources/ForNowCore/TimerStateMachine.swift`
- `Packages/ForNowModes/Sources/ForNowModes/TimerCommands.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/EditorProjection.swift`
- `Packages/ForNowEditor/Sources/ForNowEditor/ProjectionEditorView.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/NotificationService.swift`
- `Packages/ForNowIntegrations/Sources/ForNowIntegrations/TimerSoundPlayer.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/TimerRow.swift`
- `Packages/ForNowPersistence/Sources/ForNowPersistence/PersistenceStore.swift`
- `Packages/ForNowWindowing/Sources/ForNowWindowing/TimerPresentation.swift`
- `Packages/ForNowWindowing/Sources/ForNowWindowing/WindowCoordinator.swift`
- `Tests/EditorProjectionSpikeTests/TimerCommandTests.swift`
- `Tests/EditorProjectionSpikeTests/TimerClockScenarioTests.swift`
- `Tests/EditorProjectionSpikeTests/AggregateTests.swift`
- `Tests/EditorProjectionSpikeTests/BasicMathTests.swift`
- `Tests/EditorProjectionSpikeTests/ConversionTests.swift`
- `Tests/EditorProjectionSpikeTests/ListModeTests.swift`
- `Tests/EditorProjectionSpikeTests/VariableTests.swift`
- `Tests/ForNowTests/TimerModelTests.swift`
- `Packages/ForNowPersistence/Tests/ForNowPersistenceTests/PersistenceSpikeTests.swift`
- `Tests/WindowSpikeTests/WindowSpikeTests.swift`
- `ForNow.xcodeproj/project.pbxproj`
- `docs/00_SOURCE_LEDGER.md`
- `docs/01_PRODUCT_SPEC.md`
- `docs/02_ARCHITECTURE.md`
- `docs/04_TEST_MATRIX.md`
- `docs/traceability.yml`
- `README.md`

## Behavior Contract

- Contract `fornow-timer-v1` defines case-insensitive line-scoped commands for
  stopwatch, decimal-minute and `m:ss` countdown, titled countdown, custom
  work/rest, standard 25/5 pomodoro, pause/resume, restart, and stop. Only an
  explicit Return executes a command; loading or reparsing source never does.
- One actor-owned timer is current application-wide. A start command replaces
  it and links it to the submitting note. Controls retain that note link, and
  deleting the note cascades to its timer row.
- The state machine is the only transition owner. Running and paused timers can
  be controlled by source commands, pointer actions, Escape, or VoiceOver
  actions. Completed and cancelled controls are disabled, retain no actions,
  and require the explicit restart command.
- Live display uses a monotonic clock. SQLite stores accumulated phase duration
  and a wall-clock anchor only at lifecycle boundaries. Launch, wake, clock
  change, clean quit, and forced-termination recovery clamp negative wall-clock
  deltas and deterministically carry positive elapsed time across phase bounds.
- Countdown completion emits one completion event. Entering a pomodoro rest
  phase emits one break event; finishing the rest phase completes silently.
- Menu-bar time, countdown and pomodoro-break notifications, takeover and sound
  are independently configurable. Notification denial or scheduling failure
  cannot change timer state. Sound volume is clamped to `0...100`.
- The timer row and command text are canonical persistence. Visible countdowns,
  tutorial content, diagnostics, buttons, status text, and accessibility labels
  remain projections and never enter `Note.body`, SQLite FTS, or clean copy.

## Automated Evidence

- `TimerCommandTests` passes all 28 command, parser, state-machine, source-only,
  AppKit interaction, VoiceOver action, terminal-state, and Escape tests. Every
  required `UT-TIME-001*`, `UT-TIME-002*`, and `ET-TIME-002` mapping is present.
- `TimerClockScenarioTests` passes all 5 scenario tests, covering normal
  monotonic progression, sleep/wake re-anchoring, forward and backward wall
  changes, time-zone independence, negative recovery, forced termination, day
  boundary, and work/rest phase-boundary recovery.
- `TimerModelTests` passes all 10 `IT-TIME-003A...J` tests for defaults and
  settings persistence, menu-bar visibility, timestamp notification requests,
  denial isolation, independent countdown and break sound/takeover behavior,
  volume, pause-on-quit, and running relaunch.
- Persistence integration covers complete timer-field round trip, relaunch,
  failed replacement rollback, exact source/FTS isolation, integrity, and note
  foreign-key cascade. Native AppKit window coverage verifies accessible
  takeover presentation and click/Escape dismissal.
- The complete parallel Editor Projection suite passes all 238 tests with zero
  failures or skips. Programmatically owned test windows opt out of AppKit's
  release-on-close behavior, including 10 consecutive conversion and variable
  regression runs, so teardown cannot double-release an `NSWindow`.
- The complete main application, persistence, window, and Release performance
  suites pass. Debug and Release unsigned builds, strict formatting,
  generated-project comparison, traceability generation and fault injection,
  and `git diff --check` also pass.

## Real Application Evidence

- A current Debug app launched under an isolated `CFFIXED_USER_HOME`. Submitting
  `timer 2: Relaunch Check` created one running 120-second titled countdown
  linked to the note. SQLite and FTS contained byte-identical source, and
  `PRAGMA quick_check` returned `ok`.
- The editor exposed an accessible `Timer control` with a live countdown and
  pause/resume and stop actions. The status item exposed the same live time.
  Pointer activation paused and resumed the same timer without changing source.
- With pause-on-quit disabled, normal Quit persisted a running timer. Relaunch
  reconciled it to `completed`; Previous Note restored exact source and
  `Completed 0:00`. The completed control was disabled, exposed zero custom
  actions, and instructed the user to restart with a command.
- Submitting `timer r` restarted the same timer identity. A second confirmed
  restart entered `running`; pressing Escape persisted `cancelled` with a null
  `started_at` and 27.174678958 accumulated seconds. The real control displayed
  `Stopped 1:33`, was disabled, and exposed zero custom actions. Timer text was
  absent from the status item.
- Final note and FTS bodies were the same 40 bytes:
  `timer 2: Relaunch Check\ntimer r\ntimer r\n`. The database integrity check
  remained `ok`. The process then quit normally, the clipboard was cleared, no
  ForNow process remained, and the isolated directory was removed.

## Exit Criteria

- State-machine transition tests are exhaustive: `PASS` in
  `UT-TIME-002A...N`, repeated-transition coverage, and pointer, Escape, and
  accessibility integration.
- Restart and relaunch preserve documented semantics: `PASS` in parser/state,
  clock recovery, persistence round trip, pause-on-quit, and isolated real-app
  quit/relaunch evidence.
- Denied notifications do not affect timer state: `PASS` in `IT-TIME-003E`.
- Every Step 4.1 task is implemented: `PASS` in the versioned contract, mapped
  automated suites, native integration coverage, and real-app evidence.

## Environment Limitation

Signed UI tests remain unavailable because this host has zero valid Apple
Development identities. Native AppKit integration tests and isolated
real-process Accessibility inspection cover the implemented Step 4.1 paths
without waiving future signed UI coverage.

## Deferred Manual Evidence

`MT-WIN-004C` physical simultaneous dual-display coverage remains `PENDING`.
Step 0.4 remains `VERIFYING`, ADR-002 remains `PROPOSED`, and the test is still
required before the 1.0 release gate.
