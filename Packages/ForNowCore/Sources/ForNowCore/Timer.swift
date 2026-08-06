import Foundation

public typealias TimerID = UUID
public typealias NoteID = UUID

public enum TimerKind: String, Codable, CaseIterable, Sendable {
  case stopwatch
  case countdown
  case pomodoro
}

public enum TimerPhase: String, Codable, CaseIterable, Sendable {
  case primary
  case work
  case rest
}

public enum TimerState: String, Codable, CaseIterable, Sendable {
  case idle
  case running
  case paused
  case completed
  case cancelled
}

public struct NoteTimer: Sendable, Equatable, Identifiable {
  public let id: TimerID
  public let noteID: NoteID
  public var kind: TimerKind
  public var title: String?
  public var phase: TimerPhase
  public var state: TimerState
  public var startedAt: Date?
  public var accumulated: Duration
  public var workDuration: Duration?
  public var restDuration: Duration?

  public init(
    id: TimerID,
    noteID: NoteID,
    kind: TimerKind,
    title: String? = nil,
    phase: TimerPhase,
    state: TimerState,
    startedAt: Date? = nil,
    accumulated: Duration = .zero,
    workDuration: Duration? = nil,
    restDuration: Duration? = nil
  ) {
    self.id = id
    self.noteID = noteID
    self.kind = kind
    self.title = title
    self.phase = phase
    self.state = state
    self.startedAt = startedAt
    self.accumulated = accumulated
    self.workDuration = workDuration
    self.restDuration = restDuration
  }
}

public enum TimerCommand: Sendable, Equatable {
  case startStopwatch(title: String?)
  case startCountdown(duration: Duration, title: String?)
  case startPomodoro(work: Duration, rest: Duration, title: String?)
  case pauseOrResume
  case restart
  case stop

  public var startsNewTimer: Bool {
    switch self {
    case .startStopwatch, .startCountdown, .startPomodoro:
      true
    case .pauseOrResume, .restart, .stop:
      false
    }
  }
}

public enum TimerEventKind: String, Sendable, Equatable {
  case countdownCompleted
  case pomodoroBreakBegan
}

public struct TimerEvent: Sendable, Equatable {
  public let kind: TimerEventKind
  public let timerID: TimerID
  public let title: String?

  public init(kind: TimerEventKind, timerID: TimerID, title: String?) {
    self.kind = kind
    self.timerID = timerID
    self.title = title
  }
}

public enum TimerSettingsError: Error, Equatable, Sendable {
  case unsupportedVersion(Int)
  case invalidSoundVolume(Int)
}

public struct TimerSettings: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version: Int
  public var pausesOnQuit: Bool
  public var showsTimeInMenuBar: Bool
  public var showsCountdownNotifications: Bool
  public var showsCountdownTakeover: Bool
  public var playsCountdownSound: Bool
  public var showsPomodoroBreakNotifications: Bool
  public var showsPomodoroBreakTakeover: Bool
  public var playsPomodoroBreakSound: Bool
  public var soundVolume: Int

  public init(
    version: Int = currentVersion,
    pausesOnQuit: Bool = false,
    showsTimeInMenuBar: Bool = true,
    showsCountdownNotifications: Bool = false,
    showsCountdownTakeover: Bool = false,
    playsCountdownSound: Bool = true,
    showsPomodoroBreakNotifications: Bool = false,
    showsPomodoroBreakTakeover: Bool = false,
    playsPomodoroBreakSound: Bool = true,
    soundVolume: Int = 70
  ) {
    self.version = version
    self.pausesOnQuit = pausesOnQuit
    self.showsTimeInMenuBar = showsTimeInMenuBar
    self.showsCountdownNotifications = showsCountdownNotifications
    self.showsCountdownTakeover = showsCountdownTakeover
    self.playsCountdownSound = playsCountdownSound
    self.showsPomodoroBreakNotifications = showsPomodoroBreakNotifications
    self.showsPomodoroBreakTakeover = showsPomodoroBreakTakeover
    self.playsPomodoroBreakSound = playsPomodoroBreakSound
    self.soundVolume = soundVolume
  }

  public func validated() throws -> TimerSettings {
    guard version == Self.currentVersion else {
      throw TimerSettingsError.unsupportedVersion(version)
    }
    guard (0...100).contains(soundVolume) else {
      throw TimerSettingsError.invalidSoundVolume(soundVolume)
    }
    return self
  }
}

