import AppKit
import ForNowCore
import ForNowEditor
import ForNowModes
import XCTest

final class TimerCommandTests: XCTestCase {
  func test_UT_TIME_001A_StopwatchAndFirstLineTutorialParse() throws {
    let document = TimerCommandParser().parse(in: "timer")
    let match = try XCTUnwrap(document.commands.first)

    XCTAssertEqual(match.command, .startStopwatch(title: nil))
    XCTAssertEqual(match.sourceRange, NSRange(location: 0, length: 5))
    XCTAssertEqual(match.anchorUTF16Offset, 5)
    XCTAssertTrue(match.showsTutorial)
    XCTAssertTrue(document.diagnostics.isEmpty)
  }

  func test_UT_TIME_001B_DecimalMinuteCountdownParsesExactly() throws {
    let match = try XCTUnwrap(TimerCommandParser().parse(in: "timer 3.5").commands.first)
    XCTAssertEqual(
      match.command,
      .startCountdown(duration: .seconds(210), title: nil)
    )
    XCTAssertFalse(match.showsTutorial)
  }

  func test_UT_TIME_001C_MinuteSecondAndTitledCountdownParse() throws {
    let document = TimerCommandParser().parse(in: "timer 3:30:  Do laundry  ")
    let match = try XCTUnwrap(document.commands.first)
    XCTAssertEqual(
      match.command,
      .startCountdown(duration: .seconds(210), title: "Do laundry")
    )
  }

  func test_UT_TIME_001D_CustomWorkRestCycleParses() throws {
    let match = try XCTUnwrap(
      TimerCommandParser().parse(in: "timer 5 1: Focus block").commands.first
    )
    XCTAssertEqual(
      match.command,
      .startPomodoro(work: .seconds(300), rest: .seconds(60), title: "Focus block")
    )
  }

  func test_UT_TIME_001E_StandardPomodoroParses() throws {
    let match = try XCTUnwrap(TimerCommandParser().parse(in: "timer pomo").commands.first)
    XCTAssertEqual(
      match.command,
      .startPomodoro(work: .seconds(1_500), rest: .seconds(300), title: nil)
    )
  }

  func test_UT_TIME_001F_ControlCommandsParse() {
    let parser = TimerCommandParser()
    XCTAssertEqual(parser.parse(in: "timer p").commands.first?.command, .pauseOrResume)
    XCTAssertEqual(parser.parse(in: "timer r").commands.first?.command, .restart)
    XCTAssertEqual(parser.parse(in: "timer s").commands.first?.command, .stop)
    XCTAssertEqual(parser.parse(in: "timer 0").commands.first?.command, .stop)
  }

  func test_UT_TIME_001G_CommandsAreLineScopedCaseInsensitiveAndAliasAware() throws {
    var settings = ModeSettings()
    let index = try XCTUnwrap(settings.definitions.firstIndex { $0.modeID == .timer })
    settings.definitions[index] = ModeAliasDefinition(
      modeID: .timer,
      aliases: ["clock", "tmr"],
      mainAlias: "clock"
    )
    let source = "ordinary\nCLOCK 0:45\ntmr p"
    let matches = TimerCommandParser(settings: settings).parse(in: source).commands

    XCTAssertEqual(matches.map(\.matchedAlias), ["clock", "tmr"])
    XCTAssertEqual(
      matches.map(\.command),
      [.startCountdown(duration: .seconds(45), title: nil), .pauseOrResume]
    )
    XCTAssertEqual(matches[0].sourceRange.location, 9)
  }

  func test_UT_TIME_001H_InvalidAndOutOfRangeDurationsAreDistinct() {
    let parser = TimerCommandParser()
    XCTAssertEqual(
      parser.parse(in: "timer 3:99").diagnostics.first?.code,
      .invalidDuration
    )
    XCTAssertEqual(
      parser.parse(in: "timer 10081").diagnostics.first?.code,
      .durationOutOfRange
    )
    XCTAssertEqual(
      parser.parse(in: "timer -1").diagnostics.first?.code,
      .invalidDuration
    )
  }

