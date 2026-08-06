import Combine
import ForNowCore
import ForNowIntegrations
import ForNowWindowing
import Foundation

@MainActor
final class TimerModel: ObservableObject {
  @Published private(set) var snapshot: TimerSnapshot?
  @Published private(set) var settings = TimerSettings()
  @Published private(set) var hasPersistenceFailure = false

  private let timerClock: TimerClock
  private let wallClock: any WallClock
  private let settingsStore: any TimerSettingsStoring
  private let notifications: any NotificationService
  private let soundPlayer: any TimerSoundPlaying
  private let windowCoordinator: any WindowCoordinating
  private var tickerTask: Task<Void, Never>?
  private var isClockActive = false

  init(
    timerClock: TimerClock,
    wallClock: any WallClock,
    settingsStore: any TimerSettingsStoring,
    notifications: any NotificationService,
    soundPlayer: any TimerSoundPlaying,
    windowCoordinator: any WindowCoordinating
  ) {
    self.timerClock = timerClock
    self.wallClock = wallClock
    self.settingsStore = settingsStore
    self.notifications = notifications
    self.soundPlayer = soundPlayer
    self.windowCoordinator = windowCoordinator
  }

  deinit {
    tickerTask?.cancel()
  }

  func start() async throws {
    isClockActive = true
    settings = await settingsStore.load()
    let update = try await timerClock.load()
    await apply(update, dispatchesEvents: false, reschedulesNotification: true)
  }

  func perform(_ command: TimerCommand, noteID: NoteID) async throws {
    let update = try await timerClock.perform(command, noteID: noteID)
    await apply(update, dispatchesEvents: true, reschedulesNotification: true)
  }

  func handleSingleClick() async throws {
    guard snapshot != nil else { return }
    let update = try await timerClock.perform(.pauseOrResume, noteID: snapshot!.timer.noteID)
    await apply(update, dispatchesEvents: true, reschedulesNotification: true)
  }

  func handleStop() async throws {
    guard snapshot != nil else { return }
    let update = try await timerClock.perform(.stop, noteID: snapshot!.timer.noteID)
    await apply(update, dispatchesEvents: true, reschedulesNotification: true)
  }

  func synchronizeClock() async {
    do {
      let update = try await timerClock.synchronizeWallClock()
      await apply(update, dispatchesEvents: true, reschedulesNotification: true)
    } catch {
      hasPersistenceFailure = true
    }
  }

  func prepareForQuit() async throws {
    isClockActive = false
    tickerTask?.cancel()
    tickerTask = nil
    let update = try await timerClock.prepareForQuit(
      pausesRunningTimer: settings.pausesOnQuit
    )
    await apply(update, dispatchesEvents: true, reschedulesNotification: true)
  }

  func removeTimer(linkedTo noteID: NoteID) async throws {
    let update = try await timerClock.removeTimer(linkedTo: noteID)
    await apply(update, dispatchesEvents: false, reschedulesNotification: true)
  }

  func updateSettings(_ settings: TimerSettings) async throws {
    let previous = self.settings
    let settings = try settings.validated()
    self.settings = settings
    do {
      try await settingsStore.save(settings)
      updateStatusItem()
      await rescheduleNotification()
    } catch {
      if self.settings == settings {
        self.settings = previous
        updateStatusItem()
      }
      throw error
    }
  }

  func snapshot(linkedTo noteID: NoteID?) -> TimerSnapshot? {
    guard snapshot?.timer.noteID == noteID else { return nil }
    return snapshot
  }

  private func tick() async {
    do {
      let previousTimer = snapshot?.timer
      let update = try await timerClock.tick()
      let reschedules = previousTimer != update.snapshot?.timer
      await apply(
        update,
        dispatchesEvents: true,
        reschedulesNotification: reschedules
      )
    } catch {
      hasPersistenceFailure = true
      tickerTask?.cancel()
      tickerTask = nil
    }
  }

