import ForNowCore
import Foundation

public enum MathDecimalLocale: String, Codable, CaseIterable, Sendable {
  case periodDecimal
  case commaDecimal

  public init(locale: Locale = .current) {
    self = locale.decimalSeparator == "," ? .commaDecimal : .periodDecimal
  }

  public var decimalSeparator: String {
    self == .commaDecimal ? "," : "."
  }

  public var groupingSeparator: String {
    self == .commaDecimal ? "." : ","
  }
}

public struct MathSettings: Codable, Equatable, Sendable {
  public var significantDigits: Int
  public var separatesThousands: Bool
  public var primaryCurrency: CurrencyCode
  public var secondaryCurrency: CurrencyCode
  public var primaryCurrencySymbol: String
  public var automaticCurrencyRefreshEnabled: Bool
  public var customCurrencyRates: [CustomCurrencyRate]

  public init(
    significantDigits: Int = 2,
    separatesThousands: Bool = true,
    primaryCurrency: CurrencyCode = CurrencyCode(rawValue: "USD"),
    secondaryCurrency: CurrencyCode = CurrencyCode(rawValue: "EUR"),
    primaryCurrencySymbol: String = "$",
    automaticCurrencyRefreshEnabled: Bool = false,
    customCurrencyRates: [CustomCurrencyRate] = []
  ) {
    self.significantDigits = min(7, max(0, significantDigits))
    self.separatesThousands = separatesThousands
    self.primaryCurrency = primaryCurrency
    self.secondaryCurrency = secondaryCurrency
    self.primaryCurrencySymbol = primaryCurrencySymbol
    self.automaticCurrencyRefreshEnabled = automaticCurrencyRefreshEnabled
    self.customCurrencyRates = customCurrencyRates
  }

  public func validated() throws -> MathSettings {
    guard (0...7).contains(significantDigits) else {
      throw MathSettingsValidationError.invalidSignificantDigits(significantDigits)
    }
    guard primaryCurrency.isISOFormatted else {
      throw MathSettingsValidationError.invalidCurrency(primaryCurrency)
    }
    guard secondaryCurrency.isISOFormatted else {
      throw MathSettingsValidationError.invalidCurrency(secondaryCurrency)
    }
    let currencyCatalog = ConversionCatalogs.bundled.currencies
    guard currencyCatalog.contains(primaryCurrency) else {
      throw MathSettingsValidationError.unsupportedCurrency(primaryCurrency)
    }
    guard currencyCatalog.contains(secondaryCurrency) else {
      throw MathSettingsValidationError.unsupportedCurrency(secondaryCurrency)
    }
    guard
      !primaryCurrencySymbol.isEmpty,
      primaryCurrencySymbol.utf16.count <= 8,
      !primaryCurrencySymbol.contains(where: { $0.isWhitespace })
    else {
      throw MathSettingsValidationError.invalidPrimaryCurrencySymbol
    }
    guard customCurrencyRates.count <= 128 else {
      throw MathSettingsValidationError.tooManyCustomRates
    }
    var pairs = Set<CustomCurrencyRate.Pair>()
    for rate in customCurrencyRates {
      _ = try rate.validated()
      guard
        currencyCatalog.contains(rate.source),
        currencyCatalog.contains(rate.target)
      else {
        throw MathSettingsValidationError.unsupportedCurrency(
          currencyCatalog.contains(rate.source) ? rate.target : rate.source
        )
      }
      guard pairs.insert(rate.pair).inserted else {
        throw MathSettingsValidationError.duplicateCustomRate(rate.source, rate.target)
      }
    }
    return self
  }

  private enum CodingKeys: String, CodingKey {
    case significantDigits
    case separatesThousands
    case primaryCurrency
    case secondaryCurrency
    case primaryCurrencySymbol
    case automaticCurrencyRefreshEnabled
    case customCurrencyRates
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    significantDigits = try values.decode(Int.self, forKey: .significantDigits)
    separatesThousands = try values.decode(Bool.self, forKey: .separatesThousands)
    primaryCurrency =
      try values.decodeIfPresent(CurrencyCode.self, forKey: .primaryCurrency)
      ?? CurrencyCode(rawValue: "USD")
    secondaryCurrency =
      try values.decodeIfPresent(CurrencyCode.self, forKey: .secondaryCurrency)
      ?? CurrencyCode(rawValue: "EUR")
    primaryCurrencySymbol =
      try values.decodeIfPresent(String.self, forKey: .primaryCurrencySymbol) ?? "$"
    automaticCurrencyRefreshEnabled =
      try values.decodeIfPresent(Bool.self, forKey: .automaticCurrencyRefreshEnabled) ?? false
    customCurrencyRates =
      try values.decodeIfPresent([CustomCurrencyRate].self, forKey: .customCurrencyRates) ?? []
    _ = try validated()
  }
}