public struct TimerSnapshot: Sendable, Equatable {
  public let timer: NoteTimer
  public let elapsedInPhase: Duration
  public let displayText: String
  public let menuBarText: String
  public let accessibilityLabel: String

  public init(timer: NoteTimer, elapsedInPhase: Duration) {
    self.timer = timer
    self.elapsedInPhase = elapsedInPhase
    displayText = TimerDisplayFormatter.editorText(for: timer, elapsed: elapsedInPhase)
    menuBarText = TimerDisplayFormatter.menuBarText(for: timer, elapsed: elapsedInPhase)
    accessibilityLabel = TimerDisplayFormatter.accessibilityLabel(
      for: timer,
      elapsed: elapsedInPhase
    )
  }

  public var isRunning: Bool { timer.state == .running }
  public var isPaused: Bool { timer.state == .paused }
  public var isExternallyVisible: Bool { isRunning || isPaused }
}

public enum TimerDuration {
  public static func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }

  public static func duration(seconds: Double) -> Duration {
    guard seconds.isFinite, seconds > 0 else {
      return seconds == 0 ? .zero : .zero
    }
    let wholeSeconds = seconds.rounded(.towardZero)
    let fraction = seconds - wholeSeconds
    return Duration(
      secondsComponent: Int64(wholeSeconds),
      attosecondsComponent: Int64((fraction * 1_000_000_000_000_000_000).rounded())
    )
  }

  public static func clampedNonnegative(_ duration: Duration) -> Duration {
    duration < .zero ? .zero : duration
  }
}

public enum TimerDisplayFormatter {
  public static func editorText(for timer: NoteTimer, elapsed: Duration) -> String {
    let time = formattedTime(for: timer, elapsed: elapsed)
    switch timer.state {
    case .paused:
      return "Paused \(time)"
    case .completed:
      return "Completed \(time)"
    case .cancelled:
      return "Stopped \(time)"
    case .idle, .running:
      break
    }
    switch timer.phase {
    case .work where timer.kind == .pomodoro:
      return "Work \(time)"
    case .rest:
      return "Break \(time)"
    case .primary, .work:
      return time
    }
  }

  public static func menuBarText(for timer: NoteTimer, elapsed: Duration) -> String {
    let time = formattedTime(for: timer, elapsed: elapsed)
    switch timer.phase {
    case .work where timer.kind == .pomodoro:
      return "W \(time)"
    case .rest:
      return "B \(time)"
    case .primary, .work:
      return time
    }
  }

  public static func accessibilityLabel(for timer: NoteTimer, elapsed: Duration) -> String {
    let title = timer.title.map { " \($0)." } ?? ""
    let state: String
    switch timer.state {
    case .idle: state = "idle"
    case .running: state = "running"
    case .paused: state = "paused"
    case .completed: state = "completed"
    case .cancelled: state = "stopped"
    }
    let phase: String
    switch timer.phase {
    case .primary: phase = timer.kind == .stopwatch ? "stopwatch" : "countdown"
    case .work: phase = "work"
    case .rest: phase = "break"
    }
    return
      "Timer.\(title) \(phase.capitalized) \(state). \(formattedTime(for: timer, elapsed: elapsed))."
  }

  private static func formattedTime(for timer: NoteTimer, elapsed: Duration) -> String {
    let elapsedSeconds = max(0, TimerDuration.seconds(elapsed))
    let displayedSeconds: Int
    switch timer.kind {
    case .stopwatch:
      displayedSeconds = Int(elapsedSeconds.rounded(.down))
    case .countdown, .pomodoro:
      let duration = timer.phase == .rest ? timer.restDuration : timer.workDuration
      let remaining = max(0, TimerDuration.seconds(duration ?? .zero) - elapsedSeconds)
      displayedSeconds = Int(remaining.rounded(.up))
    }
    let hours = displayedSeconds / 3_600
    let minutes = (displayedSeconds % 3_600) / 60
    let seconds = displayedSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
  }
}
