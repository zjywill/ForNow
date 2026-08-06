import ForNowModes
import Foundation

protocol ModeSettingsStoring: Sendable {
  func load() async -> ModeSettings
  func save(_ settings: ModeSettings) async throws
}

actor UserDefaultsModeSettingsStore: ModeSettingsStoring {
  private enum Key {
    static let settings = "app.fornow.mode.settings.v1"
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

  func load() -> ModeSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let settings = try? decoder.decode(ModeSettings.self, from: data),
      (try? ModeAliasRegistry(settings: settings)) != nil
    else {
      return ModeSettings()
    }
    return settings
  }

  func save(_ settings: ModeSettings) throws {
    _ = try ModeAliasRegistry(settings: settings)
    defaults.set(try encoder.encode(settings), forKey: Key.settings)
  }
}

actor InMemoryModeSettingsStore: ModeSettingsStoring {
  private var settings: ModeSettings

  init(settings: ModeSettings = ModeSettings()) {
    self.settings = settings
  }

  func load() -> ModeSettings {
    settings
  }

  func save(_ settings: ModeSettings) throws {
    _ = try ModeAliasRegistry(settings: settings)
    self.settings = settings
  }
}