public enum MathSettingsValidationError: Error, Equatable, Sendable {
  case invalidSignificantDigits(Int)
  case invalidCurrency(CurrencyCode)
  case unsupportedCurrency(CurrencyCode)
  case invalidPrimaryCurrencySymbol
  case invalidCustomRate(CurrencyCode, CurrencyCode)
  case duplicateCustomRate(CurrencyCode, CurrencyCode)
  case tooManyCustomRates
}

extension MathSettingsValidationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidSignificantDigits:
      "Result digits must be between 0 and 7."
    case .invalidCurrency:
      "Currency codes must contain exactly three ASCII letters."
    case .unsupportedCurrency:
      "The currency code is not present in the bundled ISO fixture."
    case .invalidPrimaryCurrencySymbol:
      "The primary currency symbol must contain between one and eight characters."
    case .invalidCustomRate:
      "Custom currency rates must be positive finite decimals."
    case .duplicateCustomRate:
      "Each custom currency pair may be defined only once."
    case .tooManyCustomRates:
      "No more than 128 custom currency rates may be configured."
    }
  }
}

public struct CustomCurrencyRate: Codable, Equatable, Sendable, Identifiable {
  public struct Pair: Hashable, Sendable {
    public let source: CurrencyCode
    public let target: CurrencyCode

    public init(source: CurrencyCode, target: CurrencyCode) {
      self.source = source
      self.target = target
    }
  }

  public let source: CurrencyCode
  public let target: CurrencyCode
  public var rate: Decimal
  public var updatedAt: Date

  public init(
    source: CurrencyCode,
    target: CurrencyCode,
    rate: Decimal,
    updatedAt: Date
  ) {
    self.source = source
    self.target = target
    self.rate = rate
    self.updatedAt = updatedAt
  }

  public var id: String { "\(source.rawValue)-\(target.rawValue)" }
  public var pair: Pair { Pair(source: source, target: target) }

  public func validated() throws -> CustomCurrencyRate {
    let number = NSDecimalNumber(decimal: rate)
    guard
      source.isISOFormatted,
      target.isISOFormatted,
      source != target,
      number != .notANumber,
      number.compare(NSDecimalNumber.zero) == .orderedDescending
    else {
      throw MathSettingsValidationError.invalidCustomRate(source, target)
    }
    return self
  }
}

public enum MathUnaryOperator: Sendable, Equatable {
  case plus
  case minus
}

public enum MathBinaryOperator: Sendable, Equatable {
  case add
  case subtract
  case multiply
  case divide
  case power
  case percentOf
}

public enum MathFunctionID: Sendable, Equatable {
  case squareRoot
  case cubeRoot
  case logarithm10
  case logarithm2
  case ceiling
  case floor
}

public enum MathFactorialKind: Sendable, Equatable {
  case factorial
  case doubleFactorial
}

public indirect enum ExpressionNode: Sendable, Equatable {
  case decimal(Decimal)
  case unary(MathUnaryOperator, ExpressionNode)
  case binary(MathBinaryOperator, ExpressionNode, ExpressionNode)
  case function(MathFunctionID, ExpressionNode)
  case percentage(ExpressionNode)
  case factorial(MathFactorialKind, ExpressionNode)
}

