import Foundation

public enum CodeLanguage: String, CaseIterable, Codable, Sendable {
  case plainText
  case swift
  case python
  case javascript
  case typescript
  case json
  case shell

  public var displayName: String {
    switch self {
    case .plainText:
      "Plain Text"
    case .swift:
      "Swift"
    case .python:
      "Python"
    case .javascript:
      "JavaScript"
    case .typescript:
      "TypeScript"
    case .json:
      "JSON"
    case .shell:
      "Shell"
    }
  }

  public init?(identifier: String) {
    switch identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "plain", "plaintext", "plain-text", "text", "txt":
      self = .plainText
    case "swift":
      self = .swift
    case "py", "python":
      self = .python
    case "js", "javascript", "node":
      self = .javascript
    case "ts", "typescript":
      self = .typescript
    case "json":
      self = .json
    case "bash", "sh", "shell", "zsh":
      self = .shell
    default:
      return nil
    }
  }
}

public struct CodeModeHeader: Sendable, Equatable {
  public let headerRange: NSRange
  public let bodyRange: NSRange
  public let languageIdentifier: String?
  public let language: CodeLanguage

  public init(
    headerRange: NSRange,
    bodyRange: NSRange,
    languageIdentifier: String?,
    language: CodeLanguage
  ) {
    self.headerRange = headerRange
    self.bodyRange = bodyRange
    self.languageIdentifier = languageIdentifier
    self.language = language
  }
}

public struct CodeModeHeaderParser: Sendable {
  private let modeSettings: ModeSettings

  public init(modeSettings: ModeSettings = ModeSettings()) {
    self.modeSettings = modeSettings
  }

  public func parse(in source: String, defaultLanguage: CodeLanguage) -> CodeModeHeader? {
    guard
      let header = ModeHeaderParser(settings: modeSettings).parse(in: source),
      header.modeID == .code
    else { return nil }
    let identifier = header.title
    let language: CodeLanguage
    if let identifier {
      language = CodeLanguage(identifier: identifier) ?? .plainText
    } else {
      language = defaultLanguage
    }
    return CodeModeHeader(
      headerRange: header.sourceRange,
      bodyRange: header.bodyRange,
      languageIdentifier: identifier,
      language: language
    )
  }
}

public struct CodeFence: Sendable, Equatable {
  public let fullRange: NSRange
  public let openingRange: NSRange
  public let contentRange: NSRange
  public let closingRange: NSRange?
  public let languageIdentifier: String?
  public let language: CodeLanguage
}

public struct CodeContextParser: Sendable {
  public init() {}

  public func codeHeader(
    in source: String,
    defaultLanguage: CodeLanguage = .plainText,
    modeSettings: ModeSettings = ModeSettings()
  ) -> CodeModeHeader? {
    CodeModeHeaderParser(modeSettings: modeSettings).parse(
      in: source,
      defaultLanguage: defaultLanguage
    )
  }

  public func fencedCode(in source: String) -> [CodeFence] {
    let nsSource = source as NSString
    var location = 0
    var active: OpeningFence?
    var fences: [CodeFence] = []

    while location < nsSource.length {
      let line = lineDescriptor(at: location, in: nsSource)
      if let current = active {
        if isClosingFence(line.text, character: current.character, count: current.count) {
          fences.append(
            CodeFence(
              fullRange: NSRange(
                location: current.lineRange.location,
                length: NSMaxRange(line.lineRange) - current.lineRange.location
              ),
              openingRange: current.contentsRange,
              contentRange: NSRange(
                location: NSMaxRange(current.lineRange),
                length: line.lineRange.location - NSMaxRange(current.lineRange)
              ),
              closingRange: line.contentsRange,
              languageIdentifier: current.languageIdentifier,
              language: current.language
            )
          )
          selfAdvance(&location, to: NSMaxRange(line.lineRange))
          active = nil
          continue
        }
      } else if let opening = openingFence(from: line) {
        active = opening
      }
      selfAdvance(&location, to: NSMaxRange(line.lineRange))
    }

    if let active {
      fences.append(
        CodeFence(
          fullRange: NSRange(
            location: active.lineRange.location,
            length: nsSource.length - active.lineRange.location
          ),
          openingRange: active.contentsRange,
          contentRange: NSRange(
            location: NSMaxRange(active.lineRange),
            length: nsSource.length - NSMaxRange(active.lineRange)
          ),
          closingRange: nil,
          languageIdentifier: active.languageIdentifier,
          language: active.language
        )
      )
    }
    return fences
  }

