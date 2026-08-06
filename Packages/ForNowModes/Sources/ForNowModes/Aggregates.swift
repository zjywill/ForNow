import Foundation

public enum AggregateDiagnosticCode: String, Codable, Sendable, Equatable {
  case fractionUnsupported = "aggregate-fraction-unsupported"
  case invalidNumber = "aggregate-invalid-number"
  case noValues = "aggregate-no-values"
  case overflow = "aggregate-overflow"
  case resourceLimit = "aggregate-resource-limit"
}

public struct AggregateDiagnostic: Error, Sendable, Equatable {
  public let code: AggregateDiagnosticCode
  public let sourceRange: NSRange
  public let message: String

  public init(code: AggregateDiagnosticCode, sourceRange: NSRange, message: String) {
    self.code = code
    self.sourceRange = sourceRange
    self.message = message
  }
}

extension AggregateDiagnostic: LocalizedError {
  public var errorDescription: String? { message }
}

public struct AggregateResult: Sendable, Equatable {
  public let modeID: ModeID
  public let anchorUTF16Offset: Int
  public let canonicalValue: String
  public let displayText: String
  public let copiedText: String
  public let consumedValueCount: Int

  public init(
    modeID: ModeID,
    anchorUTF16Offset: Int,
    canonicalValue: String,
    displayText: String,
    copiedText: String,
    consumedValueCount: Int
  ) {
    self.modeID = modeID
    self.anchorUTF16Offset = anchorUTF16Offset
    self.canonicalValue = canonicalValue
    self.displayText = displayText
    self.copiedText = copiedText
    self.consumedValueCount = consumedValueCount
  }
}

public struct AggregateDocumentEvaluation: Sendable, Equatable {
  public let result: AggregateResult?
  public let diagnostics: [AggregateDiagnostic]

  public init(result: AggregateResult?, diagnostics: [AggregateDiagnostic]) {
    self.result = result
    self.diagnostics = diagnostics
  }
}

public struct AggregateDocumentParser: Sendable {
  private static let maximumBodyLines = 10_000
  private static let maximumValues = 10_000

  private let mathSettings: MathSettings
  private let modeSettings: ModeSettings
  private let locale: MathDecimalLocale

  public init(
    mathSettings: MathSettings = MathSettings(),
    modeSettings: ModeSettings = ModeSettings(),
    locale: MathDecimalLocale = MathDecimalLocale()
  ) {
    self.mathSettings = (try? mathSettings.validated()) ?? MathSettings()
    self.modeSettings = modeSettings
    self.locale = locale
  }

  public func parse(in source: String) -> AggregateDocumentEvaluation? {
    try? parse(source, checksCancellation: false)
  }

  public func parseCancellable(in source: String) throws -> AggregateDocumentEvaluation? {
    try parse(source, checksCancellation: true)
  }

  private func parse(
    _ source: String,
    checksCancellation: Bool
  ) throws -> AggregateDocumentEvaluation? {
    guard
      let header = ModeHeaderParser(settings: modeSettings).parse(in: source),
      Self.aggregateModes.contains(header.modeID)
    else { return nil }

    let nsSource = source as NSString
    let bodyEnd = NSMaxRange(header.bodyRange)
    let extractor = AggregateNumberExtractor(locale: locale)
    var values: [Decimal] = []
    var count = 0
    var diagnostics: [AggregateDiagnostic] = []
    var location = header.bodyRange.location
    var lineIndex = 0

    while location < bodyEnd {
      if lineIndex.isMultiple(of: 32) {
        try checkCancellation(if: checksCancellation)
      }
      guard lineIndex < Self.maximumBodyLines else {
        diagnostics.append(
          diagnostic(
            .resourceLimit,
            range: header.sourceRange,
            message: "Aggregate modes support at most 10,000 body lines."
          )
        )
        return evaluation(result: nil, diagnostics: diagnostics)
      }

      var lineStart = 0
      var lineEnd = 0
      var contentsEnd = 0
      nsSource.getLineStart(
        &lineStart,
        end: &lineEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0)
      )
      let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
      let line = nsSource.substring(with: lineRange)
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if !trimmed.isEmpty, !trimmed.hasPrefix("//") {
        if header.modeID == .count {
          count += 1
        } else {
          switch try extractor.extract(
            from: line,
            maximumValues: Self.maximumValues - values.count,
            checksCancellation: checksCancellation
          ) {
          case .values(let extracted):
            values.append(contentsOf: extracted)
          case .fraction:
            diagnostics.append(
              diagnostic(
                .fractionUnsupported,
                range: lineRange,
                message: "Fractions are not supported in Sum or Average."
              )
            )
          case .invalidNumber:
            diagnostics.append(
              diagnostic(
                .invalidNumber,
                range: lineRange,
                message: "A number on this line does not match the active decimal locale."
              )
            )
          case .resourceLimit:
            diagnostics.append(
              diagnostic(
                .resourceLimit,
                range: lineRange,
                message: "Sum and Average support at most 10,000 numeric values."
              )
            )
            return evaluation(result: nil, diagnostics: diagnostics)
          }
        }
      }

      lineIndex += 1
      let nextLocation = min(lineEnd, bodyEnd)
      location = nextLocation > location ? nextLocation : location + 1
    }

