# ForNow Timer V1 Contract

- Contract ID: `fornow-timer-v1`
- Decision: `FORNOW-DECISION-013`
- Evidence: `AN-TIME-001`, `AN-TIME-002`
- Requirements: `FR-TIME-001`, `FR-TIME-002`, `FR-TIME-003`

This contract freezes behavior that the public evidence leaves unspecified. It
does not claim undocumented AntiNote parity.

## Command Grammar

Timer commands are case-insensitive and use the configured Timer aliases. A
command must start at UTF-16 offset zero of a source line. Spaces and tabs may
follow the alias; leading whitespace before it is not accepted. Disabled
keyword interpretation disables timer commands.

Supported forms are:

```text
timer
timer <minutes>
timer <minutes>: <title>
timer <m:ss>
timer <m:ss>: <title>
timer <work-minutes> <rest-minutes>
timer <work-minutes> <rest-minutes>: <title>
timer pomo
timer p
timer r
timer s
timer 0
```

- A decimal duration uses `.` and represents minutes. It must be greater than
  zero and no greater than 10,080 minutes (seven days).
- An `m:ss` duration has integer minutes and exactly two second digits in
  `00...59`, with the same seven-day bound.
- `pomo` is one 25-minute work phase followed by one 5-minute rest phase.
- Two durations create one custom work phase followed by one rest phase.
- A title is trimmed, must not be empty, and is accepted only on start forms.
- Additional tokens, signs, exponent syntax, locale commas, malformed times,
  and out-of-range durations produce a deterministic diagnostic and no command.
- Parsing is bounded to 10,000 lines and checks cancellation every 32 lines.

Pressing Return to commit a valid command line executes it once. Merely loading
or reparsing persisted source never replays a command. The command text remains
canonical note source and participates in SQLite and FTS exactly as typed.

When the first source line is exactly a Timer alias, the editor shows the V1
command tutorial as a projection. Committing that line also starts a stopwatch.

## Current Timer

ForNow V1 has one current timer application-wide. Starting a stopwatch,
countdown, or work/rest timer replaces the prior current timer. Control commands
operate on the current timer without changing its linked note ID. A start
command links the new timer to the note containing that command.

The persisted timer stores its UUID, linked note UUID, kind, optional title,
phase, state, wall-clock start timestamp, accumulated phase duration, work
duration, and optional rest duration. Deleting the linked note deletes the
timer through the existing foreign key.

## State Machine

Absence of a persisted timer is the idle state. A created timer starts running.

```text
running <-> paused
running  -> completed
running  -> cancelled
paused   -> cancelled
completed/cancelled/paused/running -> restart -> running
```

- `p` toggles running and paused. With no current timer, or after completion or
  cancellation, it is a no-op.
- `r` restarts the current timer from its initial phase. With no current timer,
  it is a no-op.
- `s` and `0` cancel a running or paused timer. Repeating stop is a no-op.
- A single click uses the same pause/resume transition. A double-click and
  Escape use the same stop transition.
- Stopwatch elapsed time has no automatic completion.
- Countdown completion clamps at zero and emits one countdown-completed event.
- A work/rest timer carries overshoot into its rest phase. Entering rest emits
  one pomodoro-break event. Finishing rest completes silently because the
  documented settings define a break-start alert, not a second pomodoro-end
  alert.

## Clock And Relaunch Semantics

While ForNow is alive, elapsed time derives from `ContinuousClock`; wall-clock
changes and time-zone changes do not make the visible timer jump. Persisted
`started_at` timestamps are reconciliation anchors, never decremented counters.

At launch, wake, system-clock change, clean quit, pause, and every phase
transition, ForNow reconciles the monotonic elapsed duration into accumulated
duration plus a fresh wall-clock anchor. Negative wall-clock deltas at launch
are clamped to zero. Positive elapsed time may cross countdown or work/rest
boundaries and is carried forward deterministically.

`Pause timer when quitting` pauses and persists a running timer before the
repository closes. When disabled, a clean quit checkpoints the timer as running
and relaunch advances it from the persisted timestamp. Abrupt termination uses
the most recently committed timestamp anchor.

## Presentation And Alerts

- The linked note shows a source-free timer decoration beside its most recent
  valid timer command. Single click, double-click, Escape, focus, and VoiceOver
  actions route through the state machine.
- When enabled, a running or paused timer appears in the existing status item.
  The item continues to open or hide ForNow.
- Countdown and pomodoro-break notification, full-screen takeover, and sound
  switches are independent. Volume is an integer from 0 through 100.
- Notification requests are scheduled from timestamp-derived remaining time.
  Denied or failed authorization never rolls back, delays, or otherwise changes
  timer state.
- In-process sound and takeover are emitted once per state-machine event.

## V1 Defaults

The public evidence does not define defaults. ForNow V1 chooses:

- pause on quit: off;
- menu-bar time: on;
- countdown and pomodoro-break notifications: off;
- countdown and pomodoro-break takeover: off;
- countdown and pomodoro-break sound: on;
- sound volume: 70 percent.

These defaults are product choices and remain versioned in `TimerSettings`.