  private func apply(
    _ update: TimerUpdate,
    dispatchesEvents: Bool,
    reschedulesNotification: Bool
  ) async {
    snapshot = update.snapshot
    hasPersistenceFailure = false
    updateStatusItem()
    if dispatchesEvents {
      for event in update.events {
        present(event)
      }
    }
    if reschedulesNotification {
      await rescheduleNotification()
    }
    updateTicker()
  }

  private func updateTicker() {
    guard isClockActive, snapshot?.isRunning == true else {
      tickerTask?.cancel()
      tickerTask = nil
      return
    }
    guard tickerTask == nil else { return }
    tickerTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, let self else { return }
        await self.tick()
        guard self.snapshot?.isRunning == true else { return }
      }
    }
  }

  private func updateStatusItem() {
    guard settings.showsTimeInMenuBar, let snapshot, snapshot.isExternallyVisible else {
      windowCoordinator.updateTimerStatus(nil)
      return
    }
    windowCoordinator.updateTimerStatus(
      TimerStatusPresentation(
        text: snapshot.menuBarText,
        accessibilityLabel: snapshot.accessibilityLabel
      )
    )
  }

  private func present(_ event: TimerEvent) {
    switch event.kind {
    case .countdownCompleted:
      if settings.playsCountdownSound {
        soundPlayer.play(volume: settings.soundVolume)
      }
      if settings.showsCountdownTakeover {
        windowCoordinator.presentTimerTakeover(
          TimerTakeoverPresentation(
            id: event.timerID,
            title: event.title ?? "Timer Complete",
            detail: "Countdown finished"
          )
        )
      }
    case .pomodoroBreakBegan:
      if settings.playsPomodoroBreakSound {
        soundPlayer.play(volume: settings.soundVolume)
      }
      if settings.showsPomodoroBreakTakeover {
        windowCoordinator.presentTimerTakeover(
          TimerTakeoverPresentation(
            id: event.timerID,
            title: event.title ?? "Break Time",
            detail: "Work interval finished"
          )
        )
      }
    }
  }

  private func rescheduleNotification() async {
    await notifications.cancelTimerNotifications(timerID: nil)
    guard let snapshot, snapshot.isRunning,
      let request = notificationRequest(for: snapshot)
    else { return }

    var authorization = await notifications.authorizationState()
    if authorization == .notDetermined {
      do {
        let granted = try await notifications.requestAuthorization()
        authorization = granted ? .authorized : .denied
      } catch {
        return
      }
    }
    guard
      authorization == .authorized || authorization == .provisional
        || authorization == .ephemeral
    else { return }
    try? await notifications.scheduleTimerNotification(request)
  }

  private func notificationRequest(for snapshot: TimerSnapshot) -> TimerNotificationRequest? {
    let timer = snapshot.timer
    let duration: Duration
    let kind: TimerNotificationKind
    let title: String
    let body: String
    let playsSound: Bool
    switch (timer.kind, timer.phase) {
    case (.countdown, .primary) where settings.showsCountdownNotifications:
      guard let workDuration = timer.workDuration else { return nil }
      duration = workDuration
      kind = .countdownCompleted
      title = timer.title ?? "Timer Complete"
      body = "Countdown finished"
      playsSound = settings.playsCountdownSound
    case (.pomodoro, .work) where settings.showsPomodoroBreakNotifications:
      guard let workDuration = timer.workDuration else { return nil }
      duration = workDuration
      kind = .pomodoroBreakBegan
      title = timer.title ?? "Break Time"
      body = "Work interval finished"
      playsSound = settings.playsPomodoroBreakSound
    default:
      return nil
    }
    let remaining = max(0, TimerDuration.seconds(duration - snapshot.elapsedInPhase))
    guard remaining > 0 else { return nil }
    return TimerNotificationRequest(
      timerID: timer.id,
      kind: kind,
      fireDate: wallClock.now().addingTimeInterval(remaining),
      title: title,
      body: body,
      playsSound: playsSound
    )
  }
}