    try checkCancellation(if: checksCancellation)
    switch header.modeID {
    case .count:
      return evaluation(
        result: result(modeID: .count, value: Decimal(count), count: count, header: header),
        diagnostics: diagnostics
      )
    case .sum:
      do {
        let sum = try aggregate(values)
        return evaluation(
          result: result(modeID: .sum, value: sum, count: values.count, header: header),
          diagnostics: diagnostics
        )
      } catch {
        diagnostics.append(
          diagnostic(
            .overflow,
            range: header.sourceRange,
            message: "The aggregate result exceeds Decimal range."
          )
        )
        return evaluation(result: nil, diagnostics: diagnostics)
      }
    case .average:
      guard !values.isEmpty else {
        diagnostics.append(
          diagnostic(
            .noValues,
            range: header.sourceRange,
            message: "Average needs at least one valid numeric value."
          )
        )
        return evaluation(result: nil, diagnostics: diagnostics)
      }
      do {
        let average = try divide(aggregate(values), by: Decimal(values.count))
        return evaluation(
          result: result(modeID: .average, value: average, count: values.count, header: header),
          diagnostics: diagnostics
        )
      } catch {
        diagnostics.append(
          diagnostic(
            .overflow,
            range: header.sourceRange,
            message: "The aggregate result exceeds Decimal range."
          )
        )
        return evaluation(result: nil, diagnostics: diagnostics)
      }
    default:
      return nil
    }
  }

  private static let aggregateModes: Set<ModeID> = [.sum, .average, .count]

  private func aggregate(_ values: [Decimal]) throws -> Decimal {
    var total = Decimal.zero
    for value in values {
      var left = total
      var right = value
      var next = Decimal()
      let error = NSDecimalAdd(&next, &left, &right, .bankers)
      guard error == .noError || error == .lossOfPrecision, !next.isNaN else {
        throw AggregateArithmeticError.outOfRange
      }
      total = next
    }
    return total
  }

  private func divide(_ value: Decimal, by divisor: Decimal) throws -> Decimal {
    var value = value
    var divisor = divisor
    var result = Decimal()
    let error = NSDecimalDivide(&result, &value, &divisor, .bankers)
    guard error == .noError || error == .lossOfPrecision, !result.isNaN else {
      throw AggregateArithmeticError.outOfRange
    }
    return result
  }

  private func result(
    modeID: ModeID,
    value: Decimal,
    count: Int,
    header: ModeHeader
  ) -> AggregateResult {
    let formatter = BasicMathFormatter(settings: mathSettings, locale: locale)
    let canonical = formatter.canonical(value)
    return AggregateResult(
      modeID: modeID,
      anchorUTF16Offset: NSMaxRange(header.sourceRange),
      canonicalValue: canonical,
      displayText: formatter.display(value),
      copiedText: canonical,
      consumedValueCount: count
    )
  }

  private func evaluation(
    result: AggregateResult?,
    diagnostics: [AggregateDiagnostic]
  ) -> AggregateDocumentEvaluation {
    AggregateDocumentEvaluation(
      result: result,
      diagnostics: diagnostics.enumerated().sorted { left, right in
        if left.element.sourceRange.location == right.element.sourceRange.location {
          return left.offset < right.offset
        }
        return left.element.sourceRange.location < right.element.sourceRange.location
      }.map(\.element)
    )
  }

  private func diagnostic(
    _ code: AggregateDiagnosticCode,
    range: NSRange,
    message: String
  ) -> AggregateDiagnostic {
    AggregateDiagnostic(code: code, sourceRange: range, message: message)
  }

  private func checkCancellation(if enabled: Bool) throws {
    if enabled {
      try Task.checkCancellation()
    }
  }
}

private enum AggregateArithmeticError: Error {
  case outOfRange
}

