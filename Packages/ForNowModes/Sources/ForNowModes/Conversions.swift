import ForNowCore
import Foundation

public enum UnitCategory: String, Codable, CaseIterable, Sendable {
  case distance
  case area
  case volume
  case mass
  case temperature
}

public struct UnitDefinition: Codable, Equatable, Sendable {
  public let id: String
  public let symbol: String
  public let aliases: [String]
  public let category: UnitCategory

  public init(id: String, symbol: String, aliases: [String], category: UnitCategory) {
    self.id = id
    self.symbol = symbol
    self.aliases = aliases
    self.category = category
  }
}

public struct CurrencyDefinition: Codable, Equatable, Sendable, Identifiable {
  public let code: CurrencyCode
  public let name: String
  public let aliases: [String]

  public init(code: CurrencyCode, name: String, aliases: [String]) {
    self.code = code
    self.name = name
    self.aliases = aliases
  }

  public var id: CurrencyCode { code }
}

public enum ConversionFixtureError: Error, Equatable, Sendable {
  case resourceMissing(String)
  case malformed(String)
  case unsupportedSchemaVersion(Int)
  case missingCategory(UnitCategory)
  case categoryMismatch(expected: UnitCategory, actual: UnitCategory)
  case duplicateUnitID(String)
  case unknownUnitID(String)
  case duplicateUnitAlias(String)
  case invalidUnit(String)
  case invalidCurrencyCode(String)
  case duplicateCurrencyCode(CurrencyCode)
  case duplicateCurrencyAlias(String)
  case invalidCurrency(CurrencyCode)
}

public struct UnitCatalog: Equatable, Sendable {
  public let units: [UnitDefinition]
  private let aliases: [String: UnitDefinition]

  fileprivate init(units: [UnitDefinition], aliases: [String: UnitDefinition]) {
    self.units = units
    self.aliases = aliases
  }

  public func unit(matching alias: String) -> UnitDefinition? {
    aliases[Self.normalize(alias)]
  }

  fileprivate static func normalize(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
  }
}

public struct CurrencyCatalog: Equatable, Sendable {
  public let currencies: [CurrencyDefinition]
  private let byCode: [CurrencyCode: CurrencyDefinition]

  fileprivate init(currencies: [CurrencyDefinition]) {
    self.currencies = currencies.sorted { $0.code < $1.code }
    byCode = Dictionary(uniqueKeysWithValues: currencies.map { ($0.code, $0) })
  }

  public func contains(_ code: CurrencyCode) -> Bool {
    byCode[code] != nil
  }

  public func currency(for code: CurrencyCode) -> CurrencyDefinition? {
    byCode[code]
  }
}

public struct ConversionCatalogs: Equatable, Sendable {
  public let units: UnitCatalog
  public let currencies: CurrencyCatalog

  public init(units: UnitCatalog, currencies: CurrencyCatalog) {
    self.units = units
    self.currencies = currencies
  }

  public static let bundled: ConversionCatalogs = {
    do {
      return try ConversionFixtureLoader.loadBundled()
    } catch {
      preconditionFailure("Invalid bundled conversion fixtures: \(error)")
    }
  }()
}

public enum ConversionFixtureLoader {
  public static func loadBundled() throws -> ConversionCatalogs {
    try loadBundled(bundle: .module)
  }

  public static func loadBundled(bundle: Bundle) throws -> ConversionCatalogs {
    var unitData: [UnitCategory: Data] = [:]
    for category in UnitCategory.allCases {
      guard
        let url = resourceURL(
          bundle: bundle,
          name: category.rawValue,
          extension: "json",
          subdirectory: "Units/v1"
        )
      else {
        throw ConversionFixtureError.resourceMissing("Units/v1/\(category.rawValue).json")
      }
      unitData[category] = try Data(contentsOf: url)
    }
    guard
      let currencyURL = resourceURL(
        bundle: bundle,
        name: "iso-4217-v1",
        extension: "json",
        subdirectory: "Currencies"
      )
    else {
      throw ConversionFixtureError.resourceMissing("Currencies/iso-4217-v1.json")
    }
    return try ConversionCatalogs(
      units: loadUnits(unitData),
      currencies: loadCurrencies(try Data(contentsOf: currencyURL))
    )
  }

