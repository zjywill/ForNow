import ForNowCore
import ForNowIntegrations
import ForNowWindowing
import Foundation
import XCTest

@testable import ForNow

@MainActor
final class TimerModelTests: XCTestCase {
  func test_IT_TIME_003A_SettingsDefaultsAndUserDefaultsRoundTrip() async throws {
    XCTAssertEqual(
      TimerSettings(),
      TimerSettings(
        pausesOnQuit: false,
        showsTimeInMenuBar: true,
        showsCountdownNotifications: false,
        showsCountdownTakeover: false,
        playsCountdownSound: true,
        showsPomodoroBreakNotifications: false,
        showsPomodoroBreakTakeover: false,
        playsPomodoroBreakSound: true,
        soundVolume: 70
      )
    )

    let suiteName = "ForNowTimerSettingsTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let expected = TimerSettings(
      pausesOnQuit: true,
      showsTimeInMenuBar: false,
      showsCountdownNotifications: true,
      showsCountdownTakeover: true,
      playsCountdownSound: false,
      showsPomodoroBreakNotifications: true,
      showsPomodoroBreakTakeover: true,
      playsPomodoroBreakSound: false,
      soundVolume: 0
    )
    try await UserDefaultsTimerSettingsStore(suiteName: suiteName).save(expected)
    let loaded = await UserDefaultsTimerSettingsStore(suiteName: suiteName).load()