private enum AggregateExtraction {
  case values([Decimal])
  case fraction
  case invalidNumber
  case resourceLimit
}

private struct AggregateNumberExtractor {
  private static let posixLocale = Locale(identifier: "en_US_POSIX")
  private static let vulgarFractions = Set("¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞")
  private static let fractionExpression = try! NSRegularExpression(
    pattern: #"(?:[0-9][0-9.,]*|[.,][0-9]+)[\t ]*(?:/|⁄)[\t ]*(?:[0-9][0-9.,]*|[.,][0-9]+)"#
  )
  private static let scientificExpression = try! NSRegularExpression(
    pattern: #"[0-9][eE][+-]?[0-9]"#
  )

  let locale: MathDecimalLocale

  func extract(
    from line: String,
    maximumValues: Int,
    checksCancellation: Bool
  ) throws -> AggregateExtraction {
    let fullRange = NSRange(location: 0, length: line.utf16.count)
    if line.contains(where: Self.vulgarFractions.contains)
      || Self.fractionExpression.firstMatch(in: line, range: fullRange) != nil
    {
      return .fraction
    }
    if Self.scientificExpression.firstMatch(in: line, range: fullRange) != nil {
      return .invalidNumber
    }

    let source = line as NSString
    var values: [Decimal] = []
    var location = 0
    var scanStep = 0
    while location < source.length {
      if scanStep.isMultiple(of: 32), checksCancellation {
        try Task.checkCancellation()
      }
      scanStep += 1
      guard isCandidateStart(in: source, at: location) else {
        location += 1
        continue
      }

      let start = location
      if Self.isSign(source.character(at: location)) {
        location += 1
      }
      var candidateLength = location - start
      while location < source.length, Self.isNumericCandidate(source.character(at: location)) {
        if candidateLength.isMultiple(of: 32), checksCancellation {
          try Task.checkCancellation()
        }
        guard candidateLength < 128 else { return .invalidNumber }
        location += 1
        candidateLength += 1
      }
      let candidate = source.substring(with: NSRange(location: start, length: location - start))
      guard let normalized = normalizedCandidate(candidate) else { continue }
      guard let value = decimal(from: normalized) else { return .invalidNumber }
      guard values.count < maximumValues else { return .resourceLimit }
      values.append(value)
    }
    return .values(values)
  }

  private func isCandidateStart(in source: NSString, at location: Int) -> Bool {
    let character = source.character(at: location)
    if Self.isASCIIDigit(character) {
      return true
    }
    if Self.isSeparator(character) {
      return location + 1 < source.length && Self.isASCIIDigit(source.character(at: location + 1))
    }
    guard Self.isSign(character), location + 1 < source.length else { return false }
    let next = source.character(at: location + 1)
    if Self.isASCIIDigit(next) {
      return true
    }
    return Self.isSeparator(next)
      && location + 2 < source.length
      && Self.isASCIIDigit(source.character(at: location + 2))
  }

  private func normalizedCandidate(_ source: String) -> String? {
    let candidate = source as NSString
    var location = 0
    var sign = ""
    if candidate.length > 0, Self.isSign(candidate.character(at: 0)) {
      sign =
        candidate.character(at: 0) == 0x2212
        ? "-" : candidate.substring(with: NSRange(location: 0, length: 1))
      location = 1
    }

    var end = candidate.length
    while end > location, Self.isSeparator(candidate.character(at: end - 1)) {
      end -= 1
    }
    guard end > location else { return nil }

    var leadingSeparatorCount = 0
    while location + leadingSeparatorCount < end,
      Self.isSeparator(candidate.character(at: location + leadingSeparatorCount))
    {
      leadingSeparatorCount += 1
    }
    if leadingSeparatorCount == 1,
      candidate.substring(with: NSRange(location: location, length: 1)) == locale.decimalSeparator
    {
      // Preserve a single active leading decimal separator, such as `.5`.
    } else {
      location += leadingSeparatorCount
    }
    guard end > location else { return nil }
    return sign + candidate.substring(with: NSRange(location: location, length: end - location))
  }