  public static func loadUnits(_ dataByCategory: [UnitCategory: Data]) throws -> UnitCatalog {
    let decoder = JSONDecoder()
    var units: [UnitDefinition] = []
    var ids = Set<String>()
    var aliases: [String: UnitDefinition] = [:]
    for category in UnitCategory.allCases {
      guard let data = dataByCategory[category] else {
        throw ConversionFixtureError.missingCategory(category)
      }
      let fixture: StoredUnitFixture
      do {
        fixture = try decoder.decode(StoredUnitFixture.self, from: data)
      } catch {
        throw ConversionFixtureError.malformed("Units/v1/\(category.rawValue).json")
      }
      guard fixture.schemaVersion == 1 else {
        throw ConversionFixtureError.unsupportedSchemaVersion(fixture.schemaVersion)
      }
      guard fixture.category == category else {
        throw ConversionFixtureError.categoryMismatch(
          expected: category,
          actual: fixture.category
        )
      }
      for stored in fixture.units {
        guard
          !stored.id.isEmpty,
          !stored.symbol.isEmpty,
          !stored.aliases.isEmpty
        else {
          throw ConversionFixtureError.invalidUnit(stored.id)
        }
        guard UnitRuntimeMapping.supportedIDs.contains(stored.id) else {
          throw ConversionFixtureError.unknownUnitID(stored.id)
        }
        guard ids.insert(stored.id).inserted else {
          throw ConversionFixtureError.duplicateUnitID(stored.id)
        }
        let definition = UnitDefinition(
          id: stored.id,
          symbol: stored.symbol,
          aliases: stored.aliases,
          category: category
        )
        for alias in stored.aliases {
          let normalized = UnitCatalog.normalize(alias)
          guard !normalized.isEmpty else {
            throw ConversionFixtureError.invalidUnit(stored.id)
          }
          guard aliases[normalized] == nil else {
            throw ConversionFixtureError.duplicateUnitAlias(normalized)
          }
          aliases[normalized] = definition
        }
        units.append(definition)
      }
    }
    return UnitCatalog(units: units, aliases: aliases)
  }

  public static func loadCurrencies(_ data: Data) throws -> CurrencyCatalog {
    let fixture: StoredCurrencyFixture
    do {
      fixture = try JSONDecoder().decode(StoredCurrencyFixture.self, from: data)
    } catch {
      throw ConversionFixtureError.malformed("Currencies/iso-4217-v1.json")
    }
    guard fixture.schemaVersion == 1 else {
      throw ConversionFixtureError.unsupportedSchemaVersion(fixture.schemaVersion)
    }
    var definitions: [CurrencyDefinition] = []
    var codes = Set<CurrencyCode>()
    var aliases = Set<String>()
    for stored in fixture.currencies {
      let code = CurrencyCode(rawValue: stored.code)
      guard code.isISOFormatted, stored.code == code.rawValue else {
        throw ConversionFixtureError.invalidCurrencyCode(stored.code)
      }
      guard !stored.name.isEmpty else {
        throw ConversionFixtureError.invalidCurrency(code)
      }
      guard codes.insert(code).inserted else {
        throw ConversionFixtureError.duplicateCurrencyCode(code)
      }
      let codeAlias = UnitCatalog.normalize(code.rawValue)
      guard aliases.insert(codeAlias).inserted else {
        throw ConversionFixtureError.duplicateCurrencyAlias(codeAlias)
      }
      for alias in stored.aliases {
        let normalized = UnitCatalog.normalize(alias)
        guard !normalized.isEmpty else {
          throw ConversionFixtureError.invalidCurrency(code)
        }
        guard aliases.insert(normalized).inserted else {
          throw ConversionFixtureError.duplicateCurrencyAlias(normalized)
        }
      }
      definitions.append(
        CurrencyDefinition(code: code, name: stored.name, aliases: stored.aliases)
      )
    }
    return CurrencyCatalog(currencies: definitions)
  }

  private static func resourceURL(
    bundle: Bundle,
    name: String,
    extension extensionName: String,
    subdirectory: String
  ) -> URL? {
    bundle.url(forResource: name, withExtension: extensionName, subdirectory: subdirectory)
      ?? bundle.url(forResource: name, withExtension: extensionName)
  }
}

private struct StoredUnitFixture: Decodable {
  let schemaVersion: Int
  let category: UnitCategory
  let units: [StoredUnit]
}

