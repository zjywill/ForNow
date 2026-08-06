import ForNowDesign
import Foundation

protocol AppearanceSettingsStoring: Sendable {
  func load() async -> AppearanceSettings
  func save(_ settings: AppearanceSettings) async throws
}

actor UserDefaultsAppearanceSettingsStore: AppearanceSettingsStoring {
  private struct StoredSettings: Codable {
    static let currentVersion = 1

    let version: Int
    let settings: AppearanceSettings
  }

  private enum Key {
    static let settings = "app.fornow.appearance.settings.v1"
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

  func load() -> AppearanceSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let stored = try? decoder.decode(StoredSettings.self, from: data),
      stored.version == StoredSettings.currentVersion,
      stored.settings.version == AppearanceSettings.currentVersion
    else {
      return AppearanceSettings()
    }
    var settings = stored.settings
    settings.normalize()
    return settings
  }

  func save(_ settings: AppearanceSettings) throws {
    var settings = settings
    settings.normalize()
    let stored = StoredSettings(version: StoredSettings.currentVersion, settings: settings)
    defaults.set(try encoder.encode(stored), forKey: Key.settings)
  }
}

actor InMemoryAppearanceSettingsStore: AppearanceSettingsStoring {
  private var settings: AppearanceSettings

  init(settings: AppearanceSettings = AppearanceSettings()) {
    self.settings = settings
  }

  func load() -> AppearanceSettings {
    settings
  }

  func save(_ settings: AppearanceSettings) {
    var settings = settings
    settings.normalize()
    self.settings = settings
  }
}
