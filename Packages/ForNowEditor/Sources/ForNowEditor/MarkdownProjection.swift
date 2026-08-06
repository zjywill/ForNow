import ForNowModes
import Foundation

public typealias CodeLanguage = ForNowModes.CodeLanguage
public typealias CodeModeHeader = ForNowModes.CodeModeHeader
public typealias CodeModeHeaderParser = ForNowModes.CodeModeHeaderParser

public enum CodeHighlightTheme: String, CaseIterable, Codable, Sendable {
  case adaptive
  case classic
  case midnight

  public var displayName: String {
    switch self {
    case .adaptive:
      "Adaptive"
    case .classic:
      "Classic"
    case .midnight:
      "Midnight"
    }
  }
}

public enum CodeSyntaxTokenKind: String, Codable, Sendable {
  case keyword
  case string
  case comment
  case number
}

public enum TextStyle: Sendable, Equatable {
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
  case syntax(CodeSyntaxTokenKind)

  init(_ role: SourceTextRole) {
    switch role {
    case .heading(let level):
      self = .heading(level: level)
    case .bold:
      self = .bold
    case .italic:
      self = .italic
    case .strikethrough:
      self = .strikethrough
    case .underline:
      self = .underline
    case .inlineCode:
      self = .inlineCode
    case .codeFence:
      self = .codeFence
    case .codeBlock(let language):
      self = .codeBlock(language: language)
    case .comment:
      self = .comment
    case .modeHeader:
      self = .modeHeader
    }
  }
}

public struct CodeSyntaxHighlight: Sendable, Equatable {
  public let range: SourceRange
  public let kind: CodeSyntaxTokenKind

  public init(range: SourceRange, kind: CodeSyntaxTokenKind) {
    self.range = range
    self.kind = kind
  }
}

public protocol CodeSyntaxHighlighting: Sendable {
  func highlights(
    in source: String,
    range: SourceRange,
    language: CodeLanguage
  ) -> [CodeSyntaxHighlight]
}

public struct BuiltInCodeSyntaxHighlighter: CodeSyntaxHighlighting, Sendable {
  public init() {}

  public func highlights(
    in source: String,
    range: SourceRange,
    language: CodeLanguage
  ) -> [CodeSyntaxHighlight] {
    guard language != .plainText,
      range.location.utf16Offset >= 0,
      range.upperBound <= source.utf16.count
    else { return [] }

    let searchRange = range.nsRange
    var highlights: [CodeSyntaxHighlight] = []
    var occupied: [NSRange] = []

    appendMatches(
      pattern: stringPattern(for: language),
      kind: .string,
      source: source,
      searchRange: searchRange,
      occupied: &occupied,
      highlights: &highlights
    )
    if let commentPattern = commentPattern(for: language) {
      appendCommentMatches(
        pattern: commentPattern,
        source: source,
        searchRange: searchRange,
        occupied: &occupied,
        highlights: &highlights
      )
    }
    appendMatches(
      pattern: #"(?<![\p{L}\p{N}_])(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)(?![\p{L}\p{N}_])"#,
      kind: .number,
      source: source,
      searchRange: searchRange,
      occupied: &occupied,
      highlights: &highlights
    )
    let keywords = keywords(for: language)
    if !keywords.isEmpty {
      let alternatives = keywords.map(NSRegularExpression.escapedPattern(for:)).joined(
        separator: "|")
      appendMatches(
        pattern: #"(?<![\p{L}\p{N}_])(?:"# + alternatives + #")(?![\p{L}\p{N}_])"#,
        kind: .keyword,
        source: source,
        searchRange: searchRange,
        occupied: &occupied,
        highlights: &highlights
      )
    }
    return highlights.sorted { lhs, rhs in
      lhs.range.location.utf16Offset < rhs.range.location.utf16Offset
    }
  }

