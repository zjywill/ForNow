import AppKit
import ForNowCore
import ForNowEditor
import ForNowModes
import XCTest

final class ConversionTests: XCTestCase {
  private let rateDate = Date(timeIntervalSince1970: 1_700_000_000)

  func test_UT_MATH_003A_DistanceUsesNumericExpressionBeforeMeasurementConversion() throws {
    let value = try result("(10 + 5) ft to m")

    XCTAssertEqual(value.canonicalValue, "4.572")
    XCTAssertEqual(value.displayText, "4.57 m")
    XCTAssertEqual(value.copiedText, "4.572 m")
  }

  func test_UT_MATH_003B_AreaAliasesMapToFoundationMeasurement() throws {
    XCTAssertEqual(try result("1 hectare in m2").canonicalValue, "10000")
  }

  func test_UT_MATH_003C_VolumeAliasesMapToUSFoundationUnits() throws {
    XCTAssertEqual(try result("1 gal in l").canonicalValue, "3.78541")
  }

  func test_UT_MATH_003D_MassAliasesMapToFoundationMeasurement() throws {
    XCTAssertEqual(try result("1 lb in kg").canonicalValue, "0.453592")
  }

  func test_UT_MATH_003E_TemperatureUsesDimensionAwareConversion() throws {
    XCTAssertEqual(try result("32 f in c").canonicalValue, "0")
    XCTAssertEqual(try result("0 c to f").canonicalValue, "32")
  }

  func test_UT_MATH_003F_LongestCompleteAliasAndWhitespaceFoldingAreDeterministic() throws {
    let value = try result("1 nautical   mile in km")

    XCTAssertEqual(value.canonicalValue, "1.852")
    XCTAssertEqual(value.copiedText, "1.852 km")
  }

  func test_UT_MATH_003G_IncompatibleDimensionsProduceStableDiagnostic() throws {
    XCTAssertEqual(try diagnostic("1 km in kg").code, .conversionIncompatibleUnits)
  }

  func test_UT_MATH_003H_ArithmeticAfterTargetIsRejected() throws {
    XCTAssertEqual(
      try diagnostic("1 km in m + 2").code,
      .conversionCompositionUnsupported
    )
  }

  func test_UT_MATH_003I_UnknownSourceUnitProducesStableDiagnostic() throws {
    XCTAssertEqual(try diagnostic("1 parsec in m").code, .conversionUnknownSourceUnit)
  }

  func test_UT_MATH_003J_UnknownTargetUnitProducesStableDiagnostic() throws {
    XCTAssertEqual(try diagnostic("1 km in parsec").code, .conversionUnknownTargetUnit)
  }

  func test_UT_MATH_003K_BundledFixturesCoverAllCategoriesAndRuntimeMappings() throws {
    let catalogs = try ConversionFixtureLoader.loadBundled()

    XCTAssertEqual(Set(catalogs.units.units.map(\.category)), Set(UnitCategory.allCases))
    XCTAssertEqual(catalogs.units.units.count, 33)
    XCTAssertEqual(catalogs.currencies.currencies.count, 25)
  }

  func test_UT_MATH_003L_DuplicateNormalizedAliasesAreRejected() throws {
    var fixtures = minimalUnitFixtures()
    fixtures[.area] = fixture(
      category: .area,
      id: "squareMeter",
      symbol: "m2",
      aliases: ["M"]
    )

    XCTAssertThrowsError(try ConversionFixtureLoader.loadUnits(fixtures)) { error in
      XCTAssertEqual(error as? ConversionFixtureError, .duplicateUnitAlias("m"))
    }
  }

  func test_UT_MATH_003M_ResultRangesAndProjectionCopyStaySourceOnly() throws {
    let source = "math\r\n  1 km in m =  \r\n"
    let evaluation = try XCTUnwrap(BasicMathDocumentParser().parse(in: source).first)
    let value = try result(from: evaluation)
    let projection = SpikeProjectionParser().parse(SourceSnapshot(version: 2, text: source))
    let decoration = try XCTUnwrap(
      projection.decorations.first { if case .result = $0 { true } else { false } }
    )

    XCTAssertEqual(value.expressionRange, (source as NSString).range(of: "1 km in m"))
    XCTAssertEqual(ProjectionCopyPolicy().copyText(for: decoration), "1000 m")
    XCTAssertEqual(source, "math\r\n  1 km in m =  \r\n")
  }

