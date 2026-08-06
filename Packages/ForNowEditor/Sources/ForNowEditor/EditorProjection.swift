import ForNowCore
import ForNowModes
import Foundation

public struct LinkPresentation: Sendable, Equatable {
  public let originalURL: String
  public let displayText: String
  public let duplicateIndex: Int
  public let identity: LinkIdentity

  public init(originalURL: String, displayText: String, duplicateIndex: Int) {
    self.init(
      originalURL: originalURL,
      displayText: displayText,
      duplicateIndex: duplicateIndex,
      identity: LinkIdentity(originalURL: originalURL, occurrenceIndex: duplicateIndex)
    )
  }

  public init(
    originalURL: String,
    displayText: String,
    duplicateIndex: Int,
    identity: LinkIdentity
  ) {
    self.originalURL = originalURL
    self.displayText = displayText
    self.duplicateIndex = duplicateIndex
    self.identity = identity
  }
}

public struct CalculationPresentation: Sendable, Equatable {
  public let expressionText: String?
  public let canonicalValue: String
  public let displayText: String
  public let copiedText: String
  public let dependencyIDs: [String]

  public init(
    expressionText: String? = nil,
    canonicalValue: String,
    displayText: String,
    copiedText: String? = nil,
    dependencyIDs: [String] = []
  ) {
    self.expressionText = expressionText
    self.canonicalValue = canonicalValue
    self.displayText = displayText
    self.copiedText = copiedText ?? canonicalValue
    self.dependencyIDs = dependencyIDs
  }
}

public struct TimerPresentation: Sendable, Equatable {
  public let command: TimerCommand
  public let matchedAlias: String
  public let sourceRange: SourceRange
  public let showsTutorial: Bool

  public init(
    command: TimerCommand,
    matchedAlias: String,
    sourceRange: SourceRange,
    showsTutorial: Bool
  ) {
    self.command = command
    self.matchedAlias = matchedAlias
    self.sourceRange = sourceRange
    self.showsTutorial = showsTutorial
  }
}

public enum ProjectionDiagnosticSeverity: String, Sendable, Equatable {
  case information
  case warning
  case error
}

public struct ProjectionDiagnostic: Sendable, Equatable {
  public let code: String
  public let severity: ProjectionDiagnosticSeverity
  public let sourceRange: SourceRange?
  public let message: String

  public init(
    code: String,
    severity: ProjectionDiagnosticSeverity,
    sourceRange: SourceRange? = nil,
    message: String
  ) {
    self.code = code
    self.severity = severity
    self.sourceRange = sourceRange
    self.message = message
  }
}

public enum EditorDecoration: Sendable, Equatable {
  case style(range: SourceRange, style: TextStyle)
  case checkbox(range: SourceRange, markerRange: SourceRange?, isChecked: Bool)
  case link(range: SourceRange, presentation: LinkPresentation)
  case result(anchor: SourceOffset, presentation: CalculationPresentation)
  case timer(anchor: SourceOffset, presentation: TimerPresentation)

  public var sourceRange: SourceRange? {
    switch self {
    case .style(let range, _), .checkbox(let range, _, _), .link(let range, _):
      range
    case .result:
      nil
    case .timer(_, let presentation):
      presentation.sourceRange
    }
  }
}

public struct EditorProjection: Sendable, Equatable {
  public let sourceVersion: UInt64
  public let decorations: [EditorDecoration]
  public let diagnostics: [ProjectionDiagnostic]

  public init(
    sourceVersion: UInt64,
    decorations: [EditorDecoration],
    diagnostics: [ProjectionDiagnostic] = []
  ) {
    self.sourceVersion = sourceVersion
    self.decorations = decorations
    self.diagnostics = diagnostics
  }
}

public struct ProjectionGate: Sendable {
  public init() {}

  public func accepts(_ projection: EditorProjection, for snapshot: SourceSnapshot) -> Bool {
    projection.sourceVersion == snapshot.version
  }
}

