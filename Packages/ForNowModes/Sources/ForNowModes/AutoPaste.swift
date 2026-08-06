import CryptoKit
import Foundation

public struct AutoPasteCommand: Sendable, Equatable {
  public let separatorOverride: String?

  public init(separatorOverride: String? = nil) {
    self.separatorOverride = separatorOverride
  }
}

public struct AutoPasteCommandParser: Sendable {
  public static let maximumDelimiterUTF16Length = 256

  public init() {}

  public func parse(_ line: String) -> AutoPasteCommand? {
    guard !line.isEmpty, !line.unicodeScalars.contains(where: CharacterSet.newlines.contains)
    else { return nil }

    var candidate = line
    while candidate.last == " " || candidate.last == "\t" {
      candidate.removeLast()
    }
    guard candidate.first != " ", candidate.first != "\t" else { return nil }
    guard candidate.prefix(5).lowercased() == "paste" else { return nil }

    let remainder = candidate.dropFirst(5)
    guard !remainder.isEmpty else {
      return AutoPasteCommand()
    }
    guard remainder.first == "(", remainder.last == ")" else { return nil }
    let separator = String(remainder.dropFirst().dropLast())
    guard separator.utf16.count <= Self.maximumDelimiterUTF16Length else { return nil }
    return AutoPasteCommand(separatorOverride: separator)
  }
}

public enum AutoPasteSeparatorPreset: String, Codable, CaseIterable, Sendable {
  case newLine
  case blankLine
  case space
  case commaSpace

  public var separator: String {
    switch self {
    case .newLine: "\n"
    case .blankLine: "\n\n"
    case .space: " "
    case .commaSpace: ", "
    }
  }

  public var displayName: String {
    switch self {
    case .newLine: "New Line"
    case .blankLine: "Blank Line"
    case .space: "Space"
    case .commaSpace: "Comma and Space"
    }
  }
}

public enum AutoPasteLinkTreatment: String, Codable, CaseIterable, Sendable {
  case preserve
  case readableText
  case destinationOnly

  public var displayName: String {
    switch self {
    case .preserve: "Keep Original"
    case .readableText: "Readable Text"
    case .destinationOnly: "Destination Only"
    }
  }
}

public enum AutoPasteTimestampPolicy: String, Codable, CaseIterable, Sendable {
  case none
  case iso8601

  public var displayName: String {
    switch self {
    case .none: "None"
    case .iso8601: "ISO 8601"
    }
  }
}

public struct AutoPasteSettings: Codable, Sendable, Equatable {
  public var prefix: String
  public var suffix: String
  public var separatorPreset: AutoPasteSeparatorPreset
  public var linkTreatment: AutoPasteLinkTreatment
  public var timestampPolicy: AutoPasteTimestampPolicy

  public init(
    prefix: String = "",
    suffix: String = "",
    separatorPreset: AutoPasteSeparatorPreset = .newLine,
    linkTreatment: AutoPasteLinkTreatment = .preserve,
    timestampPolicy: AutoPasteTimestampPolicy = .none
  ) {
    self.prefix = prefix
    self.suffix = suffix
    self.separatorPreset = separatorPreset
    self.linkTreatment = linkTreatment
    self.timestampPolicy = timestampPolicy
  }

  public func validated() throws -> AutoPasteSettings {
    guard prefix.utf16.count <= 1_024, suffix.utf16.count <= 1_024 else {
      throw AutoPasteSettingsError.affixTooLong
    }
    return self
  }
}

public enum AutoPasteSettingsError: Error, Equatable, Sendable {
  case affixTooLong
}

public struct AutoPasteCapturePolicy: Sendable, Equatable {
  public let prefix: String
  public let suffix: String
  public let separator: String
  public let linkTreatment: AutoPasteLinkTreatment
  public let timestampPolicy: AutoPasteTimestampPolicy