    XCTAssertEqual(loaded, expected)
  }

  func test_IT_TIME_003B_MenuBarStatusFollowsIndependentSetting() async throws {
    let rig = try await makeRig()
    try await rig.model.perform(
      .startCountdown(duration: .seconds(60), title: "Tea"),
      noteID: rig.noteID
    )

    XCTAssertEqual(rig.window.timerStatusPresentation?.text, "1:00")
    XCTAssertEqual(
      rig.window.timerStatusPresentation?.accessibilityLabel,
      "Timer. Tea. Countdown running. 1:00."
    )

    var hidden = rig.model.settings
    hidden.showsTimeInMenuBar = false
    try await rig.model.updateSettings(hidden)
    XCTAssertNil(rig.window.timerStatusPresentation)

    hidden.showsTimeInMenuBar = true
    try await rig.model.updateSettings(hidden)
    XCTAssertEqual(rig.window.timerStatusPresentation?.text, "1:00")
  }

  func test_IT_TIME_003C_CountdownNotificationUsesTimestampRemainingTime() async throws {
    var settings = TimerSettings()
    settings.showsCountdownNotifications = true
    settings.playsCountdownSound = false
    let rig = try await makeRig(settings: settings)

    try await rig.model.perform(
      .startCountdown(duration: .seconds(90), title: "Laundry"),
      noteID: rig.noteID
    )

    let scheduled = await rig.notifications.scheduledTimerNotifications()
    let request = try XCTUnwrap(scheduled.first)
    XCTAssertEqual(request.kind, .countdownCompleted)
    XCTAssertEqual(request.fireDate, rig.wallClock.now().addingTimeInterval(90))
    XCTAssertEqual(request.title, "Laundry")
    XCTAssertEqual(request.body, "Countdown finished")
    XCTAssertFalse(request.playsSound)
  }

  func test_IT_TIME_003D_PomodoroNotificationTargetsBreakStart() async throws {
    var settings = TimerSettings()
    settings.showsPomodoroBreakNotifications = true
    let rig = try await makeRig(settings: settings)

    try await rig.model.perform(
      .startPomodoro(work: .seconds(45), rest: .seconds(15), title: nil),
      noteID: rig.noteID
    )

    let scheduled = await rig.notifications.scheduledTimerNotifications()
    let request = try XCTUnwrap(scheduled.first)
    XCTAssertEqual(request.kind, .pomodoroBreakBegan)
    XCTAssertEqual(request.fireDate, rig.wallClock.now().addingTimeInterval(45))
    XCTAssertEqual(request.title, "Break Time")
    XCTAssertEqual(request.body, "Work interval finished")
    XCTAssertTrue(request.playsSound)
  }

  func test_IT_TIME_003E_DeniedNotificationsNeverAffectCompletion() async throws {
    var settings = TimerSettings()
    settings.showsCountdownNotifications = true
    settings.playsCountdownSound = false
    let rig = try await makeRig(settings: settings, authorization: .denied)

    try await rig.model.perform(
      .startCountdown(duration: .seconds(1), title: nil),
      noteID: rig.noteID
    )
    let scheduled = await rig.notifications.scheduledTimerNotifications()
    let authorizationRequestCount = await rig.notifications.requestedAuthorizationCount()
    XCTAssertTrue(scheduled.isEmpty)
    XCTAssertEqual(authorizationRequestCount, 0)

    await rig.monotonicClock.advance(by: .seconds(2))
    await rig.model.synchronizeClock()

    XCTAssertEqual(rig.model.snapshot?.timer.state, .completed)
    XCTAssertEqual(rig.model.snapshot?.elapsedInPhase, .seconds(1))
    XCTAssertFalse(rig.model.hasPersistenceFailure)
  }

  func test_IT_TIME_003F_CountdownSoundUsesVolumeAndEmitsOnce() async throws {
    var settings = TimerSettings()
    settings.soundVolume = 37
    let rig = try await makeRig(settings: settings)

    try await rig.model.perform(
      .startCountdown(duration: .seconds(1), title: nil),
      noteID: rig.noteID
    )
    await rig.monotonicClock.advance(by: .seconds(2))
    await rig.model.synchronizeClock()
    await rig.model.synchronizeClock()

    XCTAssertEqual(rig.sound.playedVolumes, [37])
  }

  func test_IT_TIME_003G_PomodoroBreakSoundUsesIndependentSetting() async throws {
    var settings = TimerSettings()
    settings.playsCountdownSound = false
    settings.playsPomodoroBreakSound = true
    settings.soundVolume = 82
    let rig = try await makeRig(settings: settings)

    try await rig.model.perform(
      .startPomodoro(work: .seconds(1), rest: .seconds(30), title: nil),
      noteID: rig.noteID
    )
    await rig.monotonicClock.advance(by: .seconds(2))
    await rig.model.synchronizeClock()
    await rig.model.synchronizeClock()

    XCTAssertEqual(rig.model.snapshot?.timer.phase, .rest)
    XCTAssertEqual(rig.sound.playedVolumes, [82])
  }

  func test_IT_TIME_003H_CountdownTakeoverUsesIndependentSetting() async throws {
    var settings = TimerSettings()
    settings.playsCountdownSound = false
    settings.showsCountdownTakeover = true
    let rig = try await makeRig(settings: settings)
    XCTAssertFalse(rig.window.isWindowVisible)

    try await rig.model.perform(
      .startCountdown(duration: .seconds(1), title: "Tea"),
      noteID: rig.noteID
    )
    await rig.monotonicClock.advance(by: .seconds(1))
    await rig.model.synchronizeClock()

    XCTAssertEqual(rig.window.timerTakeoverPresentation?.title, "Tea")
    XCTAssertEqual(rig.window.timerTakeoverPresentation?.detail, "Countdown finished")
  }

  func test_IT_TIME_003I_PomodoroBreakTakeoverUsesIndependentSetting() async throws {
    var settings = TimerSettings()
    settings.playsPomodoroBreakSound = false
    settings.showsPomodoroBreakTakeover = true
    let rig = try await makeRig(settings: settings)

    try await rig.model.perform(
      .startPomodoro(work: .seconds(1), rest: .seconds(30), title: "Focus"),
      noteID: rig.noteID
    )
    await rig.monotonicClock.advance(by: .seconds(1))
    await rig.model.synchronizeClock()

    XCTAssertEqual(rig.window.timerTakeoverPresentation?.title, "Focus")
    XCTAssertEqual(rig.window.timerTakeoverPresentation?.detail, "Work interval finished")
  }

  func test_IT_TIME_003J_PauseOnQuitControlsRelaunchProgression() async throws {
    var pausedSettings = TimerSettings()
    pausedSettings.pausesOnQuit = true
    let pausedRig = try await makeRig(settings: pausedSettings)
    try await pausedRig.model.perform(
      .startCountdown(duration: .seconds(60), title: nil),
      noteID: pausedRig.noteID
    )
    await pausedRig.monotonicClock.advance(by: .seconds(10))
    try await pausedRig.model.prepareForQuit()
    XCTAssertEqual(pausedRig.model.snapshot?.timer.state, .paused)
    XCTAssertEqual(pausedRig.model.snapshot?.timer.accumulated, .seconds(10))
    XCTAssertNil(pausedRig.model.snapshot?.timer.startedAt)

    let runningRig = try await makeRig()
    try await runningRig.model.perform(
      .startCountdown(duration: .seconds(60), title: nil),
      noteID: runningRig.noteID
    )
    await runningRig.monotonicClock.advance(by: .seconds(10))
    try await runningRig.model.prepareForQuit()
    XCTAssertEqual(runningRig.model.snapshot?.timer.state, .running)
    XCTAssertEqual(runningRig.model.snapshot?.timer.accumulated, .seconds(10))

    runningRig.wallClock.advance(by: 5)
    let relaunchedClock = TimerClock(
      repository: runningRig.repository,
      wallClock: runningRig.wallClock,
      monotonicClock: ManualMonotonicClock(),
      uuidGenerator: SequenceUUIDGenerator(values: [UUID()])
    )
    let relaunched = try await relaunchedClock.load()
    XCTAssertEqual(relaunched.snapshot?.timer.state, .running)
    XCTAssertEqual(relaunched.snapshot?.elapsedInPhase, .seconds(15))
  }

  private func makeRig(
    settings: TimerSettings = TimerSettings(),
    authorization: NotificationAuthorizationState = .authorized
  ) async throws -> TimerModelTestRig {
    let noteID = UUID()
    let repository = InMemoryNoteRepository()
    try await repository.prepare()
    try await repository.schedule(
      NoteDraft(
        id: noteID,
        body: "timer test source",
        modifiedAt: Date(timeIntervalSince1970: 100)
      )
    )
    _ = try await repository.flush()
    let wallClock = TimerTestWallClock(Date(timeIntervalSince1970: 100))
    let monotonicClock = ManualMonotonicClock()
    let notifications = RecordingNotificationService(state: authorization)
    let sound = DisabledTimerSoundPlayer()
    let window = DisabledWindowCoordinator()
    let model = TimerModel(
      timerClock: TimerClock(
        repository: repository,
        wallClock: wallClock,
        monotonicClock: monotonicClock,
        uuidGenerator: SequenceUUIDGenerator(values: [UUID()])
      ),
      wallClock: wallClock,
      settingsStore: InMemoryTimerSettingsStore(),
      notifications: notifications,
      soundPlayer: sound,
      windowCoordinator: window
    )
    try await model.updateSettings(settings)
    return TimerModelTestRig(
      model: model,
      repository: repository,
      wallClock: wallClock,
      monotonicClock: monotonicClock,
      notifications: notifications,
      sound: sound,
      window: window,
      noteID: noteID
    )
  }
}

@MainActor
private struct TimerModelTestRig {
  let model: TimerModel
  let repository: InMemoryNoteRepository
  let wallClock: TimerTestWallClock
  let monotonicClock: ManualMonotonicClock
  let notifications: RecordingNotificationService
  let sound: DisabledTimerSoundPlayer
  let window: DisabledWindowCoordinator
  let noteID: NoteID
}

private final class TimerTestWallClock: WallClock, @unchecked Sendable {
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
