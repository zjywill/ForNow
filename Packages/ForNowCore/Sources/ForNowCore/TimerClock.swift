import Foundation

public protocol MonotonicClock: Sendable {
  func now() async -> Duration
}

public struct SystemMonotonicClock: MonotonicClock {
  private let clock: ContinuousClock
  private let origin: ContinuousClock.Instant

  public init() {
    let clock = ContinuousClock()
    self.clock = clock
    origin = clock.now
  }

  public func now() -> Duration {
    origin.duration(to: clock.now)
  }
}

public actor ManualMonotonicClock: MonotonicClock {
  private var instant: Duration

  public init(_ instant: Duration = .zero) {
    self.instant = instant
  }

  public func now() -> Duration {
    instant
  }

  public func advance(by duration: Duration) {
    instant += duration
  }

  public func set(_ instant: Duration) {
    self.instant = instant
  }
}

public struct TimerUpdate: Sendable, Equatable {
  public let snapshot: TimerSnapshot?
  public let events: [TimerEvent]

  public init(snapshot: TimerSnapshot?, events: [TimerEvent] = []) {
    self.snapshot = snapshot
    self.events = events
  }
}

public actor TimerClock {
  private struct RuntimeAnchor: Sendable {
    let timerID: TimerID
    let phase: TimerPhase
    let monotonicInstant: Duration
    let elapsedInPhase: Duration
  }

  private let repository: any NoteRepository
  private let wallClock: any WallClock
  private let monotonicClock: any MonotonicClock
  private let uuidGenerator: any UUIDGenerating
  private let stateMachine: TimerStateMachine
  private var currentTimer: NoteTimer?
  private var anchor: RuntimeAnchor?

  public init(
    repository: any NoteRepository,
    wallClock: any WallClock,
    monotonicClock: any MonotonicClock,
    uuidGenerator: any UUIDGenerating,
    stateMachine: TimerStateMachine = TimerStateMachine()
  ) {
    self.repository = repository
    self.wallClock = wallClock
    self.monotonicClock = monotonicClock
    self.uuidGenerator = uuidGenerator
    self.stateMachine = stateMachine
  }

  public func load() async throws -> TimerUpdate {
    guard var timer = try await repository.currentTimer() else {
      currentTimer = nil
      anchor = nil
      return TimerUpdate(snapshot: nil)
    }
    let wallNow = wallClock.now()
    let monotonicNow = await monotonicClock.now()
    var elapsed = timer.accumulated
    var events: [TimerEvent] = []
    if timer.state == .running {
      if let startedAt = timer.startedAt {
        elapsed += TimerDuration.duration(
          seconds: max(0, wallNow.timeIntervalSince(startedAt))
        )
      }
      let transition = stateMachine.advance(timer, elapsedInPhase: elapsed, at: wallNow)
      timer = transition.timer
      elapsed = transition.elapsedInPhase
      events = transition.events
      if timer.state == .running {
        timer.accumulated = elapsed
        timer.startedAt = wallNow
      }
      try await repository.saveCurrentTimer(timer)
    }
    currentTimer = timer
    resetAnchor(for: timer, elapsed: elapsed, monotonicNow: monotonicNow)
    return TimerUpdate(
      snapshot: TimerSnapshot(timer: timer, elapsedInPhase: elapsed), events: events)
  }

  public func perform(_ command: TimerCommand, noteID: NoteID) async throws -> TimerUpdate {
    if command.startsNewTimer {
      let id = await uuidGenerator.next()
      let wallNow = wallClock.now()
      guard let timer = stateMachine.start(command: command, id: id, noteID: noteID, at: wallNow)
      else {
        return try await snapshot()
      }
      try await repository.saveCurrentTimer(timer)
      currentTimer = timer
      resetAnchor(for: timer, elapsed: .zero, monotonicNow: await monotonicClock.now())
      return TimerUpdate(snapshot: TimerSnapshot(timer: timer, elapsedInPhase: .zero))
    }

    let advanced = try await advanceCurrent()
    guard let timer = currentTimer, let snapshot = advanced.snapshot else {
      return advanced
    }
    let wallNow = wallClock.now()
    let transition = stateMachine.applyControl(
      command,
      to: timer,
      elapsedInPhase: snapshot.elapsedInPhase,
      at: wallNow
    )
    guard transition.changed else { return advanced }
    try await repository.saveCurrentTimer(transition.timer)
    currentTimer = transition.timer
    resetAnchor(
      for: transition.timer,
      elapsed: transition.elapsedInPhase,
      monotonicNow: await monotonicClock.now()
    )
    return TimerUpdate(
      snapshot: TimerSnapshot(
        timer: transition.timer,
        elapsedInPhase: transition.elapsedInPhase
      ),
      events: advanced.events + transition.events
    )
  }

  public func tick() async throws -> TimerUpdate {
    try await advanceCurrent()
  }

  public func synchronizeWallClock() async throws -> TimerUpdate {
    let update = try await advanceCurrent()
    guard var timer = currentTimer, timer.state == .running, let snapshot = update.snapshot else {
      return update
    }
    timer.accumulated = snapshot.elapsedInPhase
    timer.startedAt = wallClock.now()
    try await repository.saveCurrentTimer(timer)
    currentTimer = timer
    resetAnchor(
      for: timer,
      elapsed: snapshot.elapsedInPhase,
      monotonicNow: await monotonicClock.now()
    )
    return TimerUpdate(
      snapshot: TimerSnapshot(timer: timer, elapsedInPhase: snapshot.elapsedInPhase),
      events: update.events
    )
  }

  public func prepareForQuit(pausesRunningTimer: Bool) async throws -> TimerUpdate {
    let update = try await advanceCurrent()
    guard let timer = currentTimer, timer.state == .running, let snapshot = update.snapshot else {
      return update
    }
    if pausesRunningTimer {
      let transition = stateMachine.applyControl(
        .pauseOrResume,
        to: timer,
        elapsedInPhase: snapshot.elapsedInPhase,
        at: wallClock.now()
      )
      try await repository.saveCurrentTimer(transition.timer)
      currentTimer = transition.timer
      anchor = nil
      return TimerUpdate(
        snapshot: TimerSnapshot(
          timer: transition.timer,
          elapsedInPhase: transition.elapsedInPhase
        ),
        events: update.events
      )
    }
    var checkpointed = timer
    checkpointed.accumulated = snapshot.elapsedInPhase
    checkpointed.startedAt = wallClock.now()
    try await repository.saveCurrentTimer(checkpointed)
    currentTimer = checkpointed
    resetAnchor(
      for: checkpointed,
      elapsed: snapshot.elapsedInPhase,
      monotonicNow: await monotonicClock.now()
    )
    return TimerUpdate(
      snapshot: TimerSnapshot(
        timer: checkpointed,
        elapsedInPhase: snapshot.elapsedInPhase
      ),
      events: update.events
    )
  }

  public func removeTimer(linkedTo noteID: NoteID) async throws -> TimerUpdate {
    guard let timer = currentTimer, timer.noteID == noteID else {
      return try await snapshot()
    }
    try await repository.deleteTimer(id: timer.id)
    currentTimer = nil
    anchor = nil
    return TimerUpdate(snapshot: nil)
  }

  public func snapshot() async throws -> TimerUpdate {
    guard let timer = currentTimer else { return TimerUpdate(snapshot: nil) }
    let elapsed = await elapsedInCurrentPhase(for: timer)
    return TimerUpdate(snapshot: TimerSnapshot(timer: timer, elapsedInPhase: elapsed))
  }

  private func advanceCurrent() async throws -> TimerUpdate {
    guard let timer = currentTimer else { return TimerUpdate(snapshot: nil) }
    let elapsed = await elapsedInCurrentPhase(for: timer)
    let transition = stateMachine.advance(
      timer,
      elapsedInPhase: elapsed,
      at: wallClock.now()
    )
    if transition.changed {
      try await repository.saveCurrentTimer(transition.timer)
      currentTimer = transition.timer
      resetAnchor(
        for: transition.timer,
        elapsed: transition.elapsedInPhase,
        monotonicNow: await monotonicClock.now()
      )
    }
    return TimerUpdate(
      snapshot: TimerSnapshot(
        timer: transition.timer,
        elapsedInPhase: transition.elapsedInPhase
      ),
      events: transition.events
    )
  }

  private func elapsedInCurrentPhase(for timer: NoteTimer) async -> Duration {
    guard timer.state == .running,
      let anchor,
      anchor.timerID == timer.id,
      anchor.phase == timer.phase
    else {
      return TimerDuration.clampedNonnegative(timer.accumulated)
    }
    let monotonicNow = await monotonicClock.now()
    let delta = TimerDuration.clampedNonnegative(monotonicNow - anchor.monotonicInstant)
    return anchor.elapsedInPhase + delta
  }

  private func resetAnchor(
    for timer: NoteTimer,
    elapsed: Duration,
    monotonicNow: Duration
  ) {
    guard timer.state == .running else {
      anchor = nil
      return
    }
    anchor = RuntimeAnchor(
      timerID: timer.id,
      phase: timer.phase,
      monotonicInstant: monotonicNow,
      elapsedInPhase: TimerDuration.clampedNonnegative(elapsed)
    )
  }
}