private struct StoredUnit: Decodable {
  let id: String
  let symbol: String
  let aliases: [String]
}

private struct StoredCurrencyFixture: Decodable {
  let schemaVersion: Int
  let currencies: [StoredCurrency]
}

private struct StoredCurrency: Decodable {
  let code: String
  let name: String
  let aliases: [String]
}

public struct CurrencyConversionContext: Equatable, Sendable {
  public let rateSnapshot: RateSnapshot?
  public let evaluationDate: Date

  public init(rateSnapshot: RateSnapshot? = nil, evaluationDate: Date = Date()) {
    self.rateSnapshot = rateSnapshot
    self.evaluationDate = evaluationDate
  }
}

private enum CurrencyRateState: Equatable, Sendable {
  case custom(Date)
  case rate(Date)
  case cached(Date)
  case staleCache(Date)

  var label: String {
    switch self {
    case .custom(let date):
      "custom \(Self.dateString(date))"
    case .rate(let date):
      "rate \(Self.dateString(date))"
    case .cached(let date):
      "cached \(Self.dateString(date))"
    case .staleCache(let date):
      "stale cache \(Self.dateString(date))"
    }
  }

  private static func dateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}

private struct CurrencyRateResolution: Equatable, Sendable {
  let rate: Decimal
  let state: CurrencyRateState
}

private enum CurrencyResolutionError: Error, Equatable, Sendable {
  case unavailable
  case missingRate
  case invalidRate
}

private struct CurrencyRateResolver: Sendable {
  let settings: MathSettings
  let context: CurrencyConversionContext

  func resolve(source: CurrencyCode, target: CurrencyCode) throws -> CurrencyRateResolution {
    if let direct = settings.customCurrencyRates.first(where: {
      $0.source == source && $0.target == target
    }) {
      return CurrencyRateResolution(rate: direct.rate, state: .custom(direct.updatedAt))
    }
    if let inverse = settings.customCurrencyRates.first(where: {
      $0.source == target && $0.target == source
    }) {
      return CurrencyRateResolution(
        rate: try DecimalConversionMath.divide(1, by: inverse.rate),
        state: .custom(inverse.updatedAt)
      )
    }
    guard let snapshot = context.rateSnapshot else {
      throw CurrencyResolutionError.unavailable
    }
    guard (try? snapshot.validated()) != nil else {
      throw CurrencyResolutionError.invalidRate
    }
    let sourceRate = source == snapshot.base ? Decimal(1) : snapshot.rates[source]
    let targetRate = target == snapshot.base ? Decimal(1) : snapshot.rates[target]
    guard let sourceRate, let targetRate else {
      throw CurrencyResolutionError.missingRate
    }
    let rate = try DecimalConversionMath.divide(targetRate, by: sourceRate)
    let age = context.evaluationDate.timeIntervalSince(snapshot.fetchedAt)
    let state: CurrencyRateState
    switch snapshot.source {
    case .cached where age >= 86_400:
      state = .staleCache(snapshot.fetchedAt)
    case .cached:
      state = .cached(snapshot.fetchedAt)
    case .remote, .fixture:
      state = .rate(snapshot.fetchedAt)
    }
    return CurrencyRateResolution(rate: rate, state: state)
  }
}

private enum DecimalConversionMath {
  static func multiply(_ left: Decimal, by right: Decimal) throws -> Decimal {
    var left = left
    var right = right
    var result = Decimal()
    let status = NSDecimalMultiply(&result, &left, &right, .bankers)
    try validate(status, result: result)
    return result
  }

  static func divide(_ numerator: Decimal, by denominator: Decimal) throws -> Decimal {
    guard NSDecimalNumber(decimal: denominator).compare(NSDecimalNumber.zero) != .orderedSame else {
      throw CurrencyResolutionError.invalidRate
    }
    var numerator = numerator
    var denominator = denominator
    var result = Decimal()
    let status = NSDecimalDivide(&result, &numerator, &denominator, .bankers)
    try validate(status, result: result)
    return result
  }

  private static func validate(_ status: Decimal.CalculationError, result: Decimal) throws {
    guard
      status == .noError || status == .lossOfPrecision,
      !result.isNaN
    else {
      throw CurrencyResolutionError.invalidRate
    }
  }
}

