import Carbon.HIToolbox
import ForNowWindowing
import Foundation
import SwiftUI

enum QuickAction: String, CaseIterable, Codable, Identifiable, Sendable {
  case previousNote
  case nextNote
  case newestNote
  case newNote
  case promoteNote
  case deleteNote
  case searchNotes
  case togglePin
  case increaseTextSize
  case decreaseTextSize

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .previousNote:
      "Previous Note"
    case .nextNote:
      "Next Note"
    case .newestNote:
      "Newest Note"
    case .newNote:
      "New Note"
    case .promoteNote:
      "Promote Note"
    case .deleteNote:
      "Delete Note"
    case .searchNotes:
      "Search Notes"
    case .togglePin:
      "Toggle Pin"
    case .increaseTextSize:
      "Increase Text Size"
    case .decreaseTextSize:
      "Decrease Text Size"
    }
  }
}

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
  let rawValue: UInt8

  init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  static let command = ShortcutModifiers(rawValue: 1 << 0)
  static let control = ShortcutModifiers(rawValue: 1 << 1)
  static let option = ShortcutModifiers(rawValue: 1 << 2)
  static let shift = ShortcutModifiers(rawValue: 1 << 3)

  var eventModifiers: SwiftUI.EventModifiers {
    var result: SwiftUI.EventModifiers = []
    if contains(.command) { result.insert(.command) }
    if contains(.control) { result.insert(.control) }
    if contains(.option) { result.insert(.option) }
    if contains(.shift) { result.insert(.shift) }
    return result
  }

  var displayName: String {
    var symbols = ""
    if contains(.control) { symbols += "⌃" }
    if contains(.option) { symbols += "⌥" }
    if contains(.shift) { symbols += "⇧" }
    if contains(.command) { symbols += "⌘" }
    return symbols
  }

  var hasCommandControlOrOption: Bool {
    !intersection([.command, .control, .option]).isEmpty
  }
}

struct CommandShortcut: Codable, Equatable, Hashable, Sendable {
  var key: String
  var modifiers: ShortcutModifiers

  init(_ key: String, modifiers: ShortcutModifiers) {
    self.key = key
    self.modifiers = modifiers
  }

  var normalizedKey: String {
    key
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
  }

  var displayName: String {
    modifiers.displayName + normalizedKey.uppercased()
  }

  var keyEquivalent: KeyEquivalent {
    KeyEquivalent(normalizedKey.first ?? "?")
  }
}

struct QuickActionSettings: Codable, Equatable, Sendable {
  static let currentVersion = 1
  static let defaults: [QuickAction: CommandShortcut] = [
    .previousNote: CommandShortcut("[", modifiers: .command),
    .nextNote: CommandShortcut("]", modifiers: .command),
    .newestNote: CommandShortcut("1", modifiers: .command),
    .newNote: CommandShortcut("n", modifiers: .command),
    .promoteNote: CommandShortcut("1", modifiers: [.command, .shift]),
    .deleteNote: CommandShortcut("d", modifiers: .command),
    .searchNotes: CommandShortcut("f", modifiers: .command),
    .togglePin: CommandShortcut("p", modifiers: .command),
    .increaseTextSize: CommandShortcut("+", modifiers: .command),
    .decreaseTextSize: CommandShortcut("-", modifiers: .command),
  ]

  var version: Int
  var bindings: [QuickAction: CommandShortcut]

  init(
    version: Int = currentVersion,
    bindings: [QuickAction: CommandShortcut] = defaults
  ) {
    self.version = version
    self.bindings = bindings
  }

  subscript(_ action: QuickAction) -> CommandShortcut {
    get { bindings[action] ?? Self.defaults[action]! }
    set { bindings[action] = newValue }
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case bindings
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
    let decoded =
      try values.decodeIfPresent([QuickAction: CommandShortcut].self, forKey: .bindings) ?? [:]
    bindings = Self.defaults.merging(decoded) { _, decoded in decoded }
  }
}

enum QuickActionSettingsError: LocalizedError, Equatable, Sendable {
  case unsupportedVersion(Int)
  case invalidKey(QuickAction)
  case missingModifier(QuickAction)
  case duplicate(QuickAction, QuickAction)
  case reserved(QuickAction, String)
  case conflictsWithGlobalInvocation(QuickAction)

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version):
      "Shortcut settings version \(version) is not supported."
    case .invalidKey(let action):
      "\(action.displayName) needs exactly one visible key."
    case .missingModifier(let action):
      "\(action.displayName) needs Command, Control, or Option."
    case .duplicate(let first, let second):
      "\(first.displayName) conflicts with \(second.displayName)."
    case .reserved(let action, let binding):
      "\(binding) is reserved by macOS or an editor command and cannot be used for \(action.displayName)."
    case .conflictsWithGlobalInvocation(let action):
      "\(action.displayName) conflicts with the global invocation shortcut."
    }
  }
}

struct QuickActionSettingsValidator {
  private struct Identity: Hashable {
    let key: String
    let modifiers: ShortcutModifiers
  }

  private static let reserved: Set<Identity> = [
    identity("q", .command),
    identity("h", .command),
    identity("m", .command),
    identity("w", .command),
    identity(",", .command),
    identity("o", .command),
    identity("a", .command),
    identity("c", .command),
    identity("v", .command),
    identity("x", .command),
    identity("z", .command),
    identity("z", [.command, .shift]),
    identity("v", [.command, .shift]),
    identity("f", [.command, .shift]),
    identity("/", .command),
  ]

