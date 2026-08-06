import ForNowCore
import ForNowIntegrations
import Foundation

protocol ExportSettingsStoring: Sendable {
  func load() async -> ExportSettings
  func save(_ settings: ExportSettings) async throws
}

actor UserDefaultsExportSettingsStore: ExportSettingsStoring {
  private struct StoredSettings: Codable {
    static let currentVersion = 1

    let version: Int
    let settings: ExportSettings
  }

  private enum Key {
    static let settings = "app.fornow.export.settings.v1"
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

  func load() -> ExportSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let stored = try? decoder.decode(StoredSettings.self, from: data),
      stored.version == StoredSettings.currentVersion,
      stored.settings.version == ExportSettings.currentVersion
    else {
      return ExportSettings()
    }
    var settings = stored.settings
    settings.normalize()
    guard Self.isValidActiveConfiguration(settings) else {
      return ExportSettings()
    }
    return settings
  }

  func save(_ settings: ExportSettings) throws {
    var settings = settings
    settings.normalize()
    guard settings.version == ExportSettings.currentVersion else {
      throw ExportError.invalidTemplate("Only export settings version 1 is supported.")
    }
    if settings.quickDestination == .customURL {
      _ = try ValidatedCustomURLTemplate(source: settings.customURLTemplate)
    }
    let stored = StoredSettings(version: StoredSettings.currentVersion, settings: settings)
    defaults.set(try encoder.encode(stored), forKey: Key.settings)
  }

  private static func isValidActiveConfiguration(_ settings: ExportSettings) -> Bool {
    guard settings.quickDestination == .customURL else { return true }
    return (try? ValidatedCustomURLTemplate(source: settings.customURLTemplate)) != nil
  }
}

actor InMemoryExportSettingsStore: ExportSettingsStoring {
  private var settings: ExportSettings
  private let saveError: (any Error)?

  init(settings: ExportSettings = ExportSettings(), saveError: (any Error)? = nil) {
    self.settings = settings
    self.saveError = saveError
  }

  func load() -> ExportSettings {
    settings
  }

  func save(_ settings: ExportSettings) throws {
    if let saveError { throw saveError }
    self.settings = settings
  }
}