private enum UnitRuntimeMapping {
  static let supportedIDs: Set<String> = [
    "meter", "kilometer", "centimeter", "millimeter", "mile", "yard", "foot", "inch",
    "nauticalMile", "squareMeter", "squareKilometer", "squareFoot", "squareMile", "acre",
    "hectare", "liter", "milliliter", "cubicMeter", "gallonUS", "quartUS", "pintUS",
    "cupUS", "fluidOunceUS", "gram", "kilogram", "milligram", "metricTon", "pound",
    "ounce", "stone", "celsius", "fahrenheit", "kelvin",
  ]

  static func convert(
    _ value: Decimal,
    source: UnitDefinition,
    target: UnitDefinition
  ) throws -> Decimal {
    let input = NSDecimalNumber(decimal: value).doubleValue
    guard input.isFinite else { throw CurrencyResolutionError.invalidRate }
    let output: Double
    switch source.category {
    case .distance:
      output = try convertLength(input, source: source.id, target: target.id)
    case .area:
      output = try convertArea(input, source: source.id, target: target.id)
    case .volume:
      output = try convertVolume(input, source: source.id, target: target.id)
    case .mass:
      output = try convertMass(input, source: source.id, target: target.id)
    case .temperature:
      output = try convertTemperature(input, source: source.id, target: target.id)
    }
    let nearestInteger = output.rounded()
    let normalizedOutput = abs(output - nearestInteger) < 0.000_000_001 ? nearestInteger : output
    guard normalizedOutput.isFinite,
      let decimal = Decimal(
        string: String(normalizedOutput),
        locale: Locale(identifier: "en_US_POSIX")
      )
    else {
      throw CurrencyResolutionError.invalidRate
    }
    return decimal
  }

  private static func convertLength(_ value: Double, source: String, target: String) throws
    -> Double
  {
    let sourceUnit: UnitLength
    let targetUnit: UnitLength
    switch source {
    case "meter": sourceUnit = .meters
    case "kilometer": sourceUnit = .kilometers
    case "centimeter": sourceUnit = .centimeters
    case "millimeter": sourceUnit = .millimeters
    case "mile": sourceUnit = .miles
    case "yard": sourceUnit = .yards
    case "foot": sourceUnit = .feet
    case "inch": sourceUnit = .inches
    case "nauticalMile": sourceUnit = .nauticalMiles
    default: throw ConversionFixtureError.unknownUnitID(source)
    }
    switch target {
    case "meter": targetUnit = .meters
    case "kilometer": targetUnit = .kilometers
    case "centimeter": targetUnit = .centimeters
    case "millimeter": targetUnit = .millimeters
    case "mile": targetUnit = .miles
    case "yard": targetUnit = .yards
    case "foot": targetUnit = .feet
    case "inch": targetUnit = .inches
    case "nauticalMile": targetUnit = .nauticalMiles
    default: throw ConversionFixtureError.unknownUnitID(target)
    }
    return Measurement(value: value, unit: sourceUnit).converted(to: targetUnit).value
  }

  private static func convertArea(_ value: Double, source: String, target: String) throws -> Double
  {
    let sourceUnit: UnitArea
    let targetUnit: UnitArea
    switch source {
    case "squareMeter": sourceUnit = .squareMeters
    case "squareKilometer": sourceUnit = .squareKilometers
    case "squareFoot": sourceUnit = .squareFeet
    case "squareMile": sourceUnit = .squareMiles
    case "acre": sourceUnit = .acres
    case "hectare": sourceUnit = .hectares
    default: throw ConversionFixtureError.unknownUnitID(source)
    }
    switch target {
    case "squareMeter": targetUnit = .squareMeters
    case "squareKilometer": targetUnit = .squareKilometers
    case "squareFoot": targetUnit = .squareFeet
    case "squareMile": targetUnit = .squareMiles
    case "acre": targetUnit = .acres
    case "hectare": targetUnit = .hectares
    default: throw ConversionFixtureError.unknownUnitID(target)
    }
    return Measurement(value: value, unit: sourceUnit).converted(to: targetUnit).value
  }

