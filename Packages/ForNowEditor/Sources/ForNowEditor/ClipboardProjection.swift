import AppKit
import ForNowCore
import ForNowModes
import Foundation

public struct ExportProjectionPolicy: Sendable, Equatable {
  public var omitsModeHeader: Bool
  public var omitsChecklistTriggers: Bool
  public var checklistTrigger: String
  public var modeSettings: ModeSettings
  private var additionalModeAliases: Set<String>

  public var modeAliases: Set<String> {
    let registry = try? ModeAliasRegistry(settings: modeSettings)
    let configured =
      registry?.keywordInterpretationEnabled == true
      ? registry?.allAliases ?? [] : []
    return configured.union(additionalModeAliases)
  }

  public init(
    omitsModeHeader: Bool = true,
    omitsChecklistTriggers: Bool = true,
    checklistTrigger: String = "/x",
    modeSettings: ModeSettings = ModeSettings(),
    modeAliases: Set<String>? = nil
  ) {
    self.omitsModeHeader = omitsModeHeader
    self.omitsChecklistTriggers = omitsChecklistTriggers
    self.checklistTrigger = checklistTrigger
    self.modeSettings = modeSettings
    additionalModeAliases = Set((modeAliases ?? []).map(Self.normalizeAlias))
  }

  private static func normalizeAlias(_ alias: String) -> String {
    alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

public struct CleanExportProjection: Sendable {
  public init() {}

  public func text(from source: String, policy: ExportProjectionPolicy) -> String {
    var exported = source
    if policy.omitsChecklistTriggers, !policy.checklistTrigger.isEmpty {
      exported = removingChecklistTriggers(from: exported, policy: policy)
    }
    if policy.omitsModeHeader {
      exported = removingModeHeader(from: exported, policy: policy)
    }
    return exported
  }

  private func removingModeHeader(from source: String, policy: ExportProjectionPolicy) -> String {
    guard !source.isEmpty else { return source }
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
    if let header = ModeHeaderParser(settings: policy.modeSettings).parse(in: source) {
      let remainder = nsSource.substring(from: lineEnd)
      if header.modeID == .code {
        return remainder
      }
      guard let title = header.title else { return remainder }
      let lineEnding = nsSource.substring(
        with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd)
      )
      return title + lineEnding + remainder
    }

    let firstLine = nsSource.substring(with: NSRange(location: lineStart, length: contentsEnd))
    let trimmedLine = firstLine.trimmingCharacters(in: .whitespaces)
    let components = trimmedLine.split(
      separator: ":",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    guard let aliasComponent = components.first else { return source }
    let alias = aliasComponent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard policy.modeAliases.contains(alias) else { return source }

    let remainder = nsSource.substring(from: lineEnd)
    if alias == "code" {
      return remainder
    }
    guard components.count == 2 else { return remainder }
    let title = components[1].trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty else { return remainder }
    let lineEnding = nsSource.substring(
      with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd)
    )
    return title + lineEnding + remainder
  }

  private func removingChecklistTriggers(
    from source: String,
    policy: ExportProjectionPolicy
  ) -> String {
    var settings = policy.modeSettings
    settings.checklistTrigger = policy.checklistTrigger
    let markerRanges = ListModeParser(settings: settings).parse(in: source)
      .compactMap(\.markerRange)
      .sorted { $0.location > $1.location }
    guard !markerRanges.isEmpty else { return source }
    let exported = NSMutableString(string: source)
    for markerRange in markerRanges {
      exported.replaceCharacters(in: markerRange, with: "")
    }
    return exported as String
  }
}

public struct ProjectionCopyPolicy: Sendable {
  private let exportProjection = CleanExportProjection()

  public init() {}

  public func copyText(
    from snapshot: SourceSnapshot,
    selection: SourceSelection,
    exportPolicy: ExportProjectionPolicy = ExportProjectionPolicy()
  ) -> String {
    let clamped = snapshot.clamped(selection)
    if clamped.range.length > 0, let selected = snapshot.substring(in: clamped.range) {
      return selected
    }

    let caret = clamped.range.location
    if let codeNote = codeNote(
      at: caret,
      in: snapshot.text,
      modeSettings: exportPolicy.modeSettings
    ) {
      return codeNote
    }
    if let inlineCode = inlineCode(at: caret, in: snapshot.text) {
      return inlineCode
    }
    if let fencedCode = fencedCode(at: caret, in: snapshot.text) {
      return fencedCode
    }
    return exportProjection.text(from: snapshot.text, policy: exportPolicy)
  }