public enum BasicMathDiagnosticCode: String, Sendable, Equatable {
  case emptyExpression = "math-empty-expression"
  case invalidNumber = "math-invalid-number"
  case spacedThousandsUnsupported = "math-spaced-thousands-unsupported"
  case unexpectedToken = "math-unexpected-token"
  case missingOperand = "math-missing-operand"
  case missingClosingParenthesis = "math-missing-closing-parenthesis"
  case divisionByZero = "math-division-by-zero"
  case domainError = "math-domain-error"
  case factorialDomain = "math-factorial-domain"
  case overflow = "math-overflow"
  case underflow = "math-underflow"
  case resourceLimit = "math-resource-limit"
  case conversionUnknownSourceUnit = "conversion-unknown-source-unit"
  case conversionUnknownTargetUnit = "conversion-unknown-target-unit"
  case conversionIncompatibleUnits = "conversion-incompatible-units"
  case conversionCompositionUnsupported = "conversion-composition-unsupported"
  case conversionOverflow = "conversion-overflow"
  case currencyUnknownCode = "currency-unknown-code"
  case currencyRatesUnavailable = "currency-rates-unavailable"
  case currencyRateMissing = "currency-rate-missing"
  case currencyInvalidRate = "currency-invalid-rate"
  case variableInvalidDeclaration = "variable-invalid-declaration"
  case variableDuplicateName = "variable-duplicate-name"
  case variableCycle = "variable-cycle"
  case variableDepthLimit = "variable-depth-limit"
  case variableDependencyUnavailable = "variable-dependency-unavailable"
  case variableResourceLimit = "variable-resource-limit"
}

public struct BasicMathDiagnostic: Error, Sendable, Equatable {
  public let code: BasicMathDiagnosticCode
  public let sourceRange: NSRange
  public let message: String

  public init(code: BasicMathDiagnosticCode, sourceRange: NSRange, message: String) {
    self.code = code
    self.sourceRange = sourceRange
    self.message = message
  }
}

extension BasicMathDiagnostic: LocalizedError {
  public var errorDescription: String? { message }
}

public struct BasicMathResult: Sendable, Equatable {
  public let expressionRange: NSRange
  public let anchorUTF16Offset: Int
  public let expression: ExpressionNode
  public let canonicalValue: String
  public let displayText: String
  public let copiedText: String
  public let dependencyIDs: [String]

  public init(
    expressionRange: NSRange,
    anchorUTF16Offset: Int,
    expression: ExpressionNode,
    canonicalValue: String,
    displayText: String,
    copiedText: String,
    dependencyIDs: [String] = []
  ) {
    self.expressionRange = expressionRange
    self.anchorUTF16Offset = anchorUTF16Offset
    self.expression = expression
    self.canonicalValue = canonicalValue
    self.displayText = displayText
    self.copiedText = copiedText
    self.dependencyIDs = dependencyIDs
  }
}

public enum BasicMathLineEvaluation: Sendable, Equatable {
  case result(BasicMathResult)
  case diagnostic(BasicMathDiagnostic)
}

public struct BasicMathDocumentParser: Sendable {
  private let mathSettings: MathSettings
  private let modeSettings: ModeSettings
  private let locale: MathDecimalLocale
  private let conversionCatalogs: ConversionCatalogs
  private let currencyContext: CurrencyConversionContext

  public init(
    mathSettings: MathSettings = MathSettings(),
    modeSettings: ModeSettings = ModeSettings(),
    locale: MathDecimalLocale = MathDecimalLocale(),
    conversionCatalogs: ConversionCatalogs = .bundled,
    currencyContext: CurrencyConversionContext = CurrencyConversionContext()
  ) {
    self.mathSettings = mathSettings
    self.modeSettings = modeSettings
    self.locale = locale
    self.conversionCatalogs = conversionCatalogs
    self.currencyContext = currencyContext
  }

  public func parse(in source: String) -> [BasicMathLineEvaluation] {
    (try? parse(source, checksCancellation: false)) ?? []
  }

  public func parseCancellable(in source: String) throws -> [BasicMathLineEvaluation] {
    try parse(source, checksCancellation: true)
  }

  private func parse(
    _ source: String,
    checksCancellation: Bool
  ) throws -> [BasicMathLineEvaluation] {
    guard
      let header = ModeHeaderParser(settings: modeSettings).parse(in: source),
      header.modeID == .math,
      header.bodyRange.length > 0
    else { return [] }

    return try VariableDocumentEvaluator(
      settings: (try? mathSettings.validated()) ?? MathSettings(),
      locale: locale,
      catalogs: conversionCatalogs,
      currencyContext: currencyContext
    ).evaluate(
      source: source,
      bodyRange: header.bodyRange,
      checksCancellation: checksCancellation
    )
  }
}

private enum MathTokenKind: Sendable, Equatable {
  case number(Decimal)
  case plus
  case minus
  case multiply
  case divide
  case power
  case leftParenthesis
  case rightParenthesis
  case percent
  case factorial
  case doubleFactorial
  case squareRoot
  case cubeRoot
  case function(MathFunctionID)
  case of
  case end
}

private struct MathToken: Sendable, Equatable {
  let kind: MathTokenKind
  let range: NSRange
}