  private static func convertVolume(_ value: Double, source: String, target: String) throws
    -> Double
  {
    let sourceUnit: UnitVolume
    let targetUnit: UnitVolume
    switch source {
    case "liter": sourceUnit = .liters
    case "milliliter": sourceUnit = .milliliters
    case "cubicMeter": sourceUnit = .cubicMeters
    case "gallonUS": sourceUnit = .gallons
    case "quartUS": sourceUnit = .quarts
    case "pintUS": sourceUnit = .pints
    case "cupUS": sourceUnit = .cups
    case "fluidOunceUS": sourceUnit = .fluidOunces
    default: throw ConversionFixtureError.unknownUnitID(source)
    }
    switch target {
    case "liter": targetUnit = .liters
    case "milliliter": targetUnit = .milliliters
    case "cubicMeter": targetUnit = .cubicMeters
    case "gallonUS": targetUnit = .gallons
    case "quartUS": targetUnit = .quarts
    case "pintUS": targetUnit = .pints
    case "cupUS": targetUnit = .cups
    case "fluidOunceUS": targetUnit = .fluidOunces
    default: throw ConversionFixtureError.unknownUnitID(target)
    }
    return Measurement(value: value, unit: sourceUnit).converted(to: targetUnit).value
  }

  private static func convertMass(_ value: Double, source: String, target: String) throws -> Double
  {
    let sourceUnit: UnitMass
    let targetUnit: UnitMass
    switch source {
    case "gram": sourceUnit = .grams
    case "kilogram": sourceUnit = .kilograms
    case "milligram": sourceUnit = .milligrams
    case "metricTon": sourceUnit = .metricTons
    case "pound": sourceUnit = .pounds
    case "ounce": sourceUnit = .ounces
    case "stone": sourceUnit = .stones
    default: throw ConversionFixtureError.unknownUnitID(source)
    }
    switch target {
    case "gram": targetUnit = .grams
    case "kilogram": targetUnit = .kilograms
    case "milligram": targetUnit = .milligrams
    case "metricTon": targetUnit = .metricTons
    case "pound": targetUnit = .pounds
    case "ounce": targetUnit = .ounces
    case "stone": targetUnit = .stones
    default: throw ConversionFixtureError.unknownUnitID(target)
    }
    return Measurement(value: value, unit: sourceUnit).converted(to: targetUnit).value
  }

  private static func convertTemperature(
    _ value: Double,
    source: String,
    target: String
  ) throws -> Double {
    let sourceUnit: UnitTemperature
    let targetUnit: UnitTemperature
    switch source {
    case "celsius": sourceUnit = .celsius
    case "fahrenheit": sourceUnit = .fahrenheit
    case "kelvin": sourceUnit = .kelvin
    default: throw ConversionFixtureError.unknownUnitID(source)
    }
    switch target {
    case "celsius": targetUnit = .celsius
    case "fahrenheit": targetUnit = .fahrenheit
    case "kelvin": targetUnit = .kelvin
    default: throw ConversionFixtureError.unknownUnitID(target)
    }
    return Measurement(value: value, unit: sourceUnit).converted(to: targetUnit).value
  }
}

struct ConversionLineParser: Sendable {
  private struct UnitCandidate {
    let amountSource: String
    let amountRange: NSRange
    let source: UnitDefinition
    let target: UnitDefinition
  }

  private struct CurrencyCandidate {
    let amountSource: String
    let amountRange: NSRange
    let source: CurrencyCode
    let target: CurrencyCode
  }

  let settings: MathSettings
  let locale: MathDecimalLocale
  let catalogs: ConversionCatalogs
  let context: CurrencyConversionContext