  private func codeNote(
    at caret: SourceOffset,
    in source: String,
    modeSettings: ModeSettings
  ) -> String? {
    guard
      let header = CodeModeHeaderParser(modeSettings: modeSettings).parse(
        in: source,
        defaultLanguage: .plainText
      ),
      caret.utf16Offset >= header.bodyRange.location,
      caret.utf16Offset <= NSMaxRange(header.bodyRange)
    else { return nil }
    return (source as NSString).substring(with: header.bodyRange)
  }

  public func copyText(for decoration: EditorDecoration) -> String? {
    switch decoration {
    case .style:
      nil
    case .link(_, let presentation):
      presentation.originalURL
    case .result(_, let presentation):
      presentation.canonicalValue
    case .checkbox:
      nil
    }
  }

  private func inlineCode(at caret: SourceOffset, in source: String) -> String? {
    guard let expression = try? NSRegularExpression(pattern: #"`([^`\r\n]+)`"#) else {
      return nil
    }
    let sourceRange = NSRange(location: 0, length: source.utf16.count)
    for match in expression.matches(in: source, range: sourceRange) where match.numberOfRanges == 2
    {
      let contentRange = match.range(at: 1)
      if caret.utf16Offset >= contentRange.location,
        caret.utf16Offset <= NSMaxRange(contentRange)
      {
        return (source as NSString).substring(with: contentRange)
      }
    }
    return nil
  }

  private func fencedCode(at caret: SourceOffset, in source: String) -> String? {
    let nsSource = source as NSString
    for fence in ForNowModes.CodeContextParser().fencedCode(in: source) {
      if caret.utf16Offset >= fence.contentRange.location,
        caret.utf16Offset <= NSMaxRange(fence.contentRange)
      {
        return nsSource.substring(with: fence.contentRange)
      }
    }
    return nil
  }
}

public struct PasteSettings: Codable, Sendable, Equatable {
  public var stripsLeadingWhitespace: Bool
  public var stripsListNumbers: Bool
  public var stripsBullets: Bool
  public var stripsMarkdown: Bool
  public var stripsEmptyLines: Bool

  public init(
    stripsLeadingWhitespace: Bool = true,
    stripsListNumbers: Bool = true,
    stripsBullets: Bool = true,
    stripsMarkdown: Bool = true,
    stripsEmptyLines: Bool = true
  ) {
    self.stripsLeadingWhitespace = stripsLeadingWhitespace
    self.stripsListNumbers = stripsListNumbers
    self.stripsBullets = stripsBullets
    self.stripsMarkdown = stripsMarkdown
    self.stripsEmptyLines = stripsEmptyLines
  }
}

public enum PasteMode: Sendable, Equatable {
  case normal
  case raw
}

public enum PasteContext: Sendable, Equatable {
  case plain
  case code
}

public struct PasteboardPayload: Sendable, Equatable {
  public let plainText: String?
  public let html: Data?
  public let richText: Data?

  public init(plainText: String? = nil, html: Data? = nil, richText: Data? = nil) {
    self.plainText = plainText
    self.html = html
    self.richText = richText
  }
}

public enum PastePipelineError: Error, LocalizedError, Sendable, Equatable {
  case unsupportedClipboardContent
  case unreadableTextRepresentation

  public var errorDescription: String? {
    switch self {
    case .unsupportedClipboardContent:
      "The clipboard does not contain supported text."
    case .unreadableTextRepresentation:
      "The clipboard text could not be read."
    }
  }
}

@MainActor
public struct PasteboardTextDecoder {
  public init() {}

  public func text(from payload: PasteboardPayload) throws -> String {
    if let plainText = payload.plainText {
      return plainText
    }
    if let html = payload.html {
      return try attributedText(from: html, documentType: .html)
    }
    if let richText = payload.richText {
      return try attributedText(from: richText, documentType: .rtf)
    }
    throw PastePipelineError.unsupportedClipboardContent
  }

  private func attributedText(
    from data: Data,
    documentType: NSAttributedString.DocumentType
  ) throws -> String {
    guard !data.isEmpty else {
      throw PastePipelineError.unreadableTextRepresentation
    }
    let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
      .documentType: documentType,
      .characterEncoding: String.Encoding.utf8.rawValue,
    ]
    guard
      let attributed = try? NSAttributedString(
        data: data,
        options: options,
        documentAttributes: nil
      )
    else {
      throw PastePipelineError.unreadableTextRepresentation
    }
    return textPreservingLinks(from: attributed)
  }