  func test_UT_MATH_003N_FixtureVersionsAndModeEligibilityAreEnforced() throws {
    var fixtures = minimalUnitFixtures()
    fixtures[.distance] = Data(
      #"{"schemaVersion":2,"category":"distance","units":[]}"#.utf8
    )

    XCTAssertThrowsError(try ConversionFixtureLoader.loadUnits(fixtures)) { error in
      XCTAssertEqual(error as? ConversionFixtureError, .unsupportedSchemaVersion(2))
    }
    XCTAssertTrue(BasicMathDocumentParser().parse(in: "list\n1 km in m =").isEmpty)
    XCTAssertTrue(BasicMathDocumentParser().parse(in: "1 km in m =").isEmpty)
  }

  func test_UT_MATH_004A_ExplicitCodesUseProviderSnapshot() throws {
    let value = try result(
      "100 USD in EUR",
      context: context(source: .remote, rates: ["USD": 1, "EUR": 0.8])
    )

    XCTAssertEqual(value.canonicalValue, "80")
    XCTAssertEqual(value.displayText, "80 EUR · rate 2023-11-14")
    XCTAssertEqual(value.copiedText, "80 EUR")
  }

  func test_UT_MATH_004B_PrimaryCurrencyFillsOmittedSource() throws {
    let settings = MathSettings(
      primaryCurrency: CurrencyCode(rawValue: "GBP"),
      secondaryCurrency: CurrencyCode(rawValue: "EUR")
    )
    let value = try result(
      "100 in EUR",
      settings: settings,
      context: context(base: "GBP", source: .remote, rates: ["GBP": 1, "EUR": 1.2])
    )

    XCTAssertEqual(value.canonicalValue, "120")
  }

  func test_UT_MATH_004C_SecondaryCurrencyFillsOmittedTarget() throws {
    let value = try result(
      "100 USD",
      context: context(source: .remote, rates: ["USD": 1, "EUR": 0.8])
    )

    XCTAssertEqual(value.copiedText, "80 EUR")
  }

  func test_UT_MATH_004D_ConfiguredPrimarySymbolWorksBeforeOrAfterAmount() throws {
    let settings = MathSettings(primaryCurrencySymbol: "US$")
    let context = context(source: .remote, rates: ["USD": 1, "EUR": 0.8])

    XCTAssertEqual(try result("US$100", settings: settings, context: context).canonicalValue, "80")
    XCTAssertEqual(try result("100US$", settings: settings, context: context).canonicalValue, "80")
  }

  func test_UT_MATH_004E_DirectCustomRateOverridesProviderRate() throws {
    let settings = MathSettings(
      customCurrencyRates: [
        CustomCurrencyRate(
          source: CurrencyCode(rawValue: "USD"),
          target: CurrencyCode(rawValue: "EUR"),
          rate: 0.9,
          updatedAt: rateDate
        )
      ]
    )
    let value = try result(
      "100 USD",
      settings: settings,
      context: context(source: .remote, rates: ["USD": 1, "EUR": 0.8])
    )

    XCTAssertEqual(value.canonicalValue, "90")
    XCTAssertEqual(value.displayText, "90 EUR · custom 2023-11-14")
  }

  func test_UT_MATH_004F_InverseCustomRatePrecedesProviderCrossRate() throws {
    let settings = MathSettings(
      customCurrencyRates: [
        CustomCurrencyRate(
          source: CurrencyCode(rawValue: "EUR"),
          target: CurrencyCode(rawValue: "USD"),
          rate: 2,
          updatedAt: rateDate
        )
      ]
    )

    XCTAssertEqual(
      try result(
        "100 USD",
        settings: settings,
        context: context(source: .remote, rates: ["USD": 1, "EUR": 0.8])
      ).canonicalValue,
      "50"
    )
  }

