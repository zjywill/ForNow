import ForNowModes
import Foundation

protocol MathSettingsStoring: Sendable {
  func load() async -> MathSettings
  func save(_ settings: MathSettings) async throws
}

actor UserDefaultsMathSettingsStore: MathSettingsStoring {
  private struct StoredSettings: Codable {
    static let currentVersion = 2

    let version: Int
    let settings: MathSettings
  }

  private enum Key {
    static let settings = "app.fornow.math.settings.v1"
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

  func load() -> MathSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let stored = try? decoder.decode(StoredSettings.self, from: data),
      (1...StoredSettings.currentVersion).contains(stored.version),
      (try? stored.settings.validated()) != nil
    else {
      return MathSettings()
    }
    if stored.version < StoredSettings.currentVersion {
      try? persist(stored.settings)
    }
    return stored.settings
  }

  func save(_ settings: MathSettings) throws {
    _ = try settings.validated()
    try persist(settings)
  }

  private func persist(_ settings: MathSettings) throws {
    defaults.set(
      try encoder.encode(
        StoredSettings(version: StoredSettings.currentVersion, settings: settings)
      ),
      forKey: Key.settings
    )
  }
}

actor InMemoryMathSettingsStore: MathSettingsStoring {
  private var settings: MathSettings

  init(settings: MathSettings = MathSettings()) {
    self.settings = settings
  }

  func load() -> MathSettings {
    settings
  }

  func save(_ settings: MathSettings) throws {
    self.settings = try settings.validated()
  }
}
