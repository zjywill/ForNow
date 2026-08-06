import CryptoKit
import ForNowModes
import Foundation

public enum EditorLayoutDirection: String, CaseIterable, Codable, Sendable {
  case natural
  case leftToRight
  case rightToLeft

  public var displayName: String {
    switch self {
    case .natural:
      "Natural"
    case .leftToRight:
      "Left to Right"
    case .rightToLeft:
      "Right to Left"
    }
  }
}

public struct EditorSettings: Codable, Sendable, Equatable {
  public var automaticallyShortensLinks: Bool
  public var hyperlinkFeaturesEnabled: Bool
  public var defaultCodeLanguage: CodeLanguage
  public var codeHighlightTheme: CodeHighlightTheme
  public var omitsChecklistTriggersOnExport: Bool
  public var layoutDirection: EditorLayoutDirection

  public init(
    automaticallyShortensLinks: Bool = true,
    hyperlinkFeaturesEnabled: Bool = true,
    defaultCodeLanguage: CodeLanguage = .plainText,
    codeHighlightTheme: CodeHighlightTheme = .adaptive,
    omitsChecklistTriggersOnExport: Bool = true,
    layoutDirection: EditorLayoutDirection = .natural
  ) {
    self.automaticallyShortensLinks = automaticallyShortensLinks
    self.hyperlinkFeaturesEnabled = hyperlinkFeaturesEnabled
    self.defaultCodeLanguage = defaultCodeLanguage
    self.codeHighlightTheme = codeHighlightTheme
    self.omitsChecklistTriggersOnExport = omitsChecklistTriggersOnExport
    self.layoutDirection = layoutDirection
  }

  private enum CodingKeys: String, CodingKey {
    case automaticallyShortensLinks
    case hyperlinkFeaturesEnabled
    case defaultCodeLanguage
    case codeHighlightTheme
    case omitsChecklistTriggersOnExport
    case layoutDirection
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    automaticallyShortensLinks =
      try values.decodeIfPresent(
        Bool.self,
        forKey: .automaticallyShortensLinks
      ) ?? true
    hyperlinkFeaturesEnabled =
      try values.decodeIfPresent(
        Bool.self,
        forKey: .hyperlinkFeaturesEnabled
      ) ?? true
    defaultCodeLanguage =
      try values.decodeIfPresent(
        CodeLanguage.self,
        forKey: .defaultCodeLanguage
      ) ?? .plainText
    codeHighlightTheme =
      try values.decodeIfPresent(
        CodeHighlightTheme.self,
        forKey: .codeHighlightTheme
      ) ?? .adaptive
    omitsChecklistTriggersOnExport =
      try values.decodeIfPresent(
        Bool.self,
        forKey: .omitsChecklistTriggersOnExport
      ) ?? true
    layoutDirection =
      try values.decodeIfPresent(
        EditorLayoutDirection.self,
        forKey: .layoutDirection
      ) ?? .natural
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(automaticallyShortensLinks, forKey: .automaticallyShortensLinks)
    try values.encode(hyperlinkFeaturesEnabled, forKey: .hyperlinkFeaturesEnabled)
    try values.encode(defaultCodeLanguage, forKey: .defaultCodeLanguage)
    try values.encode(codeHighlightTheme, forKey: .codeHighlightTheme)
    try values.encode(
      omitsChecklistTriggersOnExport,
      forKey: .omitsChecklistTriggersOnExport
    )
    try values.encode(layoutDirection, forKey: .layoutDirection)
  }
}

public struct LinkIdentity: Codable, Hashable, Sendable {
  public let urlDigest: String
  public let occurrenceIndex: Int

  public init(originalURL: String, occurrenceIndex: Int) {
    let digest = SHA256.hash(data: Data(originalURL.utf8))
    urlDigest = digest.map { String(format: "%02x", $0) }.joined()
    self.occurrenceIndex = max(1, occurrenceIndex)
  }

  public init(urlDigest: String, occurrenceIndex: Int) {
    self.urlDigest = urlDigest
    self.occurrenceIndex = max(1, occurrenceIndex)
  }
}

public struct HTTPLinkValidator: Sendable {
  public init() {}

  public func validatedURL(from exactSource: String) -> URL? {
    guard !exactSource.isEmpty,
      exactSource.unicodeScalars.allSatisfy({
        !$0.properties.isWhitespace && $0.properties.generalCategory != .control
      }),
      let components = URLComponents(string: exactSource),
      let scheme = components.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let host = components.host,
      !host.isEmpty,
      let url = components.url
    else { return nil }
    return url
  }
}

public struct LinkDisplayPolicy: Sendable {
  public init() {}

  public func displayText(
    for presentation: LinkPresentation,
    settings: EditorSettings,
    expandedIdentities: Set<LinkIdentity>
  ) -> String? {
    guard settings.hyperlinkFeaturesEnabled else { return nil }
    if !settings.automaticallyShortensLinks
      || expandedIdentities.contains(presentation.identity)
    {
      let duplicateSuffix =
        presentation.duplicateIndex > 1 ? " · \(presentation.duplicateIndex)" : ""
      return presentation.originalURL + duplicateSuffix
    }
    return presentation.displayText
  }
}

public struct LinkVisibilityPolicy: Sendable {
  public init() {}

  public func shouldPresent(sourceRange: NSRange, selection: NSRange) -> Bool {
    if selection.length == 0 {
      return selection.location < sourceRange.location
        || selection.location > NSMaxRange(sourceRange)
    }
    return NSIntersectionRange(selection, sourceRange).length == 0
  }
}

public struct LinkInteractionModifiers: OptionSet, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let command = LinkInteractionModifiers(rawValue: 1 << 0)
  public static let shift = LinkInteractionModifiers(rawValue: 1 << 1)
}

public enum LinkInteractionAction: Sendable, Equatable {
  case open(URL)
  case toggleExpanded(LinkIdentity)
  case ignore
}

public struct LinkInteractionPolicy: Sendable {
  private let validator: HTTPLinkValidator

  public init(validator: HTTPLinkValidator = HTTPLinkValidator()) {
    self.validator = validator
  }

  public func action(
    for presentation: LinkPresentation,
    modifiers: LinkInteractionModifiers,
    settings: EditorSettings
  ) -> LinkInteractionAction {
    guard settings.hyperlinkFeaturesEnabled else { return .ignore }
    if modifiers.contains([.command, .shift]) {
      return .toggleExpanded(presentation.identity)
    }
    guard let url = validator.validatedURL(from: presentation.originalURL) else {
      return .ignore
    }
    return .open(url)
  }
}

struct LinkCodeContextPolicy: Sendable {
  func excludesAllLinks(
    in source: String,
    modeSettings: ModeSettings = ModeSettings()
  ) -> Bool {
    CodeContextParser().codeHeader(in: source, modeSettings: modeSettings) != nil
  }

  func fencedCodeRanges(in source: String) -> [NSRange] {
    CodeContextParser().fencedCode(in: source).map(\.fullRange)
  }
}