  func test_UT_MATH_004G_ProviderCrossRateUsesSnapshotBase() throws {
    let settings = MathSettings(
      primaryCurrency: CurrencyCode(rawValue: "USD"),
      secondaryCurrency: CurrencyCode(rawValue: "GBP")
    )
    let value = try result(
      "100 USD",
      settings: settings,
      context: context(base: "EUR", source: .remote, rates: ["EUR": 1, "USD": 1.25, "GBP": 0.8])
    )

    XCTAssertEqual(value.canonicalValue, "64")
  }

  func test_UT_MATH_004H_CacheAtTwentyFourHoursIsExplicitlyStale() throws {
    let value = try result(
      "100 USD",
      context: context(
        source: .cached,
        rates: ["USD": 1, "EUR": 0.8],
        evaluationDate: rateDate.addingTimeInterval(86_400)
      )
    )

    XCTAssertEqual(value.displayText, "80 EUR · stale cache 2023-11-14")
  }

  func test_UT_MATH_004I_FreshCacheRemainsLabeledCached() throws {
    let value = try result(
      "100 USD",
      context: context(
        source: .cached,
        rates: ["USD": 1, "EUR": 0.8],
        evaluationDate: rateDate.addingTimeInterval(86_399)
      )
    )

    XCTAssertEqual(value.displayText, "80 EUR · cached 2023-11-14")
  }

  func test_UT_MATH_004J_OfflineWithoutCustomOrCacheIsClear() throws {
    XCTAssertEqual(try diagnostic("100 USD").code, .currencyRatesUnavailable)
  }

  func test_UT_MATH_004K_MissingSnapshotCurrencyHasDistinctDiagnostic() throws {
    XCTAssertEqual(
      try diagnostic(
        "100 USD",
        context: context(source: .cached, rates: ["USD": 1])
      ).code,
      .currencyRateMissing
    )
  }

  func test_UT_MATH_004L_UnknownExplicitCurrencyCodesAreRejected() throws {
    XCTAssertEqual(try diagnostic("100 XYZ in EUR").code, .currencyUnknownCode)
    XCTAssertEqual(try diagnostic("100 USD in XYZ").code, .currencyUnknownCode)
    XCTAssertEqual(try diagnostic("100 XYZ").code, .currencyUnknownCode)
  }

  func test_UT_MATH_004M_CurrencyFormattingSupportsDecimalCommaWithoutChangingCopy() throws {
    let value = try result(
      "10,5 USD",
      locale: .commaDecimal,
      context: context(source: .remote, rates: ["USD": 1, "EUR": 0.8])
    )

    XCTAssertEqual(value.displayText, "8,4 EUR · rate 2023-11-14")
    XCTAssertEqual(value.copiedText, "8.4 EUR")
  }

  func testInvalidInjectedSnapshotProducesStableRateDiagnostic() throws {
    let invalidContext = CurrencyConversionContext(
      rateSnapshot: RateSnapshot(
        base: CurrencyCode(rawValue: "USD"),
        rates: [
          CurrencyCode(rawValue: "USD"): 1,
          CurrencyCode(rawValue: "EUR"): 0,
        ],
        fetchedAt: rateDate
      ),
      evaluationDate: rateDate
    )

    XCTAssertEqual(
      try diagnostic("100 USD", context: invalidContext).code,
      .currencyInvalidRate
    )
  }

