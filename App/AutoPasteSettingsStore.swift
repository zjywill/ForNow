import ForNowModes
import Foundation

protocol AutoPasteSettingsStoring: Sendable {
  func load() async -> AutoPasteSettings
  func save(_ settings: AutoPasteSettings) async throws
}

actor UserDefaultsAutoPasteSettingsStore: AutoPasteSettingsStoring {
  private struct StoredSettings: Codable {
    static let currentVersion = 1

    let version: Int
    let settings: AutoPasteSettings
  }

  private enum Key {
    static let settings = "app.fornow.autopaste.settings.v1"
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

  func load() -> AutoPasteSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let stored = try? decoder.decode(StoredSettings.self, from: data),
      stored.version == StoredSettings.currentVersion,
      (try? stored.settings.validated()) != nil
    else {
      return AutoPasteSettings()
    }
    return stored.settings
  }

  func save(_ settings: AutoPasteSettings) throws {
    let settings = try settings.validated()
    defaults.set(
      try encoder.encode(
        StoredSettings(version: StoredSettings.currentVersion, settings: settings)
      ),
      forKey: Key.settings
    )
  }
}

actor InMemoryAutoPasteSettingsStore: AutoPasteSettingsStoring {
  private var settings: AutoPasteSettings

  init(settings: AutoPasteSettings = AutoPasteSettings()) {
    self.settings = settings
  }

  func load() -> AutoPasteSettings {
    settings
  }

  func save(_ settings: AutoPasteSettings) throws {
    self.settings = try settings.validated()
  }
}