struct BasicMathExpressionEvaluation: Sendable, Equatable {
  let expression: ExpressionNode
  let value: Decimal
}

struct BasicMathExpressionEngine: Sendable {
  let locale: MathDecimalLocale

  func evaluate(_ source: String, sourceRange: NSRange) throws -> BasicMathExpressionEvaluation {
    let tokens = try MathLexer(
      source: source,
      baseUTF16Offset: sourceRange.location,
      locale: locale
    ).tokens()
    var parser = MathExpressionParser(tokens: tokens)
    let expression = try parser.parse()
    let value = try MathDecimalEvaluator(sourceRange: sourceRange).evaluate(expression)
    return BasicMathExpressionEvaluation(expression: expression, value: value)
  }
}

private struct MathLexer {
  private static let maximumTokenCount = 512
  private static let posixLocale = Locale(identifier: "en_US_POSIX")

  let source: String
  let baseUTF16Offset: Int
  let locale: MathDecimalLocale

  func tokens() throws -> [MathToken] {
    let nsSource = source as NSString
    if let range = spacedThousandsRange(in: source) {
      throw diagnostic(
        .spacedThousandsUnsupported,
        localRange: range,
        message: "Spaces cannot be used as thousands separators."
      )
    }

    var tokens: [MathToken] = []
    var location = 0
    while location < nsSource.length {
      let character = nsSource.character(at: location)
      if Self.isWhitespace(character) {
        location += 1
        continue
      }
      if Self.isASCIIDigit(character)
        || (Self.isDecimalSeparator(character, locale: locale)
          && location + 1 < nsSource.length
          && Self.isASCIIDigit(nsSource.character(at: location + 1)))
      {
        let start = location
        location += 1
        while location < nsSource.length {
          let next = nsSource.character(at: location)
          if Self.isASCIIDigit(next) {
            location += 1
            continue
          }
          guard next == 0x002E || next == 0x002C,
            location + 1 < nsSource.length,
            Self.isASCIIDigit(nsSource.character(at: location + 1))
          else { break }
          location += 1
        }
        let range = NSRange(location: start, length: location - start)
        let numberSource = nsSource.substring(with: range)
        guard let number = decimal(from: numberSource) else {
          throw diagnostic(
            .invalidNumber,
            localRange: range,
            message: "The number does not match the active decimal locale."
          )
        }
        tokens.append(token(.number(number), localRange: range))
      } else if Self.isASCIIWordStart(character) {
        let start = location
        location += 1
        while location < nsSource.length,
          Self.isASCIIWordContinuation(nsSource.character(at: location))
        {
          location += 1
        }
        let range = NSRange(location: start, length: location - start)
        let word = nsSource.substring(with: range).lowercased(with: Self.posixLocale)
        let kind: MathTokenKind?
        switch word {
        case "x": kind = .multiply
        case "of": kind = .of
        case "sqrt": kind = .function(.squareRoot)
        case "log": kind = .function(.logarithm10)
        case "log2": kind = .function(.logarithm2)
        case "ceil": kind = .function(.ceiling)
        case "floor": kind = .function(.floor)
        default: kind = nil
        }
        if let kind {
          tokens.append(token(kind, localRange: range))
        }
      } else {
        let start = location
        let kind: MathTokenKind?
        switch character {
        case 0x002B:
          kind = .plus
        case 0x002D:
          kind = .minus
        case 0x002A:
          if location + 1 < nsSource.length, nsSource.character(at: location + 1) == 0x002A {
            location += 1
            kind = .power
          } else {
            kind = .multiply
          }
        case 0x002F, 0x00F7:
          kind = .divide
        case 0x005E:
          kind = .power
        case 0x0028:
          kind = .leftParenthesis
        case 0x0029:
          kind = .rightParenthesis
        case 0x0025:
          kind = .percent
        case 0x0021:
          if location + 1 < nsSource.length, nsSource.character(at: location + 1) == 0x0021 {
            location += 1
            kind = .doubleFactorial
          } else {
            kind = .factorial
          }
        case 0x221A:
          kind = .squareRoot
        case 0x221B:
          kind = .cubeRoot
        case 0x003D:
          throw diagnostic(
            .unexpectedToken,
            localRange: NSRange(location: start, length: 1),
            message: "Only the trailing equals sign can request evaluation."
          )
        default:
          kind = nil
        }
        location += 1
        if let kind {
          tokens.append(
            token(kind, localRange: NSRange(location: start, length: location - start))
          )
        }
      }
      if tokens.count > Self.maximumTokenCount {
        throw diagnostic(
          .resourceLimit,
          localRange: NSRange(location: 0, length: nsSource.length),
          message: "The expression is too large to evaluate."
        )
      }
    }
    tokens.append(
      token(.end, localRange: NSRange(location: nsSource.length, length: 0))
    )
    return tokens
  }

