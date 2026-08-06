import ForNowIntegrations
import Foundation

protocol OCRSettingsStoring: Sendable {
  func load() async -> OCRSettings
  func save(_ settings: OCRSettings) async throws
}

actor UserDefaultsOCRSettingsStore: OCRSettingsStoring {
  private struct StoredSettings: Codable {
    static let currentVersion = 1

    let version: Int
    let settings: OCRSettings
  }

  private enum Key {
    static let settings = "app.fornow.ocr.settings.v1"
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

  func load() -> OCRSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let stored = try? decoder.decode(StoredSettings.self, from: data),
      stored.version == StoredSettings.currentVersion
    else {
      return OCRSettings()
    }
    return stored.settings
  }

  func save(_ settings: OCRSettings) throws {
    defaults.set(
      try encoder.encode(
        StoredSettings(version: StoredSettings.currentVersion, settings: settings)
      ),
      forKey: Key.settings
    )
  }
}

actor InMemoryOCRSettingsStore: OCRSettingsStoring {
  private var settings: OCRSettings

  init(settings: OCRSettings = OCRSettings()) {
    self.settings = settings
  }

  func load() -> OCRSettings {
    settings
  }

  func save(_ settings: OCRSettings) {
    self.settings = settings
  }
}