  func test_UT_TIME_001I_SyntaxTitleLeadingWhitespaceAndMasterSwitchAreDeterministic() {
    let parser = TimerCommandParser()
    XCTAssertEqual(parser.parse(in: "timer 5:").diagnostics.first?.code, .emptyTitle)
    XCTAssertEqual(parser.parse(in: "timer 1 2 3").diagnostics.first?.code, .invalidSyntax)
    XCTAssertTrue(parser.parse(in: " timer 5").commands.isEmpty)
    XCTAssertTrue(parser.parse(in: " timer 5").diagnostics.isEmpty)

    var settings = ModeSettings()
    settings.keywordInterpretationEnabled = false
    let disabled = TimerCommandParser(settings: settings).parse(in: "timer 5")
    XCTAssertTrue(disabled.commands.isEmpty)
    XCTAssertTrue(disabled.diagnostics.isEmpty)
  }

  func test_UT_TIME_001J_ParserLineBoundAndCancellationAreEnforced() async throws {
    let oversized = Array(repeating: "ordinary", count: 10_001).joined(separator: "\n")
    XCTAssertEqual(
      TimerCommandParser().parse(in: oversized).diagnostics.last?.code,
      .documentTooLarge
    )

    let task = Task.detached {
      try TimerCommandParser().parseCancellable(in: oversized)
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("A cancelled timer parse must not complete")
    } catch is CancellationError {
    }
  }

  func test_UT_TIME_001K_TimerProjectionAndCopyRemainSourceOnly() throws {
    let source = "note\ntimer 2: Tea"
    let snapshot = SourceSnapshot(version: 9, text: source)
    let projection = SpikeProjectionParser().parse(snapshot)
    let timerDecoration = try XCTUnwrap(
      projection.decorations.first(where: {
        if case .timer = $0 { return true }
        return false
      })
    )

    guard case .timer(let anchor, let presentation) = timerDecoration else {
      return XCTFail("Expected a timer decoration")
    }
    XCTAssertEqual(anchor.utf16Offset, source.utf16.count)
    XCTAssertEqual(presentation.sourceRange.nsRange, NSRange(location: 5, length: 12))
    XCTAssertNil(ProjectionCopyPolicy().copyText(for: timerDecoration))
    XCTAssertEqual(snapshot.text, source)
  }

  @MainActor
  func test_UT_TIME_001L_ReturnCommitsOnceAndInteractionsDoNotMutateSource() async throws {
    let container = ProjectionEditorContainer(initialText: "timer")
    container.textView.setSelectedRange(NSRange(location: 5, length: 0))
    var commands: [TimerCommand] = []
    var commandSources: [String] = []
    var interactions: [EditorTimerInteraction] = []
    container.timerCommandDidCommit = { command, source in
      commands.append(command)
      commandSources.append(source)
    }
    container.timerInteractionHandler = { interactions.append($0) }

    container.textView.insertNewline(nil)
    container.performTimerInteraction(.singleClick)
    container.performTimerInteraction(.stop)

    XCTAssertEqual(commands, [.startStopwatch(title: nil)])
    XCTAssertEqual(commandSources, ["timer\n"])
    XCTAssertEqual(interactions, [.singleClick, .stop])
    XCTAssertEqual(container.textView.string, "timer\n")
    await container.waitForPendingProjection()
    XCTAssertTrue(
      container.currentProjection.decorations.contains(where: {
        if case .timer = $0 { return true }
        return false
      })
    )
  }

  func test_UT_TIME_002A_StartTransitionsCreateRunningKinds() throws {
    let machine = TimerStateMachine()
    let date = Date(timeIntervalSince1970: 100)
    let stopwatch = try XCTUnwrap(
      machine.start(command: .startStopwatch(title: nil), id: timerID, noteID: noteID, at: date)
    )
    let countdown = try XCTUnwrap(
      machine.start(
        command: .startCountdown(duration: .seconds(60), title: "Tea"),
        id: timerID,
        noteID: noteID,
        at: date
      )
    )
    XCTAssertEqual(stopwatch.state, .running)
    XCTAssertEqual(stopwatch.kind, .stopwatch)
    XCTAssertEqual(countdown.kind, .countdown)
    XCTAssertEqual(countdown.workDuration, .seconds(60))
  }

  func test_UT_TIME_002B_RunningPausesAtExactElapsedValue() {
    let timer = runningCountdown()
    let transition = TimerStateMachine().applyControl(
      .pauseOrResume,
      to: timer,
      elapsedInPhase: .seconds(12),
      at: Date(timeIntervalSince1970: 112)
    )
    XCTAssertEqual(transition.timer.state, .paused)
    XCTAssertEqual(transition.timer.accumulated, .seconds(12))
    XCTAssertNil(transition.timer.startedAt)
  }