  func evaluate(
    source: String,
    sourceRange: NSRange,
    anchorUTF16Offset: Int
  ) -> BasicMathLineEvaluation? {
    let nsSource = source as NSString
    let fullLocalRange = NSRange(location: 0, length: nsSource.length)
    let operatorMatches = Self.conversionOperator.matches(
      in: source,
      range: fullLocalRange
    )
    var deferredDiagnostic: BasicMathDiagnostic?
    for match in operatorMatches {
      let leftRange = Self.trim(
        NSRange(location: 0, length: match.range.location),
        in: nsSource
      )
      let rightRange = Self.trim(
        NSRange(
          location: NSMaxRange(match.range),
          length: nsSource.length - NSMaxRange(match.range)
        ),
        in: nsSource
      )
      let left = nsSource.substring(with: leftRange)
      let right = nsSource.substring(with: rightRange)

      if let target = catalogs.units.unit(matching: right) {
        if let sourceMatch = unitSuffix(in: left, localRange: leftRange) {
          guard sourceMatch.definition.category == target.category else {
            deferredDiagnostic = diagnostic(
              .conversionIncompatibleUnits,
              range: rightRange,
              base: sourceRange.location,
              message: "The source and target units use incompatible dimensions."
            )
            continue
          }
          return evaluateUnit(
            UnitCandidate(
              amountSource: sourceMatch.amount,
              amountRange: sourceMatch.amountRange,
              source: sourceMatch.definition,
              target: target
            ),
            sourceRange: sourceRange,
            anchorUTF16Offset: anchorUTF16Offset
          )
        }
        deferredDiagnostic = diagnostic(
          .conversionUnknownSourceUnit,
          range: leftRange,
          base: sourceRange.location,
          message: "The source unit is not recognized."
        )
        continue
      }

      if let targetCode = exactCurrencyCode(right), catalogs.currencies.contains(targetCode) {
        switch currencySource(in: left, localRange: leftRange, allowsOmission: true) {
        case .candidate(let amount, let amountRange, let sourceCode):
          return evaluateCurrency(
            CurrencyCandidate(
              amountSource: amount,
              amountRange: amountRange,
              source: sourceCode,
              target: targetCode
            ),
            sourceRange: sourceRange,
            anchorUTF16Offset: anchorUTF16Offset
          )
        case .unknownCode(let range):
          deferredDiagnostic = diagnostic(
            .currencyUnknownCode,
            range: range,
            base: sourceRange.location,
            message: "The source currency code is not recognized."
          )
          continue
        case .notCurrency:
          break
        }
      }

      if let targetCode = exactCurrencyCode(right), !catalogs.currencies.contains(targetCode),
        currencySource(in: left, localRange: leftRange, allowsOmission: true).isCurrencyShaped
      {
        deferredDiagnostic = diagnostic(
          .currencyUnknownCode,
          range: rightRange,
          base: sourceRange.location,
          message: "The target currency code is not recognized."
        )
        continue
      }

      if unitSuffix(in: left, localRange: leftRange) != nil {
        if beginsWithConversionTarget(right) {
          deferredDiagnostic = diagnostic(
            .conversionCompositionUnsupported,
            range: rightRange,
            base: sourceRange.location,
            message: "Arithmetic after a conversion target is not supported."
          )
        } else {
          deferredDiagnostic = diagnostic(
            .conversionUnknownTargetUnit,
            range: rightRange,
            base: sourceRange.location,
            message: "The target unit is not recognized."
          )
        }
      } else if beginsWithCurrencyTarget(right) {
        deferredDiagnostic = diagnostic(
          .conversionCompositionUnsupported,
          range: rightRange,
          base: sourceRange.location,
          message: "Arithmetic after a conversion target is not supported."
        )
      }
    }

    if let deferredDiagnostic {
      return .diagnostic(deferredDiagnostic)
    }
    if operatorMatches.isEmpty {
      let trimmedRange = Self.trim(fullLocalRange, in: nsSource)
      let trimmedSource = nsSource.substring(with: trimmedRange)
      switch currencySource(
        in: trimmedSource,
        localRange: trimmedRange,
        allowsOmission: false
      ) {
      case .candidate(let amount, let amountRange, let sourceCode):
        return evaluateCurrency(
          CurrencyCandidate(
            amountSource: amount,
            amountRange: amountRange,
            source: sourceCode,
            target: settings.secondaryCurrency
          ),
          sourceRange: sourceRange,
          anchorUTF16Offset: anchorUTF16Offset
        )
      case .unknownCode(let range):
        return .diagnostic(
          diagnostic(
            .currencyUnknownCode,
            range: range,
            base: sourceRange.location,
            message: "The source currency code is not recognized."
          )
        )
      case .notCurrency:
        break
      }
    }
    return nil
  }

