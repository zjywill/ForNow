import ForNowEditor
import Foundation

protocol EditorSettingsStoring: Sendable {
  func load() async -> EditorSettings
  func save(_ settings: EditorSettings) async throws
}

protocol ExpandedLinkStateStoring: Sendable {
  func load() async -> [UUID: Set<LinkIdentity>]
  func save(_ state: [UUID: Set<LinkIdentity>]) async throws
}

actor UserDefaultsEditorSettingsStore: EditorSettingsStoring {
  private struct StoredSettings: Codable {
    static let currentVersion = 4

    let version: Int
    let settings: EditorSettings
  }

  private enum Key {
    static let settings = "app.fornow.editor.settings.v1"
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

  func load() -> EditorSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let stored = try? decoder.decode(StoredSettings.self, from: data),
      (1...StoredSettings.currentVersion).contains(stored.version)
    else {
      return EditorSettings()
    }
    return stored.settings
  }

  func save(_ settings: EditorSettings) throws {
    let stored = StoredSettings(version: StoredSettings.currentVersion, settings: settings)
    defaults.set(try encoder.encode(stored), forKey: Key.settings)
  }
}

actor UserDefaultsExpandedLinkStateStore: ExpandedLinkStateStoring {
  private struct NoteState: Codable {
    let noteID: UUID
    let identities: [LinkIdentity]
  }

  private struct StoredState: Codable {
    static let currentVersion = 1

    let version: Int
    let notes: [NoteState]
  }

  private enum Key {
    static let state = "app.fornow.editor.expanded-links.v1"
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

  func load() -> [UUID: Set<LinkIdentity>] {
    guard
      let data = defaults.data(forKey: Key.state),
      let stored = try? decoder.decode(StoredState.self, from: data),
      stored.version == StoredState.currentVersion
    else {
      return [:]
    }

    return stored.notes.reduce(into: [:]) { result, note in
      let validIdentities = note.identities.filter(Self.isValid)
      if !validIdentities.isEmpty {
        result[note.noteID] = Set(validIdentities)
      }
    }
  }

  func save(_ state: [UUID: Set<LinkIdentity>]) throws {
    let notes = state.compactMap { noteID, identities -> NoteState? in
      guard !identities.isEmpty else { return nil }
      return NoteState(
        noteID: noteID,
        identities: identities.sorted { lhs, rhs in
          if lhs.urlDigest == rhs.urlDigest {
            return lhs.occurrenceIndex < rhs.occurrenceIndex
          }
          return lhs.urlDigest < rhs.urlDigest
        }
      )
    }.sorted { $0.noteID.uuidString < $1.noteID.uuidString }
    defaults.set(
      try encoder.encode(StoredState(version: StoredState.currentVersion, notes: notes)),
      forKey: Key.state
    )
  }

  private static func isValid(_ identity: LinkIdentity) -> Bool {
    identity.occurrenceIndex > 0
      && identity.urlDigest.count == 64
      && identity.urlDigest.unicodeScalars.allSatisfy { scalar in
        (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
      }
  }
}

actor InMemoryEditorSettingsStore: EditorSettingsStoring {
  private var settings: EditorSettings

  init(settings: EditorSettings = EditorSettings()) {
    self.settings = settings
  }

  func load() -> EditorSettings {
    settings
  }

  func save(_ settings: EditorSettings) {
    self.settings = settings
  }
}

actor InMemoryExpandedLinkStateStore: ExpandedLinkStateStoring {
  private var state: [UUID: Set<LinkIdentity>]

  init(state: [UUID: Set<LinkIdentity>] = [:]) {
    self.state = state
  }

  func load() -> [UUID: Set<LinkIdentity>] {
    state
  }

  func save(_ state: [UUID: Set<LinkIdentity>]) {
    self.state = state
  }
}