public struct SpikeProjectionParser: Sendable {
  private let editorSettings: EditorSettings
  private let modeSettings: ModeSettings
  private let mathSettings: MathSettings
  private let mathLocale: MathDecimalLocale
  private let conversionCatalogs: ConversionCatalogs
  private let currencyContext: CurrencyConversionContext
  private let syntaxHighlighter: any CodeSyntaxHighlighting

  public init(
    editorSettings: EditorSettings = EditorSettings(),
    modeSettings: ModeSettings = ModeSettings(),
    mathSettings: MathSettings = MathSettings(),
    mathLocale: MathDecimalLocale = MathDecimalLocale(),
    conversionCatalogs: ConversionCatalogs = .bundled,
    currencyContext: CurrencyConversionContext = CurrencyConversionContext(),
    syntaxHighlighter: any CodeSyntaxHighlighting = BuiltInCodeSyntaxHighlighter()
  ) {
    self.editorSettings = editorSettings
    self.modeSettings = modeSettings
    self.mathSettings = mathSettings
    self.mathLocale = mathLocale
    self.conversionCatalogs = conversionCatalogs
    self.currencyContext = currencyContext
    self.syntaxHighlighter = syntaxHighlighter
  }

  public func parse(_ snapshot: SourceSnapshot) -> EditorProjection {
    // The spike API remains synchronous for deterministic source-model tests.
    // Production uses parseCancellable(_:) through ProjectionParsePipeline.
    return (try? parse(snapshot, checksCancellation: false))
      ?? EditorProjection(sourceVersion: snapshot.version, decorations: [])
  }

  public func parseCancellable(_ snapshot: SourceSnapshot) throws -> EditorProjection {
    try parse(snapshot, checksCancellation: true)
  }

  private func parse(
    _ snapshot: SourceSnapshot,
    checksCancellation: Bool
  ) throws -> EditorProjection {
    try checkCancellation(if: checksCancellation)
    var decorations = try styleDecorations(
      in: snapshot.text,
      checksCancellation: checksCancellation
    )
    try checkCancellation(if: checksCancellation)
    decorations.append(
      contentsOf: try checkboxDecorations(
        in: snapshot.text,
        checksCancellation: checksCancellation
      ))
    try checkCancellation(if: checksCancellation)
    decorations.append(
      contentsOf: try linkDecorations(
        in: snapshot.text,
        checksCancellation: checksCancellation
      )
    )
    try checkCancellation(if: checksCancellation)
    let mathProjection = try mathProjection(
      in: snapshot.text,
      checksCancellation: checksCancellation
    )
    decorations.append(contentsOf: mathProjection.decorations)
    try checkCancellation(if: checksCancellation)
    let aggregateProjection = try aggregateProjection(
      in: snapshot.text,
      checksCancellation: checksCancellation
    )
    decorations.append(contentsOf: aggregateProjection.decorations)
    try checkCancellation(if: checksCancellation)
    let timerProjection = try timerProjection(
      in: snapshot.text,
      checksCancellation: checksCancellation
    )
    decorations.append(contentsOf: timerProjection.decorations)
    try checkCancellation(if: checksCancellation)
    return EditorProjection(
      sourceVersion: snapshot.version,
      decorations: decorations,
      diagnostics: mathProjection.diagnostics + aggregateProjection.diagnostics
        + timerProjection.diagnostics
    )
  }

  private func styleDecorations(
    in text: String,
    checksCancellation: Bool
  ) throws -> [EditorDecoration] {
    let spans = LimitedMarkdownParser().parse(
      text,
      defaultCodeLanguage: editorSettings.defaultCodeLanguage,
      modeSettings: modeSettings
    )
    var decorations = spans.map {
      EditorDecoration.style(range: SourceRange($0.range), style: TextStyle($0.role))
    }
    for (index, span) in spans.enumerated() {
      if index.isMultiple(of: 32) {
        try checkCancellation(if: checksCancellation)
      }
      guard case .codeBlock(let language) = span.role, language != .plainText else { continue }
      decorations.append(
        contentsOf: syntaxHighlighter.highlights(
          in: text,
          range: SourceRange(span.range),
          language: language
        ).map { highlight in
          .style(range: highlight.range, style: .syntax(highlight.kind))
        }
      )
    }
    return decorations
  }