  private func evaluateUnit(
    _ candidate: UnitCandidate,
    sourceRange: NSRange,
    anchorUTF16Offset: Int
  ) -> BasicMathLineEvaluation {
    do {
      let expression = try BasicMathExpressionEngine(locale: locale).evaluate(
        candidate.amountSource,
        sourceRange: offset(candidate.amountRange, by: sourceRange.location)
      )
      let value = try UnitRuntimeMapping.convert(
        expression.value,
        source: candidate.source,
        target: candidate.target
      )
      let formatter = BasicMathFormatter(settings: settings, locale: locale)
      let canonical = formatter.canonical(value)
      return .result(
        BasicMathResult(
          expressionRange: sourceRange,
          anchorUTF16Offset: anchorUTF16Offset,
          expression: expression.expression,
          canonicalValue: canonical,
          displayText: "\(formatter.display(value)) \(candidate.target.symbol)",
          copiedText: "\(canonical) \(candidate.target.symbol)"
        )
      )
    } catch let diagnostic as BasicMathDiagnostic {
      return .diagnostic(diagnostic)
    } catch {
      return .diagnostic(
        diagnostic(
          .conversionOverflow,
          range: candidate.amountRange,
          base: sourceRange.location,
          message: "The converted value exceeds the supported numeric range."
        )
      )
    }
  }

  private func evaluateCurrency(
    _ candidate: CurrencyCandidate,
    sourceRange: NSRange,
    anchorUTF16Offset: Int
  ) -> BasicMathLineEvaluation {
    do {
      let expression = try BasicMathExpressionEngine(locale: locale).evaluate(
        candidate.amountSource,
        sourceRange: offset(candidate.amountRange, by: sourceRange.location)
      )
      let resolution = try CurrencyRateResolver(settings: settings, context: context).resolve(
        source: candidate.source,
        target: candidate.target
      )
      let value = try DecimalConversionMath.multiply(expression.value, by: resolution.rate)
      let formatter = BasicMathFormatter(settings: settings, locale: locale)
      let canonical = formatter.canonical(value)
      let target = candidate.target.rawValue
      return .result(
        BasicMathResult(
          expressionRange: sourceRange,
          anchorUTF16Offset: anchorUTF16Offset,
          expression: expression.expression,
          canonicalValue: canonical,
          displayText: "\(formatter.display(value)) \(target) · \(resolution.state.label)",
          copiedText: "\(canonical) \(target)"
        )
      )
    } catch let diagnostic as BasicMathDiagnostic {
      return .diagnostic(diagnostic)
    } catch CurrencyResolutionError.unavailable {
      return .diagnostic(
        diagnostic(
          .currencyRatesUnavailable,
          range: sourceRange,
          base: 0,
          message: "Currency rates are unavailable. Refresh rates or configure a custom rate."
        )
      )
    } catch CurrencyResolutionError.missingRate {
      return .diagnostic(
        diagnostic(
          .currencyRateMissing,
          range: sourceRange,
          base: 0,
          message: "The current rate snapshot does not contain this currency pair."
        )
      )
    } catch {
      return .diagnostic(
        diagnostic(
          .currencyInvalidRate,
          range: sourceRange,
          base: 0,
          message: "The selected currency rate is invalid."
        )
      )
    }
  }

  private enum CurrencySourceMatch {
    case candidate(String, NSRange, CurrencyCode)
    case unknownCode(NSRange)
    case notCurrency

    var isCurrencyShaped: Bool {
      switch self {
      case .candidate, .unknownCode: true
      case .notCurrency: false
      }
    }
  }

  private func currencySource(
    in value: String,
    localRange: NSRange,
    allowsOmission: Bool
  ) -> CurrencySourceMatch {
    let nsValue = value as NSString
    let valueRange = NSRange(location: 0, length: nsValue.length)
    if let codeMatch = Self.trailingCurrencyCode.firstMatch(in: value, range: valueRange) {
      let code = CurrencyCode(rawValue: nsValue.substring(with: codeMatch.range(at: 1)))
      let amountLocal = Self.trim(
        NSRange(location: 0, length: codeMatch.range.location),
        in: nsValue
      )
      let amountRange = offset(amountLocal, by: localRange.location)
      guard catalogs.currencies.contains(code) else {
        return .unknownCode(offset(codeMatch.range(at: 1), by: localRange.location))
      }
      guard amountLocal.length > 0 else { return .notCurrency }
      return .candidate(nsValue.substring(with: amountLocal), amountRange, code)
    }

    let symbol = settings.primaryCurrencySymbol
    if value.hasPrefix(symbol) {
      let amountLocal = Self.trim(
        NSRange(location: symbol.utf16.count, length: nsValue.length - symbol.utf16.count),
        in: nsValue
      )
      guard amountLocal.length > 0 else { return .notCurrency }
      return .candidate(
        nsValue.substring(with: amountLocal),
        offset(amountLocal, by: localRange.location),
        settings.primaryCurrency
      )
    }
    if value.hasSuffix(symbol) {
      let amountLocal = Self.trim(
        NSRange(location: 0, length: nsValue.length - symbol.utf16.count),
        in: nsValue
      )
      guard amountLocal.length > 0 else { return .notCurrency }
      return .candidate(
        nsValue.substring(with: amountLocal),
        offset(amountLocal, by: localRange.location),
        settings.primaryCurrency
      )
    }
    if allowsOmission, !value.isEmpty {
      return .candidate(value, localRange, settings.primaryCurrency)
    }
    return .notCurrency
  }