  private func textPreservingLinks(from attributed: NSAttributedString) -> String {
    var replacements: [(range: NSRange, text: String)] = []
    let fullRange = NSRange(location: 0, length: attributed.length)
    attributed.enumerateAttribute(.link, in: fullRange) { value, range, _ in
      guard let value else { return }
      let destination: String
      if let url = value as? URL {
        destination = url.absoluteString
      } else {
        destination = String(describing: value)
      }
      let label = attributed.attributedSubstring(from: range).string
      replacements.append(
        (range, SmartLinkPasteRule().replacement(label: label, destination: destination))
      )
    }

    let result = NSMutableString(string: attributed.string)
    for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
      result.replaceCharacters(in: replacement.range, with: replacement.text)
    }
    return result as String
  }
}

public struct SmartLinkPasteRule: Sendable {
  public init() {}

  public func transform(_ source: String) -> String {
    guard
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
      let destination = nsSource.substring(with: match.range(at: 2))
      result.replaceCharacters(
        in: match.range,
        with: replacement(label: label, destination: destination)
      )
    }
    return result as String
  }

  public func replacement(label: String, destination: String) -> String {
    let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedLabel.isEmpty, trimmedLabel != destination else { return destination }
    return "\(trimmedLabel) (\(destination))"
  }
}

public struct PasteTransformer: Sendable {
  public init() {}

  public func transform(_ source: String, settings: PasteSettings) -> String {
    let normalized = normalizeLineEndings(source)
    var lines = SmartLinkPasteRule().transform(normalized).components(
      separatedBy: "\n"
    )

    for index in lines.indices {
      var line = lines[index]
      if settings.stripsListNumbers {
        line = replacing(
          #"^([\t ]*)\d+[.)][\t ]+"#,
          in: line,
          with: "$1"
        )
      }
      if settings.stripsBullets {
        line = replacing(
          #"^([\t ]*)[-+*•][\t ]+"#,
          in: line,
          with: "$1"
        )
      }
      if settings.stripsLeadingWhitespace {
        line = replacing(#"^[\t ]+"#, in: line, with: "")
      }
      if settings.stripsMarkdown {
        line = stripMarkdown(from: line)
      }
      lines[index] = line
    }

    if settings.stripsEmptyLines {
      lines.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    return lines.joined(separator: "\n")
  }

  public func normalizeLineEndings(_ source: String) -> String {
    source.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private func stripMarkdown(from source: String) -> String {
    let trimmed = source.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
      return ""
    }

    var result = source
    result = replacing(#"^([\t ]*)#{1,6}[\t ]+"#, in: result, with: "$1")
    result = replacing(#"^([\t ]*)>[\t ]?"#, in: result, with: "$1")
    result = replacing(#"\*\*([^*]+)\*\*"#, in: result, with: "$1")
    result = replacing(#"__([^_]+)__"#, in: result, with: "$1")
    result = replacing(#"~~([^~]+)~~"#, in: result, with: "$1")
    result = replacing(#"`([^`]+)`"#, in: result, with: "$1")
    result = replacing(#"(?<!\*)\*([^*]+)\*(?!\*)"#, in: result, with: "$1")
    result = replacing(#"(?<!_)_([^_]+)_(?!_)"#, in: result, with: "$1")
    return result
  }

  private func replacing(_ pattern: String, in source: String, with template: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
    return expression.stringByReplacingMatches(
      in: source,
      range: NSRange(location: 0, length: source.utf16.count),
      withTemplate: template
    )
  }
}

@MainActor
public struct PastePipeline {
  private let decoder = PasteboardTextDecoder()
  private let transformer = PasteTransformer()

  public init() {}

  public func sourceText(
    from payload: PasteboardPayload,
    mode: PasteMode,
    settings: PasteSettings,
    context: PasteContext = .plain
  ) throws -> String {
    let decoded = try decoder.text(from: payload)
    switch mode {
    case .normal:
      var effectiveSettings = settings
      if context == .code {
        effectiveSettings.stripsLeadingWhitespace = false
      }
      return transformer.transform(decoded, settings: effectiveSettings)
    case .raw:
      return transformer.normalizeLineEndings(decoded)
    }
  }
}