  private func decimal(from source: String) -> Decimal? {
    let decimal = NSRegularExpression.escapedPattern(for: locale.decimalSeparator)
    let grouping = NSRegularExpression.escapedPattern(for: locale.groupingSeparator)
    let integer = #"(?:[0-9]{1,3}(?:"# + grouping + #"[0-9]{3})+|[0-9]+)"#
    let pattern =
      #"^(?:"# + integer + #"(?:"# + decimal + #"[0-9]+)?|"#
      + decimal + #"[0-9]+)$"#
    guard source.range(of: pattern, options: .regularExpression) != nil else { return nil }
    let normalized =
      source
      .replacingOccurrences(of: locale.groupingSeparator, with: "")
      .replacingOccurrences(of: locale.decimalSeparator, with: ".")
    return Decimal(string: normalized, locale: Self.posixLocale)
  }

  private func spacedThousandsRange(in source: String) -> NSRange? {
    guard
      let expression = try? NSRegularExpression(
        pattern: #"[0-9][\t ]+[0-9]{3}(?:[.,][0-9]+)?(?![0-9])"#
      )
    else { return nil }
    return expression.firstMatch(
      in: source,
      range: NSRange(location: 0, length: source.utf16.count)
    )?.range
  }

  private func token(_ kind: MathTokenKind, localRange: NSRange) -> MathToken {
    MathToken(
      kind: kind,
      range: NSRange(
        location: baseUTF16Offset + localRange.location,
        length: localRange.length
      )
    )
  }

  private func diagnostic(
    _ code: BasicMathDiagnosticCode,
    localRange: NSRange,
    message: String
  ) -> BasicMathDiagnostic {
    BasicMathDiagnostic(
      code: code,
      sourceRange: NSRange(
        location: baseUTF16Offset + localRange.location,
        length: localRange.length
      ),
      message: message
    )
  }

  private static func isASCIIDigit(_ character: unichar) -> Bool {
    (0x0030...0x0039).contains(character)
  }

  private static func isASCIIWordStart(_ character: unichar) -> Bool {
    (0x0041...0x005A).contains(character) || (0x0061...0x007A).contains(character)
  }

  private static func isASCIIWordContinuation(_ character: unichar) -> Bool {
    isASCIIWordStart(character) || isASCIIDigit(character) || character == 0x005F
  }

  private static func isWhitespace(_ character: unichar) -> Bool {
    character == 0x0020 || character == 0x0009 || character == 0x000A || character == 0x000D
  }

  private static func isDecimalSeparator(
    _ character: unichar,
    locale: MathDecimalLocale
  ) -> Bool {
    character == (locale == .commaDecimal ? 0x002C : 0x002E)
  }
}

private struct MathExpressionParser {
  private static let maximumDepth = 64

  let tokens: [MathToken]
  private var index = 0

  init(tokens: [MathToken]) {
    self.tokens = tokens
  }

  mutating func parse() throws -> ExpressionNode {
    guard current.kind != .end else {
      throw diagnostic(
        .emptyExpression,
        at: current,
        message: "Enter an expression before the equals sign."
      )
    }
    let expression = try parseAdditive(depth: 0)
    guard current.kind == .end else {
      throw diagnostic(
        .unexpectedToken,
        at: current,
        message: "An operator or delimiter is in an unexpected position."
      )
    }
    return expression
  }

  private var current: MathToken { tokens[min(index, tokens.count - 1)] }

  private mutating func advance() -> MathToken {
    let token = current
    index = min(index + 1, tokens.count - 1)
    return token
  }

  private mutating func parseAdditive(depth: Int) throws -> ExpressionNode {
    try check(depth: depth)
    var expression = try parseMultiplicative(depth: depth + 1)
    while current.kind == .plus || current.kind == .minus {
      let operation: MathBinaryOperator = advance().kind == .plus ? .add : .subtract
      let right = try parseMultiplicative(depth: depth + 1)
      expression = .binary(operation, expression, right)
    }
    return expression
  }