  private func exactCurrencyCode(_ value: String) -> CurrencyCode? {
    guard value.utf8.count == 3,
      value.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0)
      })
    else { return nil }
    return CurrencyCode(rawValue: value)
  }

  private func unitSuffix(
    in value: String,
    localRange: NSRange
  ) -> (definition: UnitDefinition, amount: String, amountRange: NSRange)? {
    let nsValue = value as NSString
    let candidates = catalogs.units.units.flatMap { definition in
      definition.aliases.map { (definition, $0) }
    }.sorted { left, right in
      UnitCatalog.normalize(left.1).utf16.count > UnitCatalog.normalize(right.1).utf16.count
    }
    for (definition, alias) in candidates {
      let words = alias.split(whereSeparator: { $0.isWhitespace })
      let pattern = words.map { NSRegularExpression.escapedPattern(for: String($0)) }
        .joined(separator: #"[\t ]+"#)
      guard
        let expression = try? NSRegularExpression(
          pattern: "(?:^|[\\t ])(\(pattern))$",
          options: [.caseInsensitive]
        ),
        let match = expression.firstMatch(
          in: value,
          range: NSRange(location: 0, length: nsValue.length)
        )
      else { continue }
      let aliasRange = match.range(at: 1)
      let amountLocal = Self.trim(
        NSRange(location: 0, length: aliasRange.location),
        in: nsValue
      )
      guard amountLocal.length > 0 else { continue }
      return (
        definition,
        nsValue.substring(with: amountLocal),
        offset(amountLocal, by: localRange.location)
      )
    }
    return nil
  }

  private func beginsWithConversionTarget(_ value: String) -> Bool {
    let normalized = UnitCatalog.normalize(value)
    return catalogs.units.units.contains { definition in
      definition.aliases.contains { alias in
        let alias = UnitCatalog.normalize(alias)
        return normalized.hasPrefix(alias + " ")
      }
    }
  }

  private func beginsWithCurrencyTarget(_ value: String) -> Bool {
    let parts = value.split(whereSeparator: { $0.isWhitespace })
    guard let first = parts.first, parts.count > 1,
      let code = exactCurrencyCode(String(first))
    else { return false }
    return catalogs.currencies.contains(code)
  }

  private func diagnostic(
    _ code: BasicMathDiagnosticCode,
    range: NSRange,
    base: Int,
    message: String
  ) -> BasicMathDiagnostic {
    BasicMathDiagnostic(code: code, sourceRange: offset(range, by: base), message: message)
  }

  private func offset(_ range: NSRange, by amount: Int) -> NSRange {
    NSRange(location: range.location + amount, length: range.length)
  }

  private static func trim(_ range: NSRange, in source: NSString) -> NSRange {
    var start = range.location
    var end = NSMaxRange(range)
    while start < end, isHorizontalWhitespace(source.character(at: start)) { start += 1 }
    while end > start, isHorizontalWhitespace(source.character(at: end - 1)) { end -= 1 }
    return NSRange(location: start, length: end - start)
  }

  private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
    character == 0x0020 || character == 0x0009
  }

  private static let conversionOperator = try! NSRegularExpression(
    pattern: #"(?<=[\t ])(?:in|to)(?=[\t ])"#,
    options: [.caseInsensitive]
  )
  private static let trailingCurrencyCode = try! NSRegularExpression(
    pattern: #"(?:^|[\t ])([A-Za-z]{3})$"#
  )
}
