import AppKit
import Foundation

public enum FindMatchMode: String, CaseIterable, Sendable {
  case contains
  case wholeWord
  case linePrefix
  case lineSuffix
  case regularExpression

  public var displayName: String {
    switch self {
    case .contains:
      "Contains"
    case .wholeWord:
      "Whole Word"
    case .linePrefix:
      "Line Prefix"
    case .lineSuffix:
      "Line Suffix"
    case .regularExpression:
      "Regular Expression"
    }
  }
}

public struct FindRequest: Sendable, Equatable {
  public var query: String
  public var mode: FindMatchMode
  public var isCaseSensitive: Bool

  public init(
    query: String,
    mode: FindMatchMode = .contains,
    isCaseSensitive: Bool = false
  ) {
    self.query = query
    self.mode = mode
    self.isCaseSensitive = isCaseSensitive
  }
}

public struct FindSourceMatch: Sendable, Equatable {
  public let range: SourceRange

  public init(range: SourceRange) {
    self.range = range
  }
}

public struct FindReplaceAllPlan: Sendable, Equatable {
  public let expectedSource: String
  public let replacementSource: String
  public let replacementCount: Int

  public init(expectedSource: String, replacementSource: String, replacementCount: Int) {
    self.expectedSource = expectedSource
    self.replacementSource = replacementSource
    self.replacementCount = replacementCount
  }
}

public enum FindReplaceError: Error, LocalizedError, Sendable, Equatable {
  case invalidRegularExpression

  public var errorDescription: String? {
    switch self {
    case .invalidRegularExpression:
      "Invalid regular expression."
    }
  }
}

public struct FindReplaceEngine: Sendable {
  public init() {}

  public func matches(in source: String, request: FindRequest) throws -> [FindSourceMatch] {
    guard !request.query.isEmpty else { return [] }
    switch request.mode {
    case .contains:
      return try regularExpressionMatches(
        pattern: NSRegularExpression.escapedPattern(for: request.query),
        in: source,
        isCaseSensitive: request.isCaseSensitive
      )
    case .wholeWord:
      let escaped = NSRegularExpression.escapedPattern(for: request.query)
      return try regularExpressionMatches(
        pattern: #"(?<![\p{L}\p{N}_])(?:"# + escaped + #")(?![\p{L}\p{N}_])"#,
        in: source,
        isCaseSensitive: request.isCaseSensitive
      )
    case .linePrefix:
      return lineMatches(in: source, query: request.query, atPrefix: true, request: request)
    case .lineSuffix:
      return lineMatches(in: source, query: request.query, atPrefix: false, request: request)
    case .regularExpression:
      return try regularExpressionMatches(
        pattern: request.query,
        in: source,
        isCaseSensitive: request.isCaseSensitive
      )
    }
  }

  public func replacingAll(
    in source: String,
    request: FindRequest,
    replacement: String
  ) throws -> FindReplaceAllPlan {
    let matches = try matches(in: source, request: request)
    guard !matches.isEmpty else {
      return FindReplaceAllPlan(
        expectedSource: source,
        replacementSource: source,
        replacementCount: 0
      )
    }

    let result = NSMutableString(string: source)
    for match in matches.reversed() {
      result.replaceCharacters(in: match.range.nsRange, with: replacement)
    }
    return FindReplaceAllPlan(
      expectedSource: source,
      replacementSource: result as String,
      replacementCount: matches.count
    )
  }

  private func regularExpressionMatches(
    pattern: String,
    in source: String,
    isCaseSensitive: Bool
  ) throws -> [FindSourceMatch] {
    var options: NSRegularExpression.Options = [.anchorsMatchLines]
    if !isCaseSensitive {
      options.insert(.caseInsensitive)
    }
    let expression: NSRegularExpression
    do {
      expression = try NSRegularExpression(pattern: pattern, options: options)
    } catch {
      throw FindReplaceError.invalidRegularExpression
    }
    let fullRange = NSRange(location: 0, length: source.utf16.count)
    return expression.matches(in: source, range: fullRange).compactMap { match in
      guard match.range.location != NSNotFound else { return nil }
      return FindSourceMatch(range: SourceRange(match.range))
    }
  }

