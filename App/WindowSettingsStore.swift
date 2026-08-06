import ForNowWindowing
import Foundation

protocol WindowSettingsStoring: Sendable {
  func load() async -> WindowConfiguration
  func save(_ configuration: WindowConfiguration) async throws
}

actor UserDefaultsWindowSettingsStore: WindowSettingsStoring {
  private struct StoredSettings: Codable {
    static let currentVersion = 1

    let version: Int
    let configuration: WindowConfiguration
  }

  private enum Key {
    static let settings = "app.fornow.window.settings.v1"
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

  func load() -> WindowConfiguration {
    guard
      let data = defaults.data(forKey: Key.settings),
      let stored = try? decoder.decode(StoredSettings.self, from: data),
      stored.version == StoredSettings.currentVersion
    else {
      return WindowConfiguration()
    }
    return stored.configuration
  }

  func save(_ configuration: WindowConfiguration) throws {
    let stored = StoredSettings(
      version: StoredSettings.currentVersion,
      configuration: configuration
    )
    defaults.set(try encoder.encode(stored), forKey: Key.settings)
  }
}

actor InMemoryWindowSettingsStore: WindowSettingsStoring {
  private var configuration: WindowConfiguration

  init(configuration: WindowConfiguration = WindowConfiguration()) {
    self.configuration = configuration
  }

  func load() -> WindowConfiguration {
    configuration
  }

  func save(_ configuration: WindowConfiguration) {
    self.configuration = configuration
  }
}