  func test_UT_TIME_002C_PausedResumesFromAccumulatedValue() {
    var timer = runningCountdown()
    timer.state = .paused
    timer.startedAt = nil
    timer.accumulated = .seconds(12)
    let date = Date(timeIntervalSince1970: 200)
    let transition = TimerStateMachine().applyControl(
      .pauseOrResume,
      to: timer,
      elapsedInPhase: .seconds(12),
      at: date
    )
    XCTAssertEqual(transition.timer.state, .running)
    XCTAssertEqual(transition.timer.accumulated, .seconds(12))
    XCTAssertEqual(transition.timer.startedAt, date)
  }

  func test_UT_TIME_002D_PauseToggleIsIntentionalAndTerminalPauseIsNoOp() {
    let machine = TimerStateMachine()
    let paused = machine.applyControl(
      .pauseOrResume,
      to: runningCountdown(),
      elapsedInPhase: .seconds(5),
      at: Date()
    ).timer
    XCTAssertEqual(
      machine.applyControl(
        .pauseOrResume,
        to: paused,
        elapsedInPhase: .seconds(5),
        at: Date()
      ).timer.state,
      .running
    )
    var completed = runningCountdown()
    completed.state = .completed
    XCTAssertFalse(
      machine.applyControl(
        .pauseOrResume,
        to: completed,
        elapsedInPhase: .seconds(60),
        at: Date()
      ).changed
    )
  }

  func test_UT_TIME_002E_StopRunningCancelsAndPreservesElapsed() {
    let transition = TimerStateMachine().applyControl(
      .stop,
      to: runningCountdown(),
      elapsedInPhase: .seconds(9),
      at: Date()
    )
    XCTAssertEqual(transition.timer.state, .cancelled)
    XCTAssertEqual(transition.timer.accumulated, .seconds(9))
  }

  func test_UT_TIME_002F_StopPausedCancels() {
    var timer = runningCountdown()
    timer.state = .paused
    timer.startedAt = nil
    timer.accumulated = .seconds(8)
    XCTAssertEqual(
      TimerStateMachine().applyControl(
        .stop,
        to: timer,
        elapsedInPhase: .seconds(8),
        at: Date()
      ).timer.state,
      .cancelled
    )
  }

  func test_UT_TIME_002G_RepeatedStopIsNoOp() {
    var timer = runningCountdown()
    timer.state = .cancelled
    timer.startedAt = nil
    XCTAssertFalse(
      TimerStateMachine().applyControl(
        .stop,
        to: timer,
        elapsedInPhase: .seconds(4),
        at: Date()
      ).changed
    )
  }

  func test_UT_TIME_002H_RestartRunningResetsInitialPhase() {
    var timer = runningPomodoro()
    timer.phase = .rest
    timer.accumulated = .seconds(10)
    let transition = TimerStateMachine().applyControl(
      .restart,
      to: timer,
      elapsedInPhase: .seconds(10),
      at: Date(timeIntervalSince1970: 300)
    )
    XCTAssertEqual(transition.timer.phase, .work)
    XCTAssertEqual(transition.timer.state, .running)
    XCTAssertEqual(transition.timer.accumulated, .zero)
  }

  func test_UT_TIME_002I_RestartEveryTerminalStateIsValid() {
    for state in [TimerState.paused, .completed, .cancelled, .idle] {
      var timer = runningCountdown()
      timer.state = state
      let transition = TimerStateMachine().applyControl(
        .restart,
        to: timer,
        elapsedInPhase: .seconds(20),
        at: Date()
      )
      XCTAssertTrue(transition.changed)
      XCTAssertEqual(transition.timer.state, .running)
      XCTAssertEqual(transition.timer.accumulated, .zero)
    }
  }

  func test_UT_TIME_002J_CountdownCompletesAndEmitsExactlyOneEvent() {
    let machine = TimerStateMachine()
    let completed = machine.advance(
      runningCountdown(),
      elapsedInPhase: .seconds(61),
      at: Date()
    )
    XCTAssertEqual(completed.timer.state, .completed)
    XCTAssertEqual(completed.elapsedInPhase, .seconds(60))
    XCTAssertEqual(completed.events.map(\.kind), [.countdownCompleted])
    XCTAssertTrue(
      machine.advance(
        completed.timer,
        elapsedInPhase: .seconds(60),
        at: Date()
      ).events.isEmpty
    )
  }