  private mutating func parseMultiplicative(depth: Int) throws -> ExpressionNode {
    try check(depth: depth)
    var expression = try parseUnary(depth: depth + 1)
    while current.kind == .multiply || current.kind == .divide || current.kind == .of {
      let token = advance()
      let operation: MathBinaryOperator
      switch token.kind {
      case .multiply:
        operation = .multiply
      case .divide:
        operation = .divide
      case .of:
        guard case .percentage = expression else {
          throw diagnostic(
            .unexpectedToken,
            at: token,
            message: "The word 'of' must follow a percentage."
          )
        }
        operation = .percentOf
      default:
        preconditionFailure("Unexpected multiplicative token")
      }
      let right = try parseUnary(depth: depth + 1)
      expression = .binary(operation, expression, right)
    }
    return expression
  }

  private mutating func parseUnary(depth: Int) throws -> ExpressionNode {
    try check(depth: depth)
    if current.kind == .plus || current.kind == .minus {
      let operation: MathUnaryOperator = advance().kind == .plus ? .plus : .minus
      return .unary(operation, try parseUnary(depth: depth + 1))
    }
    return try parsePower(depth: depth + 1)
  }

  private mutating func parsePower(depth: Int) throws -> ExpressionNode {
    try check(depth: depth)
    let left = try parsePostfix(depth: depth + 1)
    guard current.kind == .power else { return left }
    _ = advance()
    return .binary(.power, left, try parseUnary(depth: depth + 1))
  }

  private mutating func parsePostfix(depth: Int) throws -> ExpressionNode {
    try check(depth: depth)
    var expression = try parsePrimary(depth: depth + 1)
    if current.kind == .percent {
      _ = advance()
      expression = .percentage(expression)
    }
    if current.kind == .factorial || current.kind == .doubleFactorial {
      let kind: MathFactorialKind =
        advance().kind == .factorial
        ? .factorial : .doubleFactorial
      expression = .factorial(kind, expression)
    }
    return expression
  }

  private mutating func parsePrimary(depth: Int) throws -> ExpressionNode {
    try check(depth: depth)
    let token = advance()
    switch token.kind {
    case .number(let value):
      return .decimal(value)
    case .leftParenthesis:
      let expression = try parseAdditive(depth: depth + 1)
      guard current.kind == .rightParenthesis else {
        throw diagnostic(
          .missingClosingParenthesis,
          at: current,
          message: "A closing parenthesis is missing."
        )
      }
      _ = advance()
      return expression
    case .squareRoot:
      return .function(.squareRoot, try parseUnary(depth: depth + 1))
    case .cubeRoot:
      return .function(.cubeRoot, try parseUnary(depth: depth + 1))
    case .function(let function):
      guard current.kind == .leftParenthesis else {
        throw diagnostic(
          .unexpectedToken,
          at: current,
          message: "Math functions require parentheses."
        )
      }
      _ = advance()
      let argument = try parseAdditive(depth: depth + 1)
      guard current.kind == .rightParenthesis else {
        throw diagnostic(
          .missingClosingParenthesis,
          at: current,
          message: "A closing parenthesis is missing."
        )
      }
      _ = advance()
      return .function(function, argument)
    default:
      throw diagnostic(
        .missingOperand,
        at: token,
        message: "A number or expression is missing."
      )
    }
  }

  private func check(depth: Int) throws {
    guard depth <= Self.maximumDepth else {
      throw diagnostic(
        .resourceLimit,
        at: current,
        message: "The expression is nested too deeply."
      )
    }
  }

  private func diagnostic(
    _ code: BasicMathDiagnosticCode,
    at token: MathToken,
    message: String
  ) -> BasicMathDiagnostic {
    BasicMathDiagnostic(code: code, sourceRange: token.range, message: message)
  }
}

private struct MathDecimalEvaluator {
  private struct EvaluatedValue {
    let decimal: Decimal
    let percentageRatio: Decimal?

    init(_ decimal: Decimal, percentageRatio: Decimal? = nil) {
      self.decimal = decimal
      self.percentageRatio = percentageRatio
    }
  }

  private static let posixLocale = Locale(identifier: "en_US_POSIX")
  private static let factorialLimit = Decimal(1_000)
  private static let integralPowerLimit = Decimal(1_024)

  let sourceRange: NSRange

  func evaluate(_ expression: ExpressionNode) throws -> Decimal {
    try value(of: expression).decimal
  }

