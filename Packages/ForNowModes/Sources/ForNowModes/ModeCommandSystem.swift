import Foundation

public enum ModeID: String, CaseIterable, Codable, Sendable {
  case plain
  case list
  case math
  case sum
  case average
  case count
  case code
  case timer

  public var displayName: String {
    switch self {
    case .plain:
      "Plain"
    case .list:
      "List"
    case .math:
      "Math"
    case .sum:
      "Sum"
    case .average:
      "Average"
    case .count:
      "Count"
    case .code:
      "Code"
    case .timer:
      "Timer"
    }
  }
}

public struct ModeAliasDefinition: Codable, Equatable, Sendable {
  public var modeID: ModeID
  public var aliases: [String]
  public var mainAlias: String

  public init(modeID: ModeID, aliases: [String], mainAlias: String) {
    self.modeID = modeID
    self.aliases = aliases
    self.mainAlias = mainAlias
  }
}

public struct ModeSettings: Codable, Equatable, Sendable {
  public static let currentVersion = 1
  public static let builtInDefinitions = [
    ModeAliasDefinition(modeID: .plain, aliases: ["plain"], mainAlias: "plain"),
    ModeAliasDefinition(modeID: .list, aliases: ["list"], mainAlias: "list"),
    ModeAliasDefinition(modeID: .math, aliases: ["math"], mainAlias: "math"),
    ModeAliasDefinition(modeID: .sum, aliases: ["sum"], mainAlias: "sum"),
    ModeAliasDefinition(
      modeID: .average,
      aliases: ["avg", "average"],
      mainAlias: "avg"
    ),
    ModeAliasDefinition(modeID: .count, aliases: ["count"], mainAlias: "count"),
    ModeAliasDefinition(modeID: .code, aliases: ["code"], mainAlias: "code"),
    ModeAliasDefinition(modeID: .timer, aliases: ["timer"], mainAlias: "timer"),
  ]

  public var version: Int
  public var keywordInterpretationEnabled: Bool
  public var definitions: [ModeAliasDefinition]
  public var checklistTrigger: String

  public init(
    version: Int = currentVersion,
    keywordInterpretationEnabled: Bool = true,
    definitions: [ModeAliasDefinition] = builtInDefinitions,
    checklistTrigger: String = "/x"
  ) {
    self.version = version
    self.keywordInterpretationEnabled = keywordInterpretationEnabled
    self.definitions = definitions
    self.checklistTrigger = checklistTrigger
  }
}

public enum ModeAliasRegistryError: Error, Equatable, Sendable {
  case unsupportedSettingsVersion(Int)
  case missingMode(ModeID)
  case duplicateMode(ModeID)
  case emptyAlias(ModeID)
  case invalidAlias(ModeID, String)
  case duplicateAlias(ModeID, String)
  case aliasCollision(String, ModeID, ModeID)
  case invalidMainAlias(ModeID, String)
  case invalidChecklistTrigger(String)
}

extension ModeAliasRegistryError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .unsupportedSettingsVersion(let version):
      "Keyword settings version \(version) is not supported."
    case .missingMode(let modeID):
      "\(modeID.displayName) needs keyword aliases."
    case .duplicateMode(let modeID):
      "\(modeID.displayName) appears more than once."
    case .emptyAlias(let modeID):
      "\(modeID.displayName) contains an empty alias."
    case .invalidAlias(let modeID, let alias):
      "\(alias) is not a valid alias for \(modeID.displayName)."
    case .duplicateAlias(let modeID, let alias):
      "\(alias) is repeated for \(modeID.displayName)."
    case .aliasCollision(let alias, let firstMode, let secondMode):
      "\(alias) is assigned to both \(firstMode.displayName) and \(secondMode.displayName)."
    case .invalidMainAlias(let modeID, let alias):
      "\(alias) must be one of the aliases for \(modeID.displayName)."
    case .invalidChecklistTrigger(let trigger):
      "\(trigger.isEmpty ? "The checked marker" : trigger) is not a valid checked marker."
    }
  }
}