  public func isCodeContext(
    in source: String,
    selection: NSRange,
    defaultLanguage: CodeLanguage = .plainText,
    modeSettings: ModeSettings = ModeSettings()
  ) -> Bool {
    if codeHeader(
      in: source,
      defaultLanguage: defaultLanguage,
      modeSettings: modeSettings
    ) != nil {
      return true
    }
    return fencedCode(in: source).contains { fence in
      if selection.length == 0 {
        let isAtUnclosedEnd =
          fence.closingRange == nil && selection.location == NSMaxRange(fence.fullRange)
        return selection.location >= fence.fullRange.location
          && (selection.location < NSMaxRange(fence.fullRange) || isAtUnclosedEnd)
      }
      return NSIntersectionRange(selection, fence.fullRange).length > 0
    }
  }

  private struct LineDescriptor {
    let lineRange: NSRange
    let contentsRange: NSRange
    let text: String
  }

  private struct OpeningFence {
    let character: Character
    let count: Int
    let lineRange: NSRange
    let contentsRange: NSRange
    let languageIdentifier: String?
    let language: CodeLanguage
  }

  private func lineDescriptor(at location: Int, in source: NSString) -> LineDescriptor {
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    source.getLineStart(
      &lineStart,
      end: &lineEnd,
      contentsEnd: &contentsEnd,
      for: NSRange(location: location, length: 0)
    )
    let contentsRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
    return LineDescriptor(
      lineRange: NSRange(location: lineStart, length: lineEnd - lineStart),
      contentsRange: contentsRange,
      text: source.substring(with: contentsRange)
    )
  }

  private func openingFence(from line: LineDescriptor) -> OpeningFence? {
    let trimmed = line.text.drop(while: { $0 == " " || $0 == "\t" })
    guard let character = trimmed.first, character == "`" || character == "~" else {
      return nil
    }
    let count = trimmed.prefix(while: { $0 == character }).count
    guard count >= 3 else { return nil }
    let info = trimmed.dropFirst(count).trimmingCharacters(in: .whitespacesAndNewlines)
    let identifier = info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    return OpeningFence(
      character: character,
      count: count,
      lineRange: line.lineRange,
      contentsRange: line.contentsRange,
      languageIdentifier: identifier,
      language: identifier.flatMap(CodeLanguage.init(identifier:)) ?? .plainText
    )
  }

  private func isClosingFence(_ line: String, character: Character, count: Int) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.first == character else { return false }
    let closingCount = trimmed.prefix(while: { $0 == character }).count
    return closingCount >= count && trimmed.dropFirst(closingCount).isEmpty
  }

  private func selfAdvance(_ location: inout Int, to nextLocation: Int) {
    location = nextLocation > location ? nextLocation : location + 1
  }

}

public enum SourceTextRole: Sendable, Equatable {
  case heading(level: Int)
  case bold
  case italic
  case strikethrough
  case underline
  case inlineCode
  case codeFence
  case codeBlock(language: CodeLanguage)
  case comment
  case modeHeader
}

public struct SourceStyleSpan: Sendable, Equatable {
  public let range: NSRange
  public let role: SourceTextRole

  public init(range: NSRange, role: SourceTextRole) {
    self.range = range
    self.role = role
  }
}

public struct LimitedMarkdownParser: Sendable {
  public init() {}

  public func parse(
    _ source: String,
    defaultCodeLanguage: CodeLanguage = .plainText,
    modeSettings: ModeSettings = ModeSettings()
  ) -> [SourceStyleSpan] {
    let contexts = CodeContextParser()
    if let header = contexts.codeHeader(
      in: source,
      defaultLanguage: defaultCodeLanguage,
      modeSettings: modeSettings
    ) {
      var spans = [SourceStyleSpan(range: header.headerRange, role: .modeHeader)]
      if header.bodyRange.length > 0 {
        spans.append(
          SourceStyleSpan(range: header.bodyRange, role: .codeBlock(language: header.language))
        )
      }
      return spans
    }

    let fences = contexts.fencedCode(in: source)
    let modeHeader = ModeHeaderParser(settings: modeSettings).parse(in: source)
    var spans: [SourceStyleSpan] =
      modeHeader.map {
        [SourceStyleSpan(range: $0.sourceRange, role: .modeHeader)]
      } ?? []
    for fence in fences {
      spans.append(SourceStyleSpan(range: fence.openingRange, role: .codeFence))
      if fence.contentRange.length > 0 {
        spans.append(
          SourceStyleSpan(range: fence.contentRange, role: .codeBlock(language: fence.language))
        )
      }
      if let closingRange = fence.closingRange {
        spans.append(SourceStyleSpan(range: closingRange, role: .codeFence))
      }
    }

    let nsSource = source as NSString
    var location = 0
    while location < nsSource.length {
      let lineRange = nsSource.lineRange(for: NSRange(location: location, length: 0))
      let contentsLength = lineContentsLength(for: lineRange, in: nsSource)
      let contentsRange = NSRange(location: lineRange.location, length: contentsLength)
      if let modeHeader,
        NSIntersectionRange(modeHeader.sourceRange, lineRange).length > 0
      {
        advance(&location, to: NSMaxRange(lineRange))
        continue
      }
      guard !fences.contains(where: { NSIntersectionRange($0.fullRange, lineRange).length > 0 })
      else {
        advance(&location, to: NSMaxRange(lineRange))
        continue
      }

      let line = nsSource.substring(with: contentsRange)
      if isComment(line) {
        if contentsRange.length > 0 {
          spans.append(SourceStyleSpan(range: contentsRange, role: .comment))
        }
        advance(&location, to: NSMaxRange(lineRange))
        continue
      }
      if let level = headingLevel(in: line) {
        spans.append(SourceStyleSpan(range: contentsRange, role: .heading(level: level)))
      }
      spans.append(contentsOf: inlineSpans(in: source, range: contentsRange))
      advance(&location, to: NSMaxRange(lineRange))
    }
    return spans
  }

