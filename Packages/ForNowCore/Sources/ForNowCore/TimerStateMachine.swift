import Foundation

public struct TimerTransition: Sendable, Equatable {
  public let timer: NoteTimer
  public let elapsedInPhase: Duration
  public let events: [TimerEvent]
  public let changed: Bool

  public init(
    timer: NoteTimer,
    elapsedInPhase: Duration,
    events: [TimerEvent] = [],
    changed: Bool
  ) {
    self.timer = timer
    self.elapsedInPhase = elapsedInPhase
    self.events = events
    self.changed = changed
  }
}

public struct TimerStateMachine: Sendable {
  public init() {}

  public func start(
    command: TimerCommand,
    id: TimerID,
    noteID: NoteID,
    at date: Date
  ) -> NoteTimer? {
    switch command {
    case .startStopwatch(let title):
      return NoteTimer(
        id: id,
        noteID: noteID,
        kind: .stopwatch,
        title: title,
        phase: .primary,
        state: .running,
        startedAt: date
      )
    case .startCountdown(let duration, let title):
      return NoteTimer(
        id: id,
        noteID: noteID,
        kind: .countdown,
        title: title,
        phase: .primary,
        state: .running,
        startedAt: date,
        workDuration: duration
      )
    case .startPomodoro(let work, let rest, let title):
      return NoteTimer(
        id: id,
        noteID: noteID,
        kind: .pomodoro,
        title: title,
        phase: .work,
        state: .running,
        startedAt: date,
        workDuration: work,
        restDuration: rest
      )
    case .pauseOrResume, .restart, .stop:
      return nil
    }
  }

  public func applyControl(
    _ command: TimerCommand,
    to timer: NoteTimer,
    elapsedInPhase: Duration,
    at date: Date
  ) -> TimerTransition {
    let elapsed = TimerDuration.clampedNonnegative(elapsedInPhase)
    var updated = timer
    switch command {
    case .pauseOrResume:
      switch timer.state {
      case .running:
        updated.state = .paused
        updated.accumulated = elapsed
        updated.startedAt = nil
      case .paused:
        updated.state = .running
        updated.accumulated = elapsed
        updated.startedAt = date
      case .idle, .completed, .cancelled:
        break
      }
    case .restart:
      updated.phase = timer.kind == .pomodoro ? .work : .primary
      updated.state = .running
      updated.accumulated = .zero
      updated.startedAt = date
    case .stop:
      switch timer.state {
      case .idle, .running, .paused:
        updated.state = .cancelled
        updated.accumulated = elapsed
        updated.startedAt = nil
      case .completed, .cancelled:
        break
      }
    case .startStopwatch, .startCountdown, .startPomodoro:
      break
    }
    return TimerTransition(
      timer: updated,
      elapsedInPhase: updated.state == .running ? updated.accumulated : elapsed,
      changed: updated != timer
    )
  }

  public func advance(
    _ timer: NoteTimer,
    elapsedInPhase: Duration,
    at date: Date
  ) -> TimerTransition {
    let elapsed = TimerDuration.clampedNonnegative(elapsedInPhase)
    guard timer.state == .running else {
      return TimerTransition(timer: timer, elapsedInPhase: timer.accumulated, changed: false)
    }
    switch timer.kind {
    case .stopwatch:
      return TimerTransition(timer: timer, elapsedInPhase: elapsed, changed: false)
    case .countdown:
      guard let duration = timer.workDuration, elapsed >= duration else {
        return TimerTransition(timer: timer, elapsedInPhase: elapsed, changed: false)
      }
      var completed = timer
      completed.state = .completed
      completed.startedAt = nil
      completed.accumulated = duration
      return TimerTransition(
        timer: completed,
        elapsedInPhase: duration,
        events: [TimerEvent(kind: .countdownCompleted, timerID: timer.id, title: timer.title)],
        changed: true
      )
    case .pomodoro:
      return advancePomodoro(timer, elapsedInPhase: elapsed, at: date)
    }
  }

  private func advancePomodoro(
    _ timer: NoteTimer,
    elapsedInPhase: Duration,
    at date: Date
  ) -> TimerTransition {
    guard let work = timer.workDuration, let rest = timer.restDuration else {
      var cancelled = timer
      cancelled.state = .cancelled
      cancelled.startedAt = nil
      return TimerTransition(
        timer: cancelled,
        elapsedInPhase: elapsedInPhase,
        changed: true
      )
    }
    switch timer.phase {
    case .work:
      guard elapsedInPhase >= work else {
        return TimerTransition(timer: timer, elapsedInPhase: elapsedInPhase, changed: false)
      }
      let overshoot = elapsedInPhase - work
      var updated = timer
      updated.phase = .rest
      let event = TimerEvent(kind: .pomodoroBreakBegan, timerID: timer.id, title: timer.title)
      if overshoot >= rest {
        updated.state = .completed
        updated.startedAt = nil
        updated.accumulated = rest
        return TimerTransition(
          timer: updated,
          elapsedInPhase: rest,
          events: [event],
          changed: true
        )
      }
      updated.accumulated = overshoot
      updated.startedAt = date
      return TimerTransition(
        timer: updated,
        elapsedInPhase: overshoot,
        events: [event],
        changed: true
      )
    case .rest:
      guard elapsedInPhase >= rest else {
        return TimerTransition(timer: timer, elapsedInPhase: elapsedInPhase, changed: false)
      }
      var completed = timer
      completed.state = .completed
      completed.startedAt = nil
      completed.accumulated = rest
      return TimerTransition(
        timer: completed,
        elapsedInPhase: rest,
        changed: true
      )
    case .primary:
      var repaired = timer
      repaired.phase = .work
      repaired.accumulated = elapsedInPhase
      repaired.startedAt = date
      return TimerTransition(
        timer: repaired,
        elapsedInPhase: elapsedInPhase,
        changed: true
      )
    }
  }
}
