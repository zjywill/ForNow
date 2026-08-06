import Foundation

public enum ReopenNewNotePolicy: String, CaseIterable, Codable, Sendable {
  case always
  case afterThreeMinutes
  case afterThirtyMinutes
  case afterOneHour
  case afterOneDay
  case never

  public var threshold: TimeInterval? {
    switch self {
    case .always:
      0
    case .afterThreeMinutes:
      3 * 60
    case .afterThirtyMinutes:
      30 * 60
    case .afterOneHour:
      60 * 60
    case .afterOneDay:
      24 * 60 * 60
    case .never:
      nil
    }
  }
}

public struct LifecycleSettings: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version: Int
  public var createsNewNoteOnLaunch: Bool
  public var reopenNewNotePolicy: ReopenNewNotePolicy
  public var showsNoteCount: Bool
  public var suppressesDeleteWarning: Bool

  public init(
    version: Int = currentVersion,
    createsNewNoteOnLaunch: Bool = true,
    reopenNewNotePolicy: ReopenNewNotePolicy = .never,
    showsNoteCount: Bool = false,
    suppressesDeleteWarning: Bool = false
  ) {
    self.version = version
    self.createsNewNoteOnLaunch = createsNewNoteOnLaunch
    self.reopenNewNotePolicy = reopenNewNotePolicy
    self.showsNoteCount = showsNoteCount
    self.suppressesDeleteWarning = suppressesDeleteWarning
  }
}

public enum NoteOpeningContext: Equatable, Sendable {
  case launch
  case reopen
}

public struct ResumeNotePolicy: Sendable {
  public init() {}

  public func shouldCreateNewNote(
    for context: NoteOpeningContext,
    settings: LifecycleSettings,
    now: Date,
    lastWindowClosedAt: Date?
  ) -> Bool {
    switch context {
    case .launch:
      return settings.createsNewNoteOnLaunch
    case .reopen:
      guard let threshold = settings.reopenNewNotePolicy.threshold else { return false }
      guard threshold > 0 else { return true }
      guard let lastWindowClosedAt else { return false }
      return now.timeIntervalSince(lastWindowClosedAt) >= threshold
    }
  }
}

public protocol LifecycleSettingsStoring: Sendable {
  func load() async -> LifecycleSettings
  func save(_ settings: LifecycleSettings) async throws
  func lastWindowClosedAt() async -> Date?
  func recordWindowClosed(at date: Date) async
}

public actor InMemoryLifecycleSettingsStore: LifecycleSettingsStoring {
  private var settings: LifecycleSettings
  private var closeDate: Date?

  public init(
    settings: LifecycleSettings = LifecycleSettings(),
    lastWindowClosedAt: Date? = nil
  ) {
    self.settings = settings
    closeDate = lastWindowClosedAt
  }

  public func load() -> LifecycleSettings {
    settings
  }

  public func save(_ settings: LifecycleSettings) {
    self.settings = settings
  }

  public func lastWindowClosedAt() -> Date? {
    closeDate
  }

  public func recordWindowClosed(at date: Date) {
    closeDate = date
  }
}