  func test_UT_TIME_002K_PomodoroCarriesOvershootIntoBreak() {
    let transition = TimerStateMachine().advance(
      runningPomodoro(),
      elapsedInPhase: .seconds(65),
      at: Date(timeIntervalSince1970: 165)
    )
    XCTAssertEqual(transition.timer.phase, .rest)
    XCTAssertEqual(transition.timer.state, .running)
    XCTAssertEqual(transition.elapsedInPhase, .seconds(5))
    XCTAssertEqual(transition.events.map(\.kind), [.pomodoroBreakBegan])
  }

  func test_UT_TIME_002L_PomodoroRestCompletesSilently() {
    var timer = runningPomodoro()
    timer.phase = .rest
    let transition = TimerStateMachine().advance(
      timer,
      elapsedInPhase: .seconds(30),
      at: Date()
    )
    XCTAssertEqual(transition.timer.state, .completed)
    XCTAssertTrue(transition.events.isEmpty)
  }

  func test_UT_TIME_002M_StopwatchUsesMonotonicElapsedAndNeverCompletes() async throws {
    let repository = try await preparedRepository()
    let monotonic = ManualMonotonicClock()
    let clock = TimerClock(
      repository: repository,
      wallClock: FixedWallClock(Date(timeIntervalSince1970: 100)),
      monotonicClock: monotonic,
      uuidGenerator: SequenceUUIDGenerator(values: [timerID])
    )
    _ = try await clock.load()
    _ = try await clock.perform(.startStopwatch(title: nil), noteID: noteID)
    await monotonic.advance(by: .seconds(3_600))
    let update = try await clock.tick()
    XCTAssertEqual(update.snapshot?.timer.state, .running)
    XCTAssertEqual(update.snapshot?.elapsedInPhase, .seconds(3_600))
  }

  func test_UT_TIME_002N_ControlsWithoutCurrentTimerAreNoOps() async throws {
    let repository = try await preparedRepository()
    let clock = TimerClock(
      repository: repository,
      wallClock: FixedWallClock(Date()),
      monotonicClock: ManualMonotonicClock(),
      uuidGenerator: SequenceUUIDGenerator(values: [timerID])
    )
    _ = try await clock.load()
    let pause = try await clock.perform(.pauseOrResume, noteID: noteID)
    let restart = try await clock.perform(.restart, noteID: noteID)
    let stop = try await clock.perform(.stop, noteID: noteID)
    XCTAssertNil(pause.snapshot)
    XCTAssertNil(restart.snapshot)
    XCTAssertNil(stop.snapshot)
  }

  func test_ET_TIME_002_ClickAndEscapeUseSharedStateMachineCommands() async throws {
    let repository = try await preparedRepository()
    let monotonic = ManualMonotonicClock()
    let clock = TimerClock(
      repository: repository,
      wallClock: FixedWallClock(Date(timeIntervalSince1970: 100)),
      monotonicClock: monotonic,
      uuidGenerator: SequenceUUIDGenerator(values: [timerID])
    )
    _ = try await clock.load()
    _ = try await clock.perform(
      .startCountdown(duration: .seconds(60), title: nil),
      noteID: noteID
    )
    await monotonic.advance(by: .seconds(5))
    let paused = try await clock.perform(.pauseOrResume, noteID: noteID)
    XCTAssertEqual(paused.snapshot?.timer.state, .paused)
    let stopped = try await clock.perform(.stop, noteID: noteID)
    XCTAssertEqual(stopped.snapshot?.timer.state, .cancelled)
    XCTAssertEqual(stopped.snapshot?.elapsedInPhase, .seconds(5))
  }

  private let timerID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
  private let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

  private func runningCountdown() -> NoteTimer {
    NoteTimer(
      id: timerID,
      noteID: noteID,
      kind: .countdown,
      title: "Tea",
      phase: .primary,
      state: .running,
      startedAt: Date(timeIntervalSince1970: 100),
      workDuration: .seconds(60)
    )
  }

  private func runningPomodoro() -> NoteTimer {
    NoteTimer(
      id: timerID,
      noteID: noteID,
      kind: .pomodoro,
      phase: .work,
      state: .running,
      startedAt: Date(timeIntervalSince1970: 100),
      workDuration: .seconds(60),
      restDuration: .seconds(30)
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
