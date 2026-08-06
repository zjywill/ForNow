import ForNowCore
import Foundation
import XCTest

final class TimerClockScenarioTests: XCTestCase {
  func test_IT_TIME_001_NormalProgressionAndSleepWakeUseMonotonicElapsed() async throws {
    let rig = try await makeRig(wallDate: Date(timeIntervalSince1970: 100))
    _ = try await rig.clock.perform(.startStopwatch(title: nil), noteID: rig.noteID)

    await rig.monotonic.advance(by: .seconds(5))
    let normalProgress = try await rig.clock.tick()
    XCTAssertEqual(normalProgress.snapshot?.elapsedInPhase, .seconds(5))

    await rig.monotonic.advance(by: .seconds(3_600))
    rig.wallClock.advance(by: 3_600)
    let wake = try await rig.clock.synchronizeWallClock()
    XCTAssertEqual(wake.snapshot?.elapsedInPhase, .seconds(3_605))
    XCTAssertEqual(wake.snapshot?.timer.accumulated, .seconds(3_605))
    XCTAssertEqual(wake.snapshot?.timer.startedAt, rig.wallClock.now())
  }

  func test_IT_TIME_001_LiveWallClockAndTimeZoneChangesDoNotJumpDisplay() async throws {
    let rig = try await makeRig(wallDate: Date(timeIntervalSince1970: 10_000))
    _ = try await rig.clock.perform(.startStopwatch(title: nil), noteID: rig.noteID)
    await rig.monotonic.advance(by: .seconds(20))

    rig.wallClock.advance(by: 86_400)
    let afterForwardChange = try await rig.clock.tick()
    XCTAssertEqual(afterForwardChange.snapshot?.elapsedInPhase, .seconds(20))
    let forward = try await rig.clock.synchronizeWallClock()
    XCTAssertEqual(forward.snapshot?.elapsedInPhase, .seconds(20))

    await rig.monotonic.advance(by: .seconds(7))
    rig.wallClock.advance(by: -172_800)
    let afterBackwardChange = try await rig.clock.tick()
    XCTAssertEqual(afterBackwardChange.snapshot?.elapsedInPhase, .seconds(27))
    let backward = try await rig.clock.synchronizeWallClock()
    XCTAssertEqual(backward.snapshot?.elapsedInPhase, .seconds(27))
    XCTAssertEqual(backward.snapshot?.timer.startedAt, rig.wallClock.now())
  }

  func test_IT_TIME_001_BackwardWallRecoveryClampsDeltaWithoutLosingAccumulated() async throws {
    let wallClock = TimerScenarioWallClock(Date(timeIntervalSince1970: 90))
    let repository = try await preparedRepository()
    let timer = NoteTimer(
      id: timerID,
      noteID: noteID,
      kind: .countdown,
      phase: .primary,
      state: .running,
      startedAt: Date(timeIntervalSince1970: 100),
      accumulated: .seconds(12),
      workDuration: .seconds(60)
    )
    try await repository.saveCurrentTimer(timer)
    let clock = makeClock(repository: repository, wallClock: wallClock)

    let loaded = try await clock.load()

    XCTAssertEqual(loaded.snapshot?.elapsedInPhase, .seconds(12))
    XCTAssertEqual(loaded.snapshot?.timer.accumulated, .seconds(12))
    XCTAssertEqual(loaded.snapshot?.timer.startedAt, wallClock.now())
  }

  func test_IT_TIME_001_ForcedTerminationAndDayBoundaryRecoverFromWallAnchor() async throws {
    let calendar = Calendar(identifier: .gregorian)
    let startedAt = try XCTUnwrap(
      calendar.date(
        from: DateComponents(
          timeZone: TimeZone(secondsFromGMT: 0),
          year: 2026,
          month: 8,
          day: 6,
          hour: 23,
          minute: 59,
          second: 50
        )
      )
    )
    let repository = try await preparedRepository()
    let timer = NoteTimer(
      id: timerID,
      noteID: noteID,
      kind: .countdown,
      phase: .primary,
      state: .running,
      startedAt: startedAt,
      workDuration: .seconds(60)
    )
    try await repository.saveCurrentTimer(timer)
    let wallClock = TimerScenarioWallClock(startedAt.addingTimeInterval(20))
    let relaunchedClock = makeClock(repository: repository, wallClock: wallClock)

    let loaded = try await relaunchedClock.load()

    XCTAssertEqual(loaded.snapshot?.timer.state, .running)
    XCTAssertEqual(loaded.snapshot?.elapsedInPhase, .seconds(20))
    XCTAssertEqual(loaded.snapshot?.timer.startedAt, wallClock.now())
  }

  func test_IT_TIME_001_WallRecoveryCarriesAcrossPomodoroPhaseBoundary() async throws {
    let repository = try await preparedRepository()
    let timer = NoteTimer(
      id: timerID,
      noteID: noteID,
      kind: .pomodoro,
      title: "Focus",
      phase: .work,
      state: .running,
      startedAt: Date(timeIntervalSince1970: 100),
      workDuration: .seconds(60),
      restDuration: .seconds(30)
    )
    try await repository.saveCurrentTimer(timer)
    let wallClock = TimerScenarioWallClock(Date(timeIntervalSince1970: 175))
    let clock = makeClock(repository: repository, wallClock: wallClock)

    let loaded = try await clock.load()

    XCTAssertEqual(loaded.snapshot?.timer.phase, .rest)
    XCTAssertEqual(loaded.snapshot?.timer.state, .running)
    XCTAssertEqual(loaded.snapshot?.elapsedInPhase, .seconds(15))
    XCTAssertEqual(loaded.events.map(\.kind), [.pomodoroBreakBegan])
    let persisted = try await repository.currentTimer()
    XCTAssertEqual(persisted?.accumulated, .seconds(15))
  }

  private let timerID = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
  private let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!

  private func makeRig(wallDate: Date) async throws -> TimerClockScenarioRig {
    let repository = try await preparedRepository()
    let wallClock = TimerScenarioWallClock(wallDate)
    let monotonic = ManualMonotonicClock()
    let clock = TimerClock(
      repository: repository,
      wallClock: wallClock,
      monotonicClock: monotonic,
      uuidGenerator: SequenceUUIDGenerator(values: [timerID])
    )
    _ = try await clock.load()
    return TimerClockScenarioRig(
      clock: clock,
      monotonic: monotonic,
      wallClock: wallClock,
      noteID: noteID
    )
  }

  private func makeClock(
    repository: InMemoryNoteRepository,
    wallClock: TimerScenarioWallClock
  ) -> TimerClock {
    TimerClock(
      repository: repository,
      wallClock: wallClock,
      monotonicClock: ManualMonotonicClock(),
      uuidGenerator: SequenceUUIDGenerator(values: [timerID])
    )
  }

  private func preparedRepository() async throws -> InMemoryNoteRepository {
    let repository = InMemoryNoteRepository()
    try await repository.prepare()
    try await repository.schedule(
      NoteDraft(id: noteID, body: "timer", modifiedAt: Date(timeIntervalSince1970: 100))
    )
    _ = try await repository.flush()
    return repository
  }
}

private struct TimerClockScenarioRig {
  let clock: TimerClock
  let monotonic: ManualMonotonicClock
  let wallClock: TimerScenarioWallClock
  let noteID: NoteID
}

private final class TimerScenarioWallClock: WallClock, @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) {
    self.date = date
  }

  func now() -> Date {
    lock.withLock { date }
  }

  func advance(by interval: TimeInterval) {
    lock.withLock { date = date.addingTimeInterval(interval) }
  }
}
