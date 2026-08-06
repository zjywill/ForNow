# ADR-004 - Timer Clock And Command Semantics

- Status: `ACCEPTED`
- Date: 2026-08-06
- Step: 4.1
- Decision: `FORNOW-DECISION-013`
- Requirements: `FR-TIME-001`, `FR-TIME-002`, `FR-TIME-003`

## Context

The public timer evidence defines commands, controls, visible surfaces, and
settings, but leaves exact shutdown, relaunch, wall-clock-change, command-commit,
and work/rest completion semantics open. A persisted decrementing counter would
drift during process suspension, while wall-clock-only display would jump when
the system clock changes.

## Decision

ForNow uses one actor-owned current timer. Live elapsed time derives from a
monotonic `ContinuousClock` anchor. SQLite stores a wall-clock anchor and
accumulated phase duration so launch and process termination can reconcile
without persisting per-second counters. Wake and system-clock-change events
checkpoint a fresh wall anchor without changing the monotonic elapsed value.

Commands are pure line-scoped parser results. Return commits a command once;
source loading and projection parsing never execute it. Starting a timer
replaces the current timer, while controls retain its linked note. A custom or
standard pomodoro contains one work phase and one rest phase. Overshoot carries
across the phase boundary.

The complete versioned grammar, state transitions, defaults, alerts, projection,
and recovery behavior are defined in `docs/timers/TIMER_V1.md`.

## Consequences

- Timer state survives clean and abrupt termination without source mutation.
- A live wall-clock or time-zone change cannot move displayed elapsed time.
- Loading an old note cannot replay a persisted command.
- Only explicit state-machine events drive notifications, sound, takeover, and
  menu-bar updates.
- Exact AntiNote behavior beyond the cited public evidence remains unclaimed.

## Acceptance Contract

This decision remains accepted only while Step 4.1 proves:

- every documented command and invalid form has deterministic parser coverage;
- every state and repeated transition is covered;
- launch, pause-on-quit, relaunch, sleep/wake, and forward/backward clock-change
  scenarios preserve timestamp-derived semantics;
- timer rows cascade with their linked note and preserve canonical source/FTS;
- denied notification permission cannot alter timer completion;
- editor, menu-bar, sound, and takeover surfaces consume the same snapshot.