  private func decimal(from source: String) -> Decimal? {
    let decimal = NSRegularExpression.escapedPattern(for: locale.decimalSeparator)
    let grouping = NSRegularExpression.escapedPattern(for: locale.groupingSeparator)
    let integer = #"(?:[0-9]{1,3}(?:"# + grouping + #"[0-9]{3})+|[0-9]+)"#
    let pattern =
      #"^[+-]?(?:"# + integer + #"(?:"# + decimal + #"[0-9]+)?|"#
      + decimal + #"[0-9]+)$"#
    guard source.range(of: pattern, options: .regularExpression) != nil else { return nil }
    let digitCount = source.unicodeScalars.count { (0x30...0x39).contains($0.value) }
    guard digitCount <= 38 else { return nil }
    let normalized =
      source
      .replacingOccurrences(of: locale.groupingSeparator, with: "")
      .replacingOccurrences(of: locale.decimalSeparator, with: ".")
    guard let value = Decimal(string: normalized, locale: Self.posixLocale), !value.isNaN else {
      return nil
    }
    return value
  }

  private static func isASCIIDigit(_ character: unichar) -> Bool {
    (0x0030...0x0039).contains(character)
  }

  private static func isSeparator(_ character: unichar) -> Bool {
    character == 0x002E || character == 0x002C
  }

  private static func isSign(_ character: unichar) -> Bool {
    character == 0x002B || character == 0x002D || character == 0x2212
  }

  private static func isNumericCandidate(_ character: unichar) -> Bool {
    isASCIIDigit(character) || isSeparator(character)
  }
}

public struct AggregateNumericFixture: Codable, Sendable, Equatable {
  public let schemaVersion: Int
  public let grammarID: String
  public let cases: [AggregateNumericFixtureCase]

  public init(schemaVersion: Int, grammarID: String, cases: [AggregateNumericFixtureCase]) {
    self.schemaVersion = schemaVersion
    self.grammarID = grammarID
    self.cases = cases
  }
}

public struct AggregateNumericFixtureCase: Codable, Sendable, Equatable {
  public let id: String
  public let modeID: ModeID
  public let locale: MathDecimalLocale
  public let source: String
  public let expectedCanonicalValue: String?
  public let expectedConsumedValueCount: Int
  public let expectedDiagnosticCodes: [AggregateDiagnosticCode]

  public init(
    id: String,
    modeID: ModeID,
    locale: MathDecimalLocale,
    source: String,
    expectedCanonicalValue: String?,
    expectedConsumedValueCount: Int,
    expectedDiagnosticCodes: [AggregateDiagnosticCode]
  ) {
    self.id = id
    self.modeID = modeID
    self.locale = locale
    self.source = source
    self.expectedCanonicalValue = expectedCanonicalValue
    self.expectedConsumedValueCount = expectedConsumedValueCount
    self.expectedDiagnosticCodes = expectedDiagnosticCodes
  }
}

public enum AggregateFixtureError: Error, Equatable, Sendable {
  case resourceMissing(String)
  case malformed
  case unsupportedSchemaVersion(Int)
  case invalidGrammarID(String)
  case emptyCases
  case invalidCase(String)
  case duplicateCaseID(String)
}

public enum AggregateFixtureLoader {
  public static func loadBundled() throws -> AggregateNumericFixture {
    guard
      let url = Bundle.module.url(
        forResource: "numeric-extraction-v1",
        withExtension: "json",
        subdirectory: "Aggregates"
      ) ?? Bundle.module.url(forResource: "numeric-extraction-v1", withExtension: "json")
    else {
      throw AggregateFixtureError.resourceMissing("Aggregates/numeric-extraction-v1.json")
    }
    return try load(Data(contentsOf: url))
  }

  public static func load(_ data: Data) throws -> AggregateNumericFixture {
    let fixture: AggregateNumericFixture
    do {
      fixture = try JSONDecoder().decode(AggregateNumericFixture.self, from: data)
    } catch {
      throw AggregateFixtureError.malformed
    }
    guard fixture.schemaVersion == 1 else {
      throw AggregateFixtureError.unsupportedSchemaVersion(fixture.schemaVersion)
    }
    guard fixture.grammarID == "fornow-aggregates-v1" else {
      throw AggregateFixtureError.invalidGrammarID(fixture.grammarID)
    }
    guard !fixture.cases.isEmpty else { throw AggregateFixtureError.emptyCases }

    var ids = Set<String>()
    for testCase in fixture.cases {
      guard
        !testCase.id.isEmpty,
        [.sum, .average, .count].contains(testCase.modeID),
        testCase.expectedConsumedValueCount >= 0,
        ModeHeaderParser().parse(in: testCase.source)?.modeID == testCase.modeID
      else {
        throw AggregateFixtureError.invalidCase(testCase.id)
      }
      guard ids.insert(testCase.id).inserted else {
        throw AggregateFixtureError.duplicateCaseID(testCase.id)
      }
    }
    return fixture
  }
}