public struct ModeAliasRegistry: Sendable, Equatable {
  private struct Entry: Sendable, Equatable {
    let aliases: [String]
    let mainAlias: String
  }

  public let keywordInterpretationEnabled: Bool
  private let entries: [ModeID: Entry]
  private let modesByAlias: [String: ModeID]

  public init(settings: ModeSettings = ModeSettings()) throws {
    guard settings.version == ModeSettings.currentVersion else {
      throw ModeAliasRegistryError.unsupportedSettingsVersion(settings.version)
    }
    guard Self.isValidChecklistTrigger(settings.checklistTrigger) else {
      throw ModeAliasRegistryError.invalidChecklistTrigger(settings.checklistTrigger)
    }

    var entries: [ModeID: Entry] = [:]
    var modesByAlias: [String: ModeID] = [:]
    for definition in settings.definitions {
      guard entries[definition.modeID] == nil else {
        throw ModeAliasRegistryError.duplicateMode(definition.modeID)
      }
      guard !definition.aliases.isEmpty else {
        throw ModeAliasRegistryError.emptyAlias(definition.modeID)
      }

      var aliases: [String] = []
      var aliasesSeen: Set<String> = []
      for sourceAlias in definition.aliases {
        let alias = Self.normalize(sourceAlias)
        guard !alias.isEmpty else {
          throw ModeAliasRegistryError.emptyAlias(definition.modeID)
        }
        guard Self.isSyntacticallyValid(sourceAlias) else {
          throw ModeAliasRegistryError.invalidAlias(definition.modeID, sourceAlias)
        }
        guard aliasesSeen.insert(alias).inserted else {
          throw ModeAliasRegistryError.duplicateAlias(definition.modeID, alias)
        }
        if let existingMode = modesByAlias[alias] {
          throw ModeAliasRegistryError.aliasCollision(alias, existingMode, definition.modeID)
        }
        aliases.append(alias)
        modesByAlias[alias] = definition.modeID
      }

      let mainAlias = Self.normalize(definition.mainAlias)
      guard aliasesSeen.contains(mainAlias) else {
        throw ModeAliasRegistryError.invalidMainAlias(definition.modeID, mainAlias)
      }
      entries[definition.modeID] = Entry(aliases: aliases, mainAlias: mainAlias)
    }

    if let missingMode = ModeID.allCases.first(where: { entries[$0] == nil }) {
      throw ModeAliasRegistryError.missingMode(missingMode)
    }

    keywordInterpretationEnabled = settings.keywordInterpretationEnabled
    self.entries = entries
    self.modesByAlias = modesByAlias
  }

  public func modeID(matching alias: String) -> ModeID? {
    guard keywordInterpretationEnabled else { return nil }
    return modesByAlias[Self.normalize(alias)]
  }

  public func aliases(for modeID: ModeID) -> [String] {
    entries[modeID]?.aliases ?? []
  }

  public func mainAlias(for modeID: ModeID) -> String? {
    entries[modeID]?.mainAlias
  }

  public var allAliases: Set<String> {
    Set(modesByAlias.keys)
  }

  public static func normalize(_ alias: String) -> String {
    alias
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
      .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }

  private static func isSyntacticallyValid(_ alias: String) -> Bool {
    let normalized = alias.trimmingCharacters(in: .whitespacesAndNewlines)
    return !normalized.isEmpty
      && !normalized.contains(":")
      && !normalized.contains("/")
      && !normalized.contains(",")
      && !normalized.unicodeScalars.contains(where: {
        $0.properties.generalCategory == .control
      })
  }

