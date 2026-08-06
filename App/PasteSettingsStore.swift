import ForNowEditor
import Foundation

protocol PasteSettingsStoring: Sendable {
  func load() async -> PasteSettings
  func save(_ settings: PasteSettings) async throws
}

actor UserDefaultsPasteSettingsStore: PasteSettingsStoring {
  private struct StoredSettings: Codable {
    static let currentVersion = 1

    let version: Int
    let settings: PasteSettings
  }

  private enum Key {
    static let settings = "app.fornow.paste.settings.v1"
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

  func load() -> PasteSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let stored = try? decoder.decode(StoredSettings.self, from: data),
      stored.version == StoredSettings.currentVersion
    else {
      return PasteSettings()
    }
    return stored.settings
  }

  func save(_ settings: PasteSettings) throws {
    let stored = StoredSettings(version: StoredSettings.currentVersion, settings: settings)
    defaults.set(try encoder.encode(stored), forKey: Key.settings)
  }
}

actor InMemoryPasteSettingsStore: PasteSettingsStoring {
  private var settings: PasteSettings

  init(settings: PasteSettings = PasteSettings()) {
    self.settings = settings
  }

  func load() -> PasteSettings {
    settings
  }

  func save(_ settings: PasteSettings) {
    self.settings = settings
  }
}