  private func value(of expression: ExpressionNode) throws -> EvaluatedValue {
    switch expression {
    case .decimal(let value):
      return EvaluatedValue(value)
    case .unary(let operation, let child):
      let value = try value(of: child)
      switch operation {
      case .plus:
        return value
      case .minus:
        let decimal = try subtract(0, value.decimal)
        let ratio = try value.percentageRatio.map { try subtract(0, $0) }
        return EvaluatedValue(decimal, percentageRatio: ratio)
      }
    case .percentage(let child):
      let ratio = try divide(try value(of: child).decimal, 100)
      return EvaluatedValue(ratio, percentageRatio: ratio)
    case .factorial(let kind, let child):
      return EvaluatedValue(try factorial(try value(of: child).decimal, kind: kind))
    case .function(let function, let child):
      return EvaluatedValue(try apply(function, to: try value(of: child).decimal))
    case .binary(let operation, let leftNode, let rightNode):
      let left = try value(of: leftNode)
      let right = try value(of: rightNode)
      switch operation {
      case .add:
        if let percentage = right.percentageRatio {
          return EvaluatedValue(try add(left.decimal, try multiply(left.decimal, percentage)))
        }
        return EvaluatedValue(try add(left.decimal, right.decimal))
      case .subtract:
        if let percentage = right.percentageRatio {
          return EvaluatedValue(
            try subtract(left.decimal, try multiply(left.decimal, percentage))
          )
        }
        return EvaluatedValue(try subtract(left.decimal, right.decimal))
      case .multiply:
        return EvaluatedValue(try multiply(left.decimal, right.decimal))
      case .divide:
        return EvaluatedValue(try divide(left.decimal, right.decimal))
      case .power:
        return EvaluatedValue(try power(left.decimal, right.decimal))
      case .percentOf:
        guard let percentage = left.percentageRatio else {
          throw diagnostic(.domainError, "The 'of' operator requires a percentage.")
        }
        return EvaluatedValue(try multiply(percentage, right.decimal))
      }
    }
  }

  private func add(_ left: Decimal, _ right: Decimal) throws -> Decimal {
    try calculate(left, right, operation: NSDecimalAdd)
  }

  private func subtract(_ left: Decimal, _ right: Decimal) throws -> Decimal {
    try calculate(left, right, operation: NSDecimalSubtract)
  }

  private func multiply(_ left: Decimal, _ right: Decimal) throws -> Decimal {
    try calculate(left, right, operation: NSDecimalMultiply)
  }

  private func divide(_ left: Decimal, _ right: Decimal) throws -> Decimal {
    guard compare(right, 0) != .orderedSame else {
      throw diagnostic(.divisionByZero, "Division by zero is undefined.")
    }
    return try calculate(left, right, operation: NSDecimalDivide)
  }

  private func calculate(
    _ left: Decimal,
    _ right: Decimal,
    operation: (
      UnsafeMutablePointer<Decimal>, UnsafePointer<Decimal>, UnsafePointer<Decimal>,
      Decimal.RoundingMode
    ) -> Decimal.CalculationError
  ) throws -> Decimal {
    var left = left
    var right = right
    var result = Decimal()
    let error = operation(&result, &left, &right, .bankers)
    try check(error)
    guard !result.isNaN else {
      throw diagnostic(.domainError, "The calculation has no real decimal result.")
    }
    return result
  }

  private func power(_ base: Decimal, _ exponent: Decimal) throws -> Decimal {
    if let integerExponent = integer(exponent) {
      guard compare(abs(exponent), Self.integralPowerLimit) != .orderedDescending else {
        throw diagnostic(.resourceLimit, "The exponent is too large to evaluate.")
      }
      if integerExponent < 0, compare(base, 0) == .orderedSame {
        throw diagnostic(.divisionByZero, "Zero cannot be raised to a negative power.")
      }
      var result = Decimal(1)
      var factor = base
      var remaining = Swift.abs(integerExponent)
      while remaining > 0 {
        if remaining.isMultiple(of: 2) == false {
          result = try multiply(result, factor)
        }
        remaining /= 2
        if remaining > 0 {
          factor = try multiply(factor, factor)
        }
      }
      return integerExponent < 0 ? try divide(1, result) : result
    }
    let result = Foundation.pow(double(base), double(exponent))
    return try decimal(fromFinite: result)
  }