  @MainActor
  func testConversionAppKitResultsAnnounceUnitsAndCopyWithoutMetadata() async throws {
    let source = "math\n1 km in m =\n100 USD ="
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    let container = ProjectionEditorContainer(
      initialText: source,
      currencyContext: context(source: .remote, rates: ["USD": 1, "EUR": 0.8]),
      pasteboard: pasteboard
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 320),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.contentView = container
    window.makeKeyAndOrderFront(nil)
    defer {
      window.close()
      pasteboard.clearContents()
    }
    await container.waitForPendingProjection()
    await Task.yield()
    try await Task.sleep(for: .milliseconds(20))
    container.layoutSubtreeIfNeeded()
    let buttons = container.decorationAccessibilityContainer.subviews.compactMap {
      $0 as? NSButton
    }
    let unitButton = try XCTUnwrap(buttons.first { $0.title == "1,000 m" })
    let currencyButton = try XCTUnwrap(
      buttons.first { $0.title == "80 EUR · rate 2023-11-14" }
    )

    XCTAssertEqual(
      unitButton.accessibilityLabel(),
      "Calculation 1 km in m. Result 1,000 m. Copy result"
    )
    XCTAssertEqual(
      currencyButton.accessibilityLabel(),
      "Calculation 100 USD. Result 80 EUR · rate 2023-11-14. Copy result"
    )
    container.textView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
    unitButton.performClick(nil)
    XCTAssertEqual(pasteboard.string(forType: .string), "1000 m")
    currencyButton.performClick(nil)
    XCTAssertEqual(pasteboard.string(forType: .string), "80 EUR")
    XCTAssertEqual(container.textView.string, source)
  }

  private func result(
    _ expression: String,
    settings: MathSettings = MathSettings(),
    locale: MathDecimalLocale = .periodDecimal,
    context: CurrencyConversionContext = CurrencyConversionContext(
      evaluationDate: Date(timeIntervalSince1970: 1_700_000_000)
    )
  ) throws -> BasicMathResult {
    try result(
      from: XCTUnwrap(
        BasicMathDocumentParser(
          mathSettings: settings,
          locale: locale,
          currencyContext: context
        ).parse(in: "math\n\(expression) =").first
      )
    )
  }

  private func result(from evaluation: BasicMathLineEvaluation) throws -> BasicMathResult {
    guard case .result(let value) = evaluation else {
      XCTFail("Expected conversion result, received \(evaluation)")
      throw TestFailure.unexpectedEvaluation
    }
    return value
  }

  private func diagnostic(
    _ expression: String,
    context: CurrencyConversionContext = CurrencyConversionContext(
      evaluationDate: Date(timeIntervalSince1970: 1_700_000_000)
    )
  ) throws -> BasicMathDiagnostic {
    let evaluation = try XCTUnwrap(
      BasicMathDocumentParser(currencyContext: context)
        .parse(in: "math\n\(expression) =").first
    )
    guard case .diagnostic(let value) = evaluation else {
      XCTFail("Expected conversion diagnostic, received \(evaluation)")
      throw TestFailure.unexpectedEvaluation
    }
    return value
  }

  private func context(
    base: String = "USD",
    source: RateSnapshotSource,
    rates: [String: Decimal],
    evaluationDate: Date? = nil
  ) -> CurrencyConversionContext {
    CurrencyConversionContext(
      rateSnapshot: RateSnapshot(
        base: CurrencyCode(rawValue: base),
        rates: Dictionary(
          uniqueKeysWithValues: rates.map {
            (CurrencyCode(rawValue: $0.key), $0.value)
          }),
        fetchedAt: rateDate,
        source: source
      ),
      evaluationDate: evaluationDate ?? rateDate
    )
  }

  private func minimalUnitFixtures() -> [UnitCategory: Data] {
    [
      .distance: fixture(category: .distance, id: "meter", symbol: "m", aliases: ["m"]),
      .area: fixture(category: .area, id: "squareMeter", symbol: "m2", aliases: ["m2"]),
      .volume: fixture(category: .volume, id: "liter", symbol: "L", aliases: ["l"]),
      .mass: fixture(category: .mass, id: "gram", symbol: "g", aliases: ["g"]),
      .temperature: fixture(
        category: .temperature,
        id: "celsius",
        symbol: "C",
        aliases: ["c"]
      ),
    ]
  }

  private func fixture(
    category: UnitCategory,
    id: String,
    symbol: String,
    aliases: [String]
  ) -> Data {
    let aliases = aliases.map { "\"\($0)\"" }.joined(separator: ",")
    return Data(
      """
      {"schemaVersion":1,"category":"\(category.rawValue)","units":[{"id":"\(id)","symbol":"\(symbol)","aliases":[\(aliases)]}]}
      """.utf8
    )
  }

  private enum TestFailure: Error {
    case unexpectedEvaluation
  }
}