  private func headingLevel(in line: String) -> Int? {
    guard
      let expression = try? NSRegularExpression(pattern: #"^[\t ]*(#{1,3})[\t ]+.+$"#),
      let match = expression.firstMatch(
        in: line,
        range: NSRange(location: 0, length: line.utf16.count)
      )
    else { return nil }
    return match.range(at: 1).length
  }

  private func isComment(_ line: String) -> Bool {
    line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//")
  }

  private func inlineSpans(in source: String, range: NSRange) -> [SourceStyleSpan] {
    let codeMatches = matches(
      pattern: #"(?<!`)`([^`\r\n]+)`(?!`)"#,
      in: source,
      range: range
    )
    var spans = codeMatches.map {
      SourceStyleSpan(range: $0.range(at: 1), role: .inlineCode)
    }
    let excluded = codeMatches.map(\.range)
    let patterns: [(String, SourceTextRole)] = [
      (#"(?<!\*)\*\*([^*\r\n]+)\*\*(?!\*)"#, .bold),
      (#"(?<!\*)\*([^*\r\n]+)\*(?!\*)"#, .italic),
      (#"(?<!~)~~([^~\r\n]+)~~(?!~)"#, .strikethrough),
      (#"(?<!_)__([^_\r\n]+)__(?!_)"#, .underline),
    ]
    for (pattern, role) in patterns {
      spans.append(
        contentsOf: matches(pattern: pattern, in: source, range: range).compactMap { match in
          guard !excluded.contains(where: { NSIntersectionRange($0, match.range).length > 0 })
          else { return nil }
          return SourceStyleSpan(range: match.range(at: 1), role: role)
        }
      )
    }
    return spans
  }

  private func matches(pattern: String, in source: String, range: NSRange)
    -> [NSTextCheckingResult]
  {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    return expression.matches(in: source, range: range)
  }

  private func lineContentsLength(for lineRange: NSRange, in source: NSString) -> Int {
    var start = 0
    var end = 0
    var contentsEnd = 0
    source.getLineStart(
      &start,
      end: &end,
      contentsEnd: &contentsEnd,
      for: NSRange(location: lineRange.location, length: 0)
    )
    return contentsEnd - start
  }

  private func advance(_ location: inout Int, to nextLocation: Int) {
    location = nextLocation > location ? nextLocation : location + 1
  }
}

public struct LineCommentEdit: Sendable, Equatable {
  public let range: NSRange
  public let replacement: String
  public let selection: NSRange
}

public struct LineCommentCommand: Sendable {
  public init() {}

  public func toggle(in source: String, selection: NSRange) -> LineCommentEdit? {
    let nsSource = source as NSString
    let boundedLocation = min(max(0, selection.location), nsSource.length)
    let boundedLength = min(max(0, selection.length), nsSource.length - boundedLocation)
    let boundedSelection = NSRange(location: boundedLocation, length: boundedLength)
    let affectedRange = selectedLineRange(in: nsSource, selection: boundedSelection)
    let descriptors = lines(in: nsSource, range: affectedRange)
    let eligible = descriptors.filter {
      boundedSelection.length == 0 || !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
    }
    guard !eligible.isEmpty else { return nil }
    let removesComments = eligible.allSatisfy { commentMarker(in: $0.text) != nil }

    var replacement = ""
    var changes: [OffsetChange] = []
    for line in descriptors {
      let lineEnding = nsSource.substring(
        with: NSRange(
          location: NSMaxRange(line.contentsRange),
          length: NSMaxRange(line.lineRange) - NSMaxRange(line.contentsRange)
        )
      )
      let isEligible = eligible.contains(where: { $0.lineRange == line.lineRange })
      if removesComments, isEligible, let marker = commentMarker(in: line.text) {
        let absolute = line.contentsRange.location + marker.location
        changes.append(OffsetChange(location: absolute, oldLength: marker.length, newLength: 0))
        replacement += (line.text as NSString).replacingCharacters(in: marker, with: "")
      } else if !removesComments, isEligible {
        let indentation = line.text.prefix(while: { $0 == " " || $0 == "\t" })
        let insertion = indentation.utf16.count
        changes.append(
          OffsetChange(
            location: line.contentsRange.location + insertion,
            oldLength: 0,
            newLength: 3
          )
        )
        let mutable = NSMutableString(string: line.text)
        mutable.insert("// ", at: insertion)
        replacement += mutable as String
      } else {
        replacement += line.text
      }
      replacement += lineEnding
    }

    let transformedSelection = mappedSelection(boundedSelection, through: changes)
    return LineCommentEdit(
      range: affectedRange,
      replacement: replacement,
      selection: transformedSelection
    )
  }

  private struct LineDescriptor: Equatable {
    let lineRange: NSRange
    let contentsRange: NSRange
    let text: String
  }

  private struct OffsetChange {
    let location: Int
    let oldLength: Int
    let newLength: Int
  }

  private func selectedLineRange(in source: NSString, selection: NSRange) -> NSRange {
    if source.length == 0 {
      return NSRange(location: 0, length: 0)
    }
    if selection.length == 0, selection.location == source.length {
      return source.lineRange(for: selection)
    }
    let startProbe = min(selection.location, source.length - 1)
    let endProbe: Int
    if selection.length == 0 {
      endProbe = startProbe
    } else {
      endProbe = min(NSMaxRange(selection) - 1, source.length - 1)
    }
    let startLine = source.lineRange(for: NSRange(location: startProbe, length: 0))
    let endLine = source.lineRange(for: NSRange(location: endProbe, length: 0))
    return NSRange(
      location: startLine.location,
      length: NSMaxRange(endLine) - startLine.location
    )
  }

  private func lines(in source: NSString, range: NSRange) -> [LineDescriptor] {
    if source.length == 0 || range.length == 0 {
      return [LineDescriptor(lineRange: range, contentsRange: range, text: "")]
    }
    var descriptors: [LineDescriptor] = []
    var location = range.location
    while location < NSMaxRange(range) {
      var lineStart = 0
      var lineEnd = 0
      var contentsEnd = 0
      source.getLineStart(
        &lineStart,
        end: &lineEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0)
      )
      let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
      let contentsRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
      descriptors.append(
        LineDescriptor(
          lineRange: lineRange,
          contentsRange: contentsRange,
          text: source.substring(with: contentsRange)
        )
      )
      let next = NSMaxRange(lineRange)
      guard next > location else { break }
      location = next
    }
    return descriptors
  }

  private func commentMarker(in line: String) -> NSRange? {
    let indentation = line.prefix(while: { $0 == " " || $0 == "\t" }).utf16.count
    let nsLine = line as NSString
    guard nsLine.length >= indentation + 2,
      nsLine.substring(with: NSRange(location: indentation, length: 2)) == "//"
    else { return nil }
    let trailingSpace =
      nsLine.length > indentation + 2
      && nsLine.substring(with: NSRange(location: indentation + 2, length: 1)) == " "
    return NSRange(location: indentation, length: trailingSpace ? 3 : 2)
  }

  private func mappedSelection(_ selection: NSRange, through changes: [OffsetChange]) -> NSRange {
    if selection.length == 0 {
      let location = mappedOffset(
        selection.location, through: changes, includesEqualInsertion: true)
      return NSRange(location: location, length: 0)
    }
    let start = mappedOffset(selection.location, through: changes, includesEqualInsertion: false)
    let end = mappedOffset(NSMaxRange(selection), through: changes, includesEqualInsertion: true)
    return NSRange(location: start, length: max(0, end - start))
  }

  private func mappedOffset(
    _ offset: Int,
    through changes: [OffsetChange],
    includesEqualInsertion: Bool
  ) -> Int {
    var delta = 0
    for change in changes.sorted(by: { $0.location < $1.location }) {
      if change.oldLength == 0 {
        if change.location < offset || (includesEqualInsertion && change.location == offset) {
          delta += change.newLength
        }
        continue
      }
      let upperBound = change.location + change.oldLength
      if offset >= upperBound {
        delta += change.newLength - change.oldLength
      } else if offset > change.location {
        return change.location + delta + min(offset - change.location, change.newLength)
      }
    }
    return offset + delta
  }
}