  private static func isValidChecklistTrigger(_ trigger: String) -> Bool {
    !trigger.isEmpty
      && trigger == trigger.trimmingCharacters(in: .whitespacesAndNewlines)
      && !trigger.unicodeScalars.contains(where: {
        $0.properties.isWhitespace || $0.properties.generalCategory == .control
      })
  }
}

public struct ModeHeader: Sendable, Equatable {
  public let modeID: ModeID
  public let matchedAlias: String
  public let title: String?
  public let aliasRange: NSRange
  public let sourceRange: NSRange
  public let bodyRange: NSRange

  public init(
    modeID: ModeID,
    matchedAlias: String,
    title: String?,
    aliasRange: NSRange,
    sourceRange: NSRange,
    bodyRange: NSRange
  ) {
    self.modeID = modeID
    self.matchedAlias = matchedAlias
    self.title = title
    self.aliasRange = aliasRange
    self.sourceRange = sourceRange
    self.bodyRange = bodyRange
  }
}

public struct ModeHeaderParser: Sendable {
  private let registry: ModeAliasRegistry?

  public init(settings: ModeSettings = ModeSettings()) {
    registry = try? ModeAliasRegistry(settings: settings)
  }

  public init(registry: ModeAliasRegistry) {
    self.registry = registry
  }

  public func parse(in source: String) -> ModeHeader? {
    guard !source.isEmpty, let registry else { return nil }
    let nsSource = source as NSString
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    nsSource.getLineStart(
      &lineStart,
      end: &lineEnd,
      contentsEnd: &contentsEnd,
      for: NSRange(location: 0, length: 0)
    )
    let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
    let firstLine = nsSource.substring(with: lineRange)
    let colonRange = (firstLine as NSString).range(of: ":")
    let rawAliasLength = colonRange.location == NSNotFound ? lineRange.length : colonRange.location
    let rawAlias = (firstLine as NSString).substring(
      with: NSRange(location: 0, length: rawAliasLength)
    )
    let leadingWhitespace = rawAlias.prefix(while: Self.isHorizontalWhitespace).utf16.count
    let trailingWhitespace = rawAlias.reversed().prefix(while: Self.isHorizontalWhitespace).count
    let aliasLength = rawAlias.utf16.count - leadingWhitespace - trailingWhitespace
    guard aliasLength > 0 else { return nil }
    let aliasRange = NSRange(location: lineStart + leadingWhitespace, length: aliasLength)
    let sourceAlias = nsSource.substring(with: aliasRange)
    guard let modeID = registry.modeID(matching: sourceAlias) else { return nil }

    let title: String?
    if colonRange.location != NSNotFound {
      let start = colonRange.location + colonRange.length
      let candidate = (firstLine as NSString).substring(from: start)
        .trimmingCharacters(in: .whitespaces)
      title = candidate.isEmpty ? nil : candidate
    } else {
      title = nil
    }

    return ModeHeader(
      modeID: modeID,
      matchedAlias: ModeAliasRegistry.normalize(sourceAlias),
      title: title,
      aliasRange: aliasRange,
      sourceRange: lineRange,
      bodyRange: NSRange(location: lineEnd, length: nsSource.length - lineEnd)
    )
  }

  private static func isHorizontalWhitespace(_ character: Character) -> Bool {
    character == " " || character == "\t"
  }
}

public struct SlashCommand: Sendable, Equatable {
  public let modeID: ModeID
  public let mainAlias: String
  public let aliases: [String]

  public init(modeID: ModeID, mainAlias: String, aliases: [String]) {
    self.modeID = modeID
    self.mainAlias = mainAlias
    self.aliases = aliases
  }
}

public struct SlashCommandEditPlan: Sendable, Equatable {
  public let expectedSource: String
  public let replacementRange: NSRange
  public let replacement: String
  public let selectionAfterEdit: NSRange
  public let modeID: ModeID

