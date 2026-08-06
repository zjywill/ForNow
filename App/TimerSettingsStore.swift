import ForNowCore
import Foundation

protocol TimerSettingsStoring: Sendable {
  func load() async -> TimerSettings
  func save(_ settings: TimerSettings) async throws
}

actor UserDefaultsTimerSettingsStore: TimerSettingsStoring {
  private struct StoredSettings: Codable {
    static let currentVersion = 1

    let version: Int
    let settings: TimerSettings
  }

  private enum Key {
    static let settings = "app.fornow.timer.settings.v1"
  }

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(suiteName: String? = nil) {
    if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
      self.defaults = defaults
    } else {
      defaults = .standard
    }
  }

  func load() -> TimerSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let stored = try? decoder.decode(StoredSettings.self, from: data),
      stored.version == StoredSettings.currentVersion,
      (try? stored.settings.validated()) != nil
    else {
      return TimerSettings()
    }
    return stored.settings
  }

  func save(_ settings: TimerSettings) throws {
    let settings = try settings.validated()
    defaults.set(
      try encoder.encode(
        StoredSettings(version: StoredSettings.currentVersion, settings: settings)),
      forKey: Key.settings
    )
  }
}

actor InMemoryTimerSettingsStore: TimerSettingsStoring {
  private var settings: TimerSettings

  init(settings: TimerSettings = TimerSettings()) {
    self.settings = settings
  }

  func load() -> TimerSettings {
    settings
  }

  func save(_ settings: TimerSettings) throws {
    self.settings = try settings.validated()
  }
}