  private func checkboxDecorations(
    in text: String,
    checksCancellation: Bool
  ) throws -> [EditorDecoration] {
    var decorations: [EditorDecoration] = []
    for (index, item) in ListModeParser(settings: modeSettings).parse(in: text).enumerated() {
      if index.isMultiple(of: 32) {
        try checkCancellation(if: checksCancellation)
      }
      decorations.append(
        .checkbox(
          range: SourceRange(item.lineRange),
          markerRange: item.markerRange.map(SourceRange.init),
          isChecked: item.isChecked
        )
      )
    }
    return decorations
  }

  private func linkDecorations(
    in text: String,
    checksCancellation: Bool
  ) throws -> [EditorDecoration] {
    guard editorSettings.hyperlinkFeaturesEnabled else { return [] }
    let codePolicy = LinkCodeContextPolicy()
    guard !codePolicy.excludesAllLinks(in: text, modeSettings: modeSettings) else { return [] }
    guard
      let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
      )
    else { return [] }

    let excludedRanges = codePolicy.fencedCodeRanges(in: text)
    let validator = HTTPLinkValidator()
    var duplicateCounts: [String: Int] = [:]
    var decorations: [EditorDecoration] = []
    var wasCancelled = false
    detector.enumerateMatches(
      in: text,
      options: [],
      range: NSRange(location: 0, length: text.utf16.count)
    ) { match, _, stop in
      if checksCancellation, Task.isCancelled {
        wasCancelled = true
        stop.pointee = true
        return
      }
      guard let match,
        !excludedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 })
      else { return }
      let originalURL = (text as NSString).substring(with: match.range)
      guard let url = validator.validatedURL(from: originalURL) else { return }
      let duplicateIndex = (duplicateCounts[originalURL] ?? 0) + 1
      duplicateCounts[originalURL] = duplicateIndex
      let host = url.host(percentEncoded: false) ?? url.host ?? originalURL
      let port = url.port.map { ":\($0)" } ?? ""
      let hasTail =
        !(url.path.isEmpty || url.path == "/") || url.query != nil || url.fragment != nil
      let pathHint = hasTail ? "/..." : ""
      let duplicateSuffix = duplicateIndex > 1 ? " · \(duplicateIndex)" : ""
      let presentation = LinkPresentation(
        originalURL: originalURL,
        displayText: "\(host)\(port)\(pathHint)\(duplicateSuffix)",
        duplicateIndex: duplicateIndex,
        identity: LinkIdentity(originalURL: originalURL, occurrenceIndex: duplicateIndex)
      )
      decorations.append(.link(range: SourceRange(match.range), presentation: presentation))
    }
    if wasCancelled {
      throw CancellationError()
    }
    return decorations
  }

  private func mathProjection(
    in text: String,
    checksCancellation: Bool
  ) throws -> (decorations: [EditorDecoration], diagnostics: [ProjectionDiagnostic]) {
    let evaluations: [BasicMathLineEvaluation]
    let parser = BasicMathDocumentParser(
      mathSettings: mathSettings,
      modeSettings: modeSettings,
      locale: mathLocale,
      conversionCatalogs: conversionCatalogs,
      currencyContext: currencyContext
    )
    if checksCancellation {
      evaluations = try parser.parseCancellable(in: text)
    } else {
      evaluations = parser.parse(in: text)
    }
    var decorations: [EditorDecoration] = []
    var diagnostics: [ProjectionDiagnostic] = []
    for (index, evaluation) in evaluations.enumerated() {
      if index.isMultiple(of: 32) {
        try checkCancellation(if: checksCancellation)
      }
      switch evaluation {
      case .result(let result):
        decorations.append(
          .result(
            anchor: SourceOffset(utf16Offset: result.anchorUTF16Offset),
            presentation: CalculationPresentation(
              expressionText: (text as NSString).substring(with: result.expressionRange),
              canonicalValue: result.canonicalValue,
              displayText: result.displayText,
              copiedText: result.copiedText,
              dependencyIDs: result.dependencyIDs
            )
          )
        )
      case .diagnostic(let diagnostic):
        diagnostics.append(
          ProjectionDiagnostic(
            code: diagnostic.code.rawValue,
            severity: .error,
            sourceRange: SourceRange(diagnostic.sourceRange),
            message: diagnostic.message
          )
        )
      }
    }
    return (decorations, diagnostics)
  }

  private func aggregateProjection(
    in text: String,
    checksCancellation: Bool
  ) throws -> (decorations: [EditorDecoration], diagnostics: [ProjectionDiagnostic]) {
    let parser = AggregateDocumentParser(
      mathSettings: mathSettings,
      modeSettings: modeSettings,
      locale: mathLocale
    )
    let evaluation: AggregateDocumentEvaluation?
    if checksCancellation {
      evaluation = try parser.parseCancellable(in: text)
    } else {
      evaluation = parser.parse(in: text)
    }
    guard let evaluation else { return ([], []) }

    let decorations =
      evaluation.result.map { result in
        [
          EditorDecoration.result(
            anchor: SourceOffset(utf16Offset: result.anchorUTF16Offset),
            presentation: CalculationPresentation(
              expressionText: result.modeID.displayName,
              canonicalValue: result.canonicalValue,
              displayText: result.displayText,
              copiedText: result.copiedText
            )
          )
        ]
      } ?? []
    let diagnostics = evaluation.diagnostics.map { diagnostic in
      ProjectionDiagnostic(
        code: diagnostic.code.rawValue,
        severity: .error,
        sourceRange: SourceRange(diagnostic.sourceRange),
        message: diagnostic.message
      )
    }
    return (decorations, diagnostics)
  }

  private func timerProjection(
    in text: String,
    checksCancellation: Bool
  ) throws -> (decorations: [EditorDecoration], diagnostics: [ProjectionDiagnostic]) {
    let parser = TimerCommandParser(settings: modeSettings)
    let document =
      checksCancellation
      ? try parser.parseCancellable(in: text)
      : parser.parse(in: text)
    let decorations = document.commands.map { match in
      EditorDecoration.timer(
        anchor: SourceOffset(utf16Offset: match.anchorUTF16Offset),
        presentation: TimerPresentation(
          command: match.command,
          matchedAlias: match.matchedAlias,
          sourceRange: SourceRange(match.sourceRange),
          showsTutorial: match.showsTutorial
        )
      )
    }
    let diagnostics = document.diagnostics.map { diagnostic in
      ProjectionDiagnostic(
        code: diagnostic.code.rawValue,
        severity: .error,
        sourceRange: SourceRange(diagnostic.sourceRange),
        message: diagnostic.message
      )
    }
    return (decorations, diagnostics)
  }

  private func enumerateLineRanges(
    in source: NSString,
    checksCancellation: Bool,
    body: (NSRange) -> Void
  ) throws {
    var location = 0
    var lineIndex = 0
    while location < source.length {
      if lineIndex.isMultiple(of: 32) {
        try checkCancellation(if: checksCancellation)
      }
      let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
      body(lineRange)
      let nextLocation = NSMaxRange(lineRange)
      guard nextLocation > location else { break }
      location = nextLocation
      lineIndex += 1
    }
  }

  private func checkCancellation(if enabled: Bool) throws {
    if enabled {
      try Task.checkCancellation()
    }
  }
}