  public init(
    expectedSource: String,
    replacementRange: NSRange,
    replacement: String,
    selectionAfterEdit: NSRange,
    modeID: ModeID
  ) {
    self.expectedSource = expectedSource
    self.replacementRange = replacementRange
    self.replacement = replacement
    self.selectionAfterEdit = selectionAfterEdit
    self.modeID = modeID
  }
}

public struct SlashCommandEngine: Sendable {
  public init() {}

  public func commands(
    matching query: String,
    settings: ModeSettings = ModeSettings()
  ) throws -> [SlashCommand] {
    let registry = try ModeAliasRegistry(settings: settings)
    guard registry.keywordInterpretationEnabled else { return [] }
    let normalizedQuery = ModeAliasRegistry.normalize(query)
    return ModeID.allCases.compactMap { modeID in
      guard let mainAlias = registry.mainAlias(for: modeID) else { return nil }
      let aliases = registry.aliases(for: modeID)
      let command = SlashCommand(modeID: modeID, mainAlias: mainAlias, aliases: aliases)
      guard !normalizedQuery.isEmpty else { return command }
      let searchableValues = aliases + [modeID.displayName, modeID.rawValue]
      return searchableValues.contains(where: {
        ModeAliasRegistry.normalize($0).contains(normalizedQuery)
      }) ? command : nil
    }
  }

  public func isEligible(
    in source: String,
    selection: NSRange,
    settings: ModeSettings = ModeSettings()
  ) -> Bool {
    guard settings.keywordInterpretationEnabled,
      selection.length == 0,
      selection.location >= 0,
      selection.location <= source.utf16.count
    else { return false }

    let nsSource = source as NSString
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    nsSource.getLineStart(
      &lineStart,
      end: &lineEnd,
      contentsEnd: &contentsEnd,
      for: NSRange(location: selection.location, length: 0)
    )
    guard selection.location <= contentsEnd else { return false }
    let prefix = nsSource.substring(
      with: NSRange(location: lineStart, length: selection.location - lineStart)
    )
    guard prefix.allSatisfy({ $0 == " " || $0 == "\t" }) else { return false }

    if lineStart == 0,
      let header = ModeHeaderParser(settings: settings).parse(in: source)
    {
      return selection.location == header.aliasRange.location
    }
    let currentLine = nsSource.substring(
      with: NSRange(location: lineStart, length: contentsEnd - lineStart)
    )
    return currentLine.trimmingCharacters(in: .whitespaces).isEmpty
  }

  public func editPlan(
    in source: String,
    selection: NSRange,
    selecting modeID: ModeID,
    settings: ModeSettings = ModeSettings()
  ) throws -> SlashCommandEditPlan? {
    let registry = try ModeAliasRegistry(settings: settings)
    guard registry.keywordInterpretationEnabled,
      let mainAlias = registry.mainAlias(for: modeID),
      isEligible(in: source, selection: selection, settings: settings)
    else { return nil }

    let replacementRange: NSRange
    let replacement: String
    if let header = ModeHeaderParser(registry: registry).parse(in: source) {
      replacementRange = header.aliasRange
      replacement = mainAlias
    } else if selection.location == 0
      || source.prefix(selection.location).allSatisfy({ $0 == " " || $0 == "\t" })
    {
      replacementRange = NSRange(location: selection.location, length: 0)
      replacement = mainAlias
    } else {
      replacementRange = NSRange(location: 0, length: 0)
      replacement = mainAlias + preferredLineEnding(in: source)
    }
    return SlashCommandEditPlan(
      expectedSource: source,
      replacementRange: replacementRange,
      replacement: replacement,
      selectionAfterEdit: NSRange(
        location: replacementRange.location + mainAlias.utf16.count,
        length: 0
      ),
      modeID: modeID
    )
  }

  private func preferredLineEnding(in source: String) -> String {
    if source.contains("\r\n") {
      return "\r\n"
    }
    if source.contains("\n") {
      return "\n"
    }
    if source.contains("\r") {
      return "\r"
    }
    return "\n"
  }
}