  private func lineMatches(
    in source: String,
    query: String,
    atPrefix: Bool,
    request: FindRequest
  ) -> [FindSourceMatch] {
    let nsSource = source as NSString
    let queryLength = query.utf16.count
    let compareOptions: NSString.CompareOptions = request.isCaseSensitive ? [] : [.caseInsensitive]
    var location = 0
    var matches: [FindSourceMatch] = []

    while location < nsSource.length {
      var lineStart = 0
      var lineEnd = 0
      var contentsEnd = 0
      nsSource.getLineStart(
        &lineStart,
        end: &lineEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0)
      )
      let contentsLength = contentsEnd - lineStart
      if queryLength <= contentsLength {
        let matchLocation = atPrefix ? lineStart : contentsEnd - queryLength
        let candidateRange = NSRange(location: matchLocation, length: queryLength)
        if nsSource.compare(query, options: compareOptions, range: candidateRange) == .orderedSame {
          matches.append(FindSourceMatch(range: SourceRange(candidateRange)))
        }
      }
      guard lineEnd > location else { break }
      location = lineEnd
    }
    return matches
  }
}

@MainActor
public final class EditorFindReplaceTarget {
  public var sourceDidChange: (@MainActor () -> Void)?

  private weak var container: ProjectionEditorContainer?
  private var temporarilyExpandsLinks = false

  public init() {}

  public var source: String {
    container?.textView.string ?? ""
  }

  public var selectedRange: NSRange {
    container?.textView.selectedRange() ?? NSRange(location: 0, length: 0)
  }

  public func attach(to container: ProjectionEditorContainer) {
    guard self.container !== container else { return }
    self.container?.temporarilyExpandsLinks = false
    self.container = container
    container.temporarilyExpandsLinks = temporarilyExpandsLinks
  }

  public func setTemporarilyExpandsLinks(_ expands: Bool) {
    guard temporarilyExpandsLinks != expands else { return }
    temporarilyExpandsLinks = expands
    container?.temporarilyExpandsLinks = expands
  }

  public func notifySourceDidChange() {
    sourceDidChange?()
  }

  public func sourceText(in range: NSRange) -> String? {
    let source = self.source as NSString
    guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= source.length else {
      return nil
    }
    return source.substring(with: range)
  }

  public func select(_ range: SourceRange) {
    guard let container else { return }
    let sourceLength = container.textView.string.utf16.count
    let boundedLocation = min(max(0, range.location.utf16Offset), sourceLength)
    let boundedLength = min(max(0, range.length), sourceLength - boundedLocation)
    let selection = NSRange(location: boundedLocation, length: boundedLength)
    container.textView.setSelectedRange(selection)
    container.textView.scrollRangeToVisible(selection)
  }

  @discardableResult
  public func replace(
    expectedSource: String,
    range: SourceRange,
    replacement: String
  ) -> Bool {
    guard let container,
      !container.textView.hasMarkedText(),
      container.textView.string == expectedSource,
      range.location.utf16Offset >= 0,
      range.upperBound <= expectedSource.utf16.count
    else { return false }
    container.textView.insertText(replacement, replacementRange: range.nsRange)
    let selection = NSRange(
      location: range.location.utf16Offset + replacement.utf16.count,
      length: 0
    )
    container.textView.setSelectedRange(selection)
    container.textView.scrollRangeToVisible(selection)
    return true
  }

  @discardableResult
  public func replaceAll(with plan: FindReplaceAllPlan) -> Bool {
    guard let container,
      !container.textView.hasMarkedText(),
      container.textView.string == plan.expectedSource,
      plan.replacementCount > 0
    else { return false }
    let previousSelection = container.textView.selectedRange()
    container.textView.insertText(
      plan.replacementSource,
      replacementRange: NSRange(location: 0, length: plan.expectedSource.utf16.count)
    )
    let location = min(previousSelection.location, plan.replacementSource.utf16.count)
    container.textView.setSelectedRange(NSRange(location: location, length: 0))
    return true
  }
}