  private func factorial(_ value: Decimal, kind: MathFactorialKind) throws -> Decimal {
    guard compare(value, 0) != .orderedAscending,
      compare(value, Self.factorialLimit) != .orderedDescending,
      let operand = integer(value)
    else {
      throw diagnostic(
        .factorialDomain,
        "Factorial operands must be non-negative integers no greater than 1000."
      )
    }
    if operand == 0 || operand == 1 { return 1 }
    let step = kind == .factorial ? 1 : 2
    var result = Decimal(1)
    var factor = operand
    while factor > 1 {
      result = try multiply(result, Decimal(factor))
      factor -= step
    }
    return result
  }

  private func apply(_ function: MathFunctionID, to value: Decimal) throws -> Decimal {
    switch function {
    case .squareRoot:
      guard compare(value, 0) != .orderedAscending else {
        throw diagnostic(.domainError, "Square root requires a non-negative value.")
      }
      return try decimal(fromFinite: Foundation.sqrt(double(value)))
    case .cubeRoot:
      return try decimal(fromFinite: Foundation.cbrt(double(value)))
    case .logarithm10:
      guard compare(value, 0) == .orderedDescending else {
        throw diagnostic(.domainError, "Logarithm requires a positive value.")
      }
      return try decimal(fromFinite: Foundation.log10(double(value)))
    case .logarithm2:
      guard compare(value, 0) == .orderedDescending else {
        throw diagnostic(.domainError, "Logarithm requires a positive value.")
      }
      return try decimal(fromFinite: Foundation.log2(double(value)))
    case .ceiling:
      return try roundedIntegral(value, towardCeiling: true)
    case .floor:
      return try roundedIntegral(value, towardCeiling: false)
    }
  }

  private func roundedIntegral(_ value: Decimal, towardCeiling: Bool) throws -> Decimal {
    var value = value
    var result = Decimal()
    NSDecimalRound(&result, &value, 0, towardCeiling ? .up : .down)
    return result
  }

  private func decimal(fromFinite value: Double) throws -> Decimal {
    guard value.isFinite else {
      throw diagnostic(.domainError, "The calculation has no finite real result.")
    }
    let source = String(format: "%.17g", locale: Self.posixLocale, value)
    guard let result = Decimal(string: source, locale: Self.posixLocale), !result.isNaN else {
      throw diagnostic(.overflow, "The result exceeds Decimal range.")
    }
    return result
  }

  private func double(_ value: Decimal) -> Double {
    NSDecimalNumber(decimal: value).doubleValue
  }

  private func integer(_ value: Decimal) -> Int? {
    var value = value
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 0, .down)
    guard compare(rounded, value) == .orderedSame else { return nil }
    return NSDecimalNumber(decimal: rounded).intValue
  }

  private func abs(_ value: Decimal) -> Decimal {
    compare(value, 0) == .orderedAscending ? -value : value
  }

  private func compare(_ left: Decimal, _ right: Decimal) -> ComparisonResult {
    NSDecimalNumber(decimal: left).compare(NSDecimalNumber(decimal: right))
  }

  private func check(_ error: Decimal.CalculationError) throws {
    switch error {
    case .noError, .lossOfPrecision:
      return
    case .underflow:
      throw diagnostic(.underflow, "The result is too close to zero for Decimal precision.")
    case .overflow:
      throw diagnostic(.overflow, "The result exceeds Decimal range.")
    case .divideByZero:
      throw diagnostic(.divisionByZero, "Division by zero is undefined.")
    @unknown default:
      throw diagnostic(.domainError, "The calculation has no valid decimal result.")
    }
  }

  private func diagnostic(
    _ code: BasicMathDiagnosticCode,
    _ message: String
  ) -> BasicMathDiagnostic {
    BasicMathDiagnostic(code: code, sourceRange: sourceRange, message: message)
  }
}

struct BasicMathFormatter {
  let settings: MathSettings
  let locale: MathDecimalLocale

  func canonical(_ value: Decimal) -> String {
    if NSDecimalNumber(decimal: value).compare(NSDecimalNumber.zero) == .orderedSame {
      return "0"
    }
    return NSDecimalNumber(decimal: value).stringValue
  }

  func display(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.decimalSeparator = locale.decimalSeparator
    formatter.groupingSeparator = locale.groupingSeparator
    formatter.usesGroupingSeparator = settings.separatesThousands
    formatter.groupingSize = 3
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = settings.significantDigits
    formatter.roundingMode = .halfEven
    formatter.generatesDecimalNumbers = true
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? canonical(value)
  }
}
