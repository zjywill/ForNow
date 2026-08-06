import ForNowCore
import Foundation

actor UserDefaultsLifecycleSettingsStore: LifecycleSettingsStoring {
  private enum Key {
    static let settings = "app.fornow.lifecycle.settings.v1"
    static let lastWindowClosedAt = "app.fornow.lifecycle.lastWindowClosedAt"
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

  func load() -> LifecycleSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let settings = try? decoder.decode(LifecycleSettings.self, from: data),
      (1...LifecycleSettings.currentVersion).contains(settings.version)
    else {
      return LifecycleSettings()
    }
    let migrated = settings.migratedToCurrentVersion()
    if migrated != settings, let data = try? encoder.encode(migrated) {
      defaults.set(data, forKey: Key.settings)
    }
    return migrated
  }

  func save(_ settings: LifecycleSettings) throws {
    let data = try encoder.encode(settings.migratedToCurrentVersion())
    defaults.set(data, forKey: Key.settings)
  }

  func lastWindowClosedAt() -> Date? {
    defaults.object(forKey: Key.lastWindowClosedAt) as? Date
  }

  func recordWindowClosed(at date: Date) {
    defaults.set(date, forKey: Key.lastWindowClosedAt)
  }
}