  public init(
    prefix: String = "",
    suffix: String = "",
    separator: String = "\n",
    linkTreatment: AutoPasteLinkTreatment = .preserve,
    timestampPolicy: AutoPasteTimestampPolicy = .none
  ) {
    self.prefix = prefix
    self.suffix = suffix
    self.separator = separator
    self.linkTreatment = linkTreatment
    self.timestampPolicy = timestampPolicy
  }

  public init(settings: AutoPasteSettings, separatorOverride: String? = nil) {
    self.init(
      prefix: settings.prefix,
      suffix: settings.suffix,
      separator: separatorOverride ?? settings.separatorPreset.separator,
      linkTreatment: settings.linkTreatment,
      timestampPolicy: settings.timestampPolicy
    )
  }

  public func formattedItem(_ source: String, capturedAt date: Date) -> String {
    let normalized = AutoPasteTextNormalizer().normalize(source)
    let linked = transformLinks(in: normalized)
    return prefix + timestamp(at: date) + linked + suffix
  }

  public func appending(
    _ capturedText: String,
    to source: String,
    capturedAt date: Date,
    isFirstCapture: Bool
  ) -> String {
    let item = formattedItem(capturedText, capturedAt: date)
    guard !source.isEmpty else { return item }
    if isFirstCapture, source.hasSuffix("\n") || (!separator.isEmpty && source.hasSuffix(separator)) {
      return source + item
    }
    return source + separator + item
  }

  private func transformLinks(in source: String) -> String {
    guard linkTreatment != .preserve,
      let expression = try? NSRegularExpression(
        pattern: #"!?\[([^\]\r\n]*)\]\((https?://[^\s)]+)\)"#,
        options: [.caseInsensitive]
      )
    else { return source }
    let matches = expression.matches(
      in: source,
      range: NSRange(location: 0, length: source.utf16.count)
    )
    let result = NSMutableString(string: source)
    let nsSource = source as NSString
    for match in matches.reversed() where match.numberOfRanges == 3 {
      let label = nsSource.substring(with: match.range(at: 1))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let destination = nsSource.substring(with: match.range(at: 2))
      let replacement: String
      switch linkTreatment {
      case .preserve:
        replacement = nsSource.substring(with: match.range)
      case .readableText:
        replacement = label.isEmpty || label == destination
          ? destination : "\(label) (\(destination))"
      case .destinationOnly:
        replacement = destination
      }
      result.replaceCharacters(in: match.range, with: replacement)
    }
    return result as String
  }

  private func timestamp(at date: Date) -> String {
    guard timestampPolicy == .iso8601 else { return "" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return "[\(formatter.string(from: date))] "
  }
}

public struct AutoPasteTextNormalizer: Sendable {
  public init() {}

  public func normalize(_ source: String) -> String {
    source.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\u{0000}", with: "")
  }
}

public struct AutoPasteEventDeduplicator: Sendable {
  public let historyLimit: Int
  public private(set) var historyCount = 0
  public private(set) var lastObservedChangeCount: Int?

  private var orderedHashes: [String] = []
  private var hashes: Set<String> = []

  public init(historyLimit: Int = 64) {
    self.historyLimit = max(1, historyLimit)
  }

  public mutating func accepts(changeCount: Int, text: String) -> Bool {
    guard changeCount != lastObservedChangeCount else { return false }
    lastObservedChangeCount = changeCount
    let normalized = AutoPasteTextNormalizer().normalize(text)
    guard !normalized.isEmpty else { return false }
    let hash = Self.hash(normalized)
    guard hashes.insert(hash).inserted else { return false }
    orderedHashes.append(hash)
    if orderedHashes.count > historyLimit {
      hashes.remove(orderedHashes.removeFirst())
    }
    historyCount = orderedHashes.count
    return true
  }

  private static func hash(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

public struct AutoPasteDestinationName: Sendable {
  public init() {}

  public func resolve(from source: String, maximumLength: Int = 60) -> String {
    for line in source.components(separatedBy: .newlines) {
      let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !candidate.isEmpty, AutoPasteCommandParser().parse(candidate) == nil else { continue }
      return String(candidate.prefix(max(1, maximumLength)))
    }
    return "Untitled note"
  }
}