  func validate(
    _ settings: QuickActionSettings,
    globalInvocation: GlobalShortcutCandidate? = nil
  ) throws {
    guard settings.version == QuickActionSettings.currentVersion else {
      throw QuickActionSettingsError.unsupportedVersion(settings.version)
    }

    var actionsByIdentity: [Identity: QuickAction] = [:]
    for action in QuickAction.allCases {
      let binding = settings[action]
      let key = binding.normalizedKey
      guard key.count == 1,
        let scalar = key.unicodeScalars.first,
        !scalar.properties.isWhitespace,
        scalar.properties.generalCategory != .control
      else {
        throw QuickActionSettingsError.invalidKey(action)
      }
      guard binding.modifiers.hasCommandControlOrOption else {
        throw QuickActionSettingsError.missingModifier(action)
      }
      let identity = Identity(key: key, modifiers: binding.modifiers)
      if let existing = actionsByIdentity[identity] {
        throw QuickActionSettingsError.duplicate(existing, action)
      }
      guard !Self.reserved.contains(identity) else {
        throw QuickActionSettingsError.reserved(action, binding.displayName)
      }
      if let globalInvocation,
        Self.identity(for: globalInvocation) == identity
      {
        throw QuickActionSettingsError.conflictsWithGlobalInvocation(action)
      }
      actionsByIdentity[identity] = action
    }
  }

  private static func identity(_ key: String, _ modifiers: ShortcutModifiers) -> Identity {
    Identity(key: key, modifiers: modifiers)
  }

  private static func identity(for candidate: GlobalShortcutCandidate) -> Identity? {
    guard let key = keyEquivalent(for: candidate.keyCode) else { return nil }
    var modifiers: ShortcutModifiers = []
    if candidate.modifiers.contains(.command) { modifiers.insert(.command) }
    if candidate.modifiers.contains(.control) { modifiers.insert(.control) }
    if candidate.modifiers.contains(.option) { modifiers.insert(.option) }
    if candidate.modifiers.contains(.shift) { modifiers.insert(.shift) }
    return Identity(key: key, modifiers: modifiers)
  }

  private static func keyEquivalent(for keyCode: Int) -> String? {
    let pairs: [(Int, String)] = [
      (kVK_ANSI_A, "a"), (kVK_ANSI_B, "b"), (kVK_ANSI_C, "c"),
      (kVK_ANSI_D, "d"), (kVK_ANSI_E, "e"), (kVK_ANSI_F, "f"),
      (kVK_ANSI_G, "g"), (kVK_ANSI_H, "h"), (kVK_ANSI_I, "i"),
      (kVK_ANSI_J, "j"), (kVK_ANSI_K, "k"), (kVK_ANSI_L, "l"),
      (kVK_ANSI_M, "m"), (kVK_ANSI_N, "n"), (kVK_ANSI_O, "o"),
      (kVK_ANSI_P, "p"), (kVK_ANSI_Q, "q"), (kVK_ANSI_R, "r"),
      (kVK_ANSI_S, "s"), (kVK_ANSI_T, "t"), (kVK_ANSI_U, "u"),
      (kVK_ANSI_V, "v"), (kVK_ANSI_W, "w"), (kVK_ANSI_X, "x"),
      (kVK_ANSI_Y, "y"), (kVK_ANSI_Z, "z"), (kVK_ANSI_0, "0"),
      (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
      (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"),
      (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
      (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"),
      (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "+"),
      (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."),
      (kVK_ANSI_Slash, "/"), (kVK_ANSI_Semicolon, ";"),
      (kVK_ANSI_Quote, "'"), (kVK_ANSI_Backslash, "\\"),
      (kVK_ANSI_Grave, "`"),
    ]
    return pairs.first(where: { $0.0 == keyCode })?.1
  }
}

protocol QuickActionSettingsStoring: Sendable {
  func load() async -> QuickActionSettings
  func save(_ settings: QuickActionSettings) async throws
}

actor UserDefaultsQuickActionSettingsStore: QuickActionSettingsStoring {
  private struct StoredSettings: Codable {
    static let currentVersion = 1

    let version: Int
    let settings: QuickActionSettings
  }

  private enum Key {
    static let settings = "app.fornow.quick-action.settings.v1"
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

  func load() -> QuickActionSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let stored = try? decoder.decode(StoredSettings.self, from: data),
      stored.version == StoredSettings.currentVersion,
      (try? QuickActionSettingsValidator().validate(stored.settings)) != nil
    else {
      return QuickActionSettings()
    }
    return stored.settings
  }

  func save(_ settings: QuickActionSettings) throws {
    try QuickActionSettingsValidator().validate(settings)
    defaults.set(
      try encoder.encode(
        StoredSettings(version: StoredSettings.currentVersion, settings: settings)),
      forKey: Key.settings
    )
  }
}

actor InMemoryQuickActionSettingsStore: QuickActionSettingsStoring {
  private var settings: QuickActionSettings

  init(settings: QuickActionSettings = QuickActionSettings()) {
    self.settings = settings
  }

  func load() -> QuickActionSettings {
    settings
  }

  func save(_ settings: QuickActionSettings) throws {
    try QuickActionSettingsValidator().validate(settings)
    self.settings = settings
  }
}