  private func appendMatches(
    pattern: String,
    kind: CodeSyntaxTokenKind,
    source: String,
    searchRange: NSRange,
    occupied: inout [NSRange],
    highlights: inout [CodeSyntaxHighlight]
  ) {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    else { return }
    for match in expression.matches(in: source, range: searchRange) {
      guard !occupied.contains(where: { NSIntersectionRange($0, match.range).length > 0 })
      else { continue }
      occupied.append(match.range)
      highlights.append(
        CodeSyntaxHighlight(range: SourceRange(match.range), kind: kind)
      )
    }
  }

  private func appendCommentMatches(
    pattern: String,
    source: String,
    searchRange: NSRange,
    occupied: inout [NSRange],
    highlights: inout [CodeSyntaxHighlight]
  ) {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    else { return }
    for match in expression.matches(in: source, range: searchRange) {
      if occupied.contains(where: { NSLocationInRange(match.range.location, $0) }) {
        continue
      }
      let superseded = Set(
        occupied.filter { NSIntersectionRange($0, match.range).length > 0 }
      )
      if !superseded.isEmpty {
        occupied.removeAll { superseded.contains($0) }
        highlights.removeAll { superseded.contains($0.range.nsRange) }
      }
      occupied.append(match.range)
      highlights.append(
        CodeSyntaxHighlight(range: SourceRange(match.range), kind: .comment)
      )
    }
  }

  private func stringPattern(for language: CodeLanguage) -> String {
    switch language {
    case .json:
      #"\"(?:\\.|[^\"\\])*\""#
    case .plainText:
      #"(?!)"#
    default:
      #"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'"#
    }
  }

  private func commentPattern(for language: CodeLanguage) -> String? {
    switch language {
    case .swift, .javascript, .typescript:
      #"//[^\r\n]*"#
    case .python, .shell:
      #"#[^\r\n]*"#
    case .plainText, .json:
      nil
    }
  }

  private func keywords(for language: CodeLanguage) -> [String] {
    switch language {
    case .plainText:
      []
    case .swift:
      [
        "actor", "async", "await", "case", "class", "else", "enum", "extension", "false",
        "for", "func", "guard", "if", "import", "in", "let", "nil", "private", "protocol",
        "public", "return", "self", "struct", "switch", "throw", "throws", "true", "try",
        "var", "while",
      ]
    case .python:
      [
        "and", "async", "await", "break", "class", "continue", "def", "elif", "else",
        "except", "False", "finally", "for", "from", "if", "import", "in", "is", "lambda",
        "None", "not", "or", "pass", "raise", "return", "True", "try", "while", "with",
        "yield",
      ]
    case .javascript, .typescript:
      [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "default",
        "else", "export", "extends", "false", "for", "function", "if", "import", "interface",
        "let", "new", "null", "return", "switch", "throw", "true", "try", "type", "typeof",
        "undefined", "var", "while",
      ]
    case .json:
      ["false", "null", "true"]
    case .shell:
      [
        "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function",
        "if", "in", "local", "then", "while",
      ]
    }
  }
}

public struct LineCommentToggleResult: Sendable, Equatable {
  public let edit: SourceEdit
  public let selection: SourceSelection
}

public struct LineCommentToggler: Sendable {
  public init() {}

  public func toggle(
    in snapshot: SourceSnapshot,
    selection: SourceSelection
  ) -> LineCommentToggleResult? {
    let clamped = snapshot.clamped(selection)
    guard
      let result = LineCommentCommand().toggle(
        in: snapshot.text,
        selection: clamped.range.nsRange
      )
    else { return nil }
    return LineCommentToggleResult(
      edit: SourceEdit(range: SourceRange(result.range), replacement: result.replacement),
      selection: SourceSelection(range: SourceRange(result.selection))
    )
  }
}

public struct EditorCodeContextPolicy: Sendable {
  public init() {}

  public func isCodeContext(
    in snapshot: SourceSnapshot,
    selection: SourceSelection,
    defaultLanguage: CodeLanguage = .plainText,
    modeSettings: ModeSettings = ModeSettings()
  ) -> Bool {
    CodeContextParser().isCodeContext(
      in: snapshot.text,
      selection: snapshot.clamped(selection).range.nsRange,
      defaultLanguage: defaultLanguage,
      modeSettings: modeSettings
    )
  }
}
