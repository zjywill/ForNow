import AppKit
import ForNowEditor
import ForNowModes
import XCTest

final class BasicMathTests: XCTestCase {
  func test_UT_MATH_001A_OnlyMathBodyLinesWithTrailingEqualsAreEligible() throws {
    let source = "math: Budget\n// 1 + 1 =\n1 + 1\n1 + 1 =\n"
    let evaluations = BasicMathDocumentParser().parse(in: source)

    XCTAssertEqual(evaluations.count, 1)
    XCTAssertEqual(try result(from: evaluations[0]).canonicalValue, "2")
    XCTAssertTrue(BasicMathDocumentParser().parse(in: "1 + 1 =").isEmpty)
    XCTAssertTrue(BasicMathDocumentParser().parse(in: "list\n1 + 1 =").isEmpty)
  }

  func test_UT_MATH_001B_AdditionAndSubtractionUseDecimalArithmetic() throws {
    XCTAssertEqual(try result("10.25 + 2.75 - 1").canonicalValue, "12")
  }

  func test_UT_MATH_001C_AllMultiplySpellingsAreEquivalent() throws {
    for expression in ["6 * 7", "6 x 7", "6 X 7"] {
      XCTAssertEqual(try result(expression).canonicalValue, "42")
    }
  }

  func test_UT_MATH_001D_BothDivisionSpellingsAreEquivalent() throws {
    XCTAssertEqual(try result("84 / 2").canonicalValue, "42")
    XCTAssertEqual(try result("84 ÷ 2").canonicalValue, "42")
  }

  func test_UT_MATH_001E_ParenthesesAndPrecedenceAreDeterministic() throws {
    XCTAssertEqual(try result("2 + 3 * 4").canonicalValue, "14")
    XCTAssertEqual(try result("(2 + 3) * 4").canonicalValue, "20")
  }

  func test_UT_MATH_001F_PowerIsRightAssociativeAndBindsBeforeUnaryMinus() throws {
    XCTAssertEqual(try result("2 ^ 3 ^ 2").canonicalValue, "512")
    XCTAssertEqual(try result("2 ** 3").canonicalValue, "8")
    XCTAssertEqual(try result("-2 ^ 2").canonicalValue, "-4")
    XCTAssertEqual(try result("2 ^ -2").canonicalValue, "0.25")
  }

  func test_UT_MATH_001G_AdditivePercentUsesTheLeftValueAsItsBase() throws {
    XCTAssertEqual(try result("100 + 15%").canonicalValue, "115")
    XCTAssertEqual(try result("100 - 15%").canonicalValue, "85")
  }

  func test_UT_MATH_001H_ColloquialPercentOfUsesThePercentageRatio() throws {
    XCTAssertEqual(try result("50% of 200").canonicalValue, "100")
  }

  func test_UT_MATH_001I_FactorialAndDoubleFactorialHaveDistinctSemantics() throws {
    XCTAssertEqual(try result("5!").canonicalValue, "120")
    XCTAssertEqual(try result("6!!").canonicalValue, "48")
    XCTAssertEqual(try result("0!").canonicalValue, "1")
  }

  func test_UT_MATH_001J_RootGlyphsAndFunctionAreSupported() throws {
    XCTAssertEqual(try result("√16").canonicalValue, "4")
    XCTAssertEqual(try result("∛8").canonicalValue, "2")
    XCTAssertEqual(try result("∛-8").canonicalValue, "-2")
    XCTAssertEqual(try result("sqrt(81)").canonicalValue, "9")
  }

  func test_UT_MATH_001K_LogarithmsUseDocumentedBases() throws {
    XCTAssertEqual(try result("log(1000)").canonicalValue, "3")
    XCTAssertEqual(try result("log2(8)").canonicalValue, "3")
  }

  func test_UT_MATH_001L_CeilingAndFloorHandleNegativeValues() throws {
    XCTAssertEqual(try result("ceil(12.256)").canonicalValue, "13")
    XCTAssertEqual(try result("floor(12.256)").canonicalValue, "12")
    XCTAssertEqual(try result("ceil(-12.256)").canonicalValue, "-12")
    XCTAssertEqual(try result("floor(-12.256)").canonicalValue, "-13")
  }

  func test_UT_MATH_001M_WordsAndCurrencySymbolsAreStrippedWithoutJoiningNumbers() throws {
    XCTAssertEqual(try result("Lunch: $10 + USD 20 dollars").canonicalValue, "30")
    XCTAssertEqual(try diagnostic("10 apples 20").code, .unexpectedToken)
  }

  func test_UT_MATH_001N_SurroundingPunctuationIsStripped() throws {
    XCTAssertEqual(try result("Total: ($10 + 20 USD).").canonicalValue, "30")
  }

  func test_UT_MATH_001O_CommaDecimalLocaleParsesAndFormatsDeterministically() throws {
    let value = try result(
      "1.000,25 + ,25",
      locale: .commaDecimal
    )
    XCTAssertEqual(value.canonicalValue, "1000.5")
    XCTAssertEqual(value.displayText, "1.000,5")
  }

  func test_UT_MATH_001P_PeriodDecimalLocaleValidatesGrouping() throws {
    let value = try result("1,000.25 + .75")
    XCTAssertEqual(value.canonicalValue, "1001")
    XCTAssertEqual(value.displayText, "1,001")
  }

  func test_UT_MATH_001Q_SpacedThousandsProduceTheParityDiagnostic() throws {
    XCTAssertEqual(
      try diagnostic("1 000,25", locale: .commaDecimal).code,
      .spacedThousandsUnsupported
    )
  }

  func test_UT_MATH_001R_ZeroDisplayDigitsUseHalfEvenDecimalRounding() throws {
    let settings = MathSettings(significantDigits: 0, separatesThousands: false)
    XCTAssertEqual(try result("1 / 3", settings: settings).displayText, "0")
    XCTAssertEqual(try result("2.5", settings: settings).displayText, "2")
    XCTAssertEqual(try result("3.5", settings: settings).displayText, "4")
  }

  func test_UT_MATH_001S_SevenDisplayDigitsDoNotChangeCanonicalValue() throws {
    let value = try result(
      "1 / 3",
      settings: MathSettings(significantDigits: 7, separatesThousands: false)
    )
    XCTAssertEqual(value.displayText, "0.3333333")
    XCTAssertTrue(value.canonicalValue.hasPrefix("0.333333333333"))
  }

  func test_UT_MATH_001T_ThousandsGroupingIsIndependentFromDigitCount() throws {
    let grouped = try result(
      "12345.678",
      settings: MathSettings(significantDigits: 2, separatesThousands: true)
    )
    let ungrouped = try result(
      "12345.678",
      settings: MathSettings(significantDigits: 2, separatesThousands: false)
    )
    XCTAssertEqual(grouped.displayText, "12,345.68")
    XCTAssertEqual(ungrouped.displayText, "12345.68")
    XCTAssertEqual(grouped.canonicalValue, ungrouped.canonicalValue)
  }

  func test_UT_MATH_001U_InvalidLocaleNumberProducesANonDestructiveDiagnostic() throws {
    let evaluation = try XCTUnwrap(evaluation("1,23 + 2"))
    XCTAssertEqual(try diagnostic(from: evaluation).code, .invalidNumber)
    XCTAssertEqual(source(afterEvaluating: "1,23 + 2"), "math\n1,23 + 2 =")
  }

  func test_UT_MATH_001V_DivisionByZeroProducesAStableDiagnostic() throws {
    XCTAssertEqual(try diagnostic("1 / 0").code, .divisionByZero)
  }

  func test_UT_MATH_001W_FunctionDomainsRejectNonRealResults() throws {
    XCTAssertEqual(try diagnostic("sqrt(-1)").code, .domainError)
    XCTAssertEqual(try diagnostic("log(0)").code, .domainError)
  }

  func test_UT_MATH_001X_FactorialBoundaryAndDecimalOverflowAreBounded() throws {
    XCTAssertEqual(try diagnostic("1001!").code, .factorialDomain)
    XCTAssertEqual(try diagnostic("10 ^ 1000").code, .overflow)
  }

  func test_UT_MATH_001Y_ResultCarriesExactUTF16RangeAnchorAndCopyValue() throws {
    let source = "math: Budget\r\n  1 + 2 =  \r\n"
    let result = try result(from: XCTUnwrap(BasicMathDocumentParser().parse(in: source).first))
    let expectedRange = (source as NSString).range(of: "1 + 2")
    let equalsRange = (source as NSString).range(
      of: "=", options: [],
      range: expectedRangeToEnd(
        expectedRange,
        source: source
      ))

    XCTAssertEqual(result.expressionRange, expectedRange)
    XCTAssertEqual(result.anchorUTF16Offset, NSMaxRange(equalsRange))
    XCTAssertEqual(result.canonicalValue, "3")
    XCTAssertEqual(result.copiedText, "3")
    XCTAssertEqual(source, "math: Budget\r\n  1 + 2 =  \r\n")
  }

  func test_UT_MATH_001Z_GoldenFixtureCoversEveryDocumentedSyntaxFamily() throws {
    let fixtures: [(String, String)] = [
      ("1 + 2 - 3", "0"),
      ("2 * 3 x 4 X 1", "24"),
      ("8 / 2 ÷ 2", "2"),
      ("2 ^ 3", "8"),
      ("2 ** 3", "8"),
      ("(2 + 3) * 4", "20"),
      ("100 + 15%", "115"),
      ("50% of 200", "100"),
      ("5!", "120"),
      ("6!!", "48"),
      ("√16", "4"),
      ("∛8", "2"),
      ("sqrt(16)", "4"),
      ("log(100)", "2"),
      ("log2(8)", "3"),
      ("ceil(12.256)", "13"),
      ("floor(12.256)", "12"),
    ]

    for (expression, expected) in fixtures {
      let value = try result(expression)
      XCTAssertEqual(value.canonicalValue, expected, expression)
      XCTAssertEqual(value.copiedText, expected, expression)
      XCTAssertGreaterThan(value.expressionRange.length, 0, expression)
    }
  }

  func testMathProjectionMapsResultsAndDiagnosticsWithoutChangingSource() throws {
    let source = "math\n1 + 2 =\n1 / 0 ="
    let snapshot = SourceSnapshot(version: 9, text: source)
    let projection = SpikeProjectionParser().parse(snapshot)
    let result = try XCTUnwrap(
      projection.decorations.first { decoration in
        if case .result = decoration { return true }
        return false
      }
    )

    XCTAssertEqual(ProjectionCopyPolicy().copyText(for: result), "3")
    XCTAssertEqual(projection.diagnostics.map(\.code), ["math-division-by-zero"])
    XCTAssertEqual(projection.diagnostics.first?.severity, .error)
    XCTAssertEqual(snapshot.text, source)
  }

  func testMathSettingsChangeOnlyFormattedProjection() throws {
    let source = SourceSnapshot(version: 1, text: "math\n12345.678 =")
    let grouped = SpikeProjectionParser(
      mathSettings: MathSettings(significantDigits: 2, separatesThousands: true),
      mathLocale: .periodDecimal
    ).parse(source)
    let ungrouped = SpikeProjectionParser(
      mathSettings: MathSettings(significantDigits: 1, separatesThousands: false),
      mathLocale: .periodDecimal
    ).parse(source)

    XCTAssertEqual(try projectionResult(grouped).canonicalValue, "12345.678")
    XCTAssertEqual(try projectionResult(grouped).displayText, "12,345.68")
    XCTAssertEqual(try projectionResult(ungrouped).canonicalValue, "12345.678")
    XCTAssertEqual(try projectionResult(ungrouped).displayText, "12345.7")
    XCTAssertEqual(source.text, "math\n12345.678 =")
  }

  @MainActor
  func test_ET_MATH_006A_AppKitResultsAndDiagnosticsAreAccessibleAndSourceFree() async throws {
    let source = "math\n12345.678 ="
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    let resultEditor = makeEditor(
      source: source,
      mathSettings: MathSettings(significantDigits: 2, separatesThousands: true),
      pasteboard: pasteboard
    )
    let diagnosticSource = "math\n1 / 0 ="
    let diagnosticEditor = makeEditor(source: diagnosticSource)
    defer {
      resultEditor.window.close()
      diagnosticEditor.window.close()
      pasteboard.clearContents()
    }
    await settle(resultEditor.container)
    await settle(diagnosticEditor.container)

    let resultButton = try XCTUnwrap(
      resultEditor.container.decorationAccessibilityContainer.subviews
        .compactMap { $0 as? NSButton }
        .first { $0.title == "12,345.68" }
    )
    XCTAssertEqual(resultButton.accessibilityRole(), .button)
    XCTAssertEqual(
      resultButton.accessibilityLabel(),
      "Calculation 12345.678. Result 12,345.68. Copy result"
    )
    XCTAssertEqual(resultEditor.container.textView.string, source)

    resultEditor.container.textView.setSelectedRange(
      NSRange(location: source.utf16.count, length: 0)
    )
    resultButton.performClick(nil)
    XCTAssertEqual(pasteboard.string(forType: .string), "12345.678")
    XCTAssertEqual(resultEditor.container.textView.string, source)

    resultEditor.container.textView.setSelectedRange(NSRange(location: 5, length: 4))
    resultButton.performClick(nil)
    XCTAssertEqual(pasteboard.string(forType: .string), "1234")
    XCTAssertEqual(resultEditor.container.textView.string, source)

    let diagnosticButton = try XCTUnwrap(
      diagnosticEditor.container.decorationAccessibilityContainer.subviews
        .compactMap { $0 as? NSButton }
        .first { $0.accessibilityHelp() == "math-division-by-zero" }
    )
    XCTAssertEqual(
      diagnosticButton.accessibilityLabel(),
      "Error: Division by zero is undefined."
    )
    XCTAssertEqual(
      diagnosticButton.toolTip,
      "Division by zero is undefined."
    )
    XCTAssertEqual(diagnosticEditor.container.textView.string, diagnosticSource)
  }

  private func evaluation(
    _ expression: String,
    settings: MathSettings = MathSettings(),
    locale: MathDecimalLocale = .periodDecimal
  ) -> BasicMathLineEvaluation? {
    BasicMathDocumentParser(mathSettings: settings, locale: locale)
      .parse(in: "math\n\(expression) =")
      .first
  }

  private func result(
    _ expression: String,
    settings: MathSettings = MathSettings(),
    locale: MathDecimalLocale = .periodDecimal
  ) throws -> BasicMathResult {
    try result(from: XCTUnwrap(evaluation(expression, settings: settings, locale: locale)))
  }

  private func result(from evaluation: BasicMathLineEvaluation) throws -> BasicMathResult {
    guard case .result(let result) = evaluation else {
      XCTFail("Expected a result, received \(evaluation)")
      throw TestFailure.unexpectedEvaluation
    }
    return result
  }

  private func diagnostic(
    _ expression: String,
    locale: MathDecimalLocale = .periodDecimal
  ) throws -> BasicMathDiagnostic {
    try diagnostic(from: XCTUnwrap(evaluation(expression, locale: locale)))
  }

  private func diagnostic(
    from evaluation: BasicMathLineEvaluation
  ) throws -> BasicMathDiagnostic {
    guard case .diagnostic(let diagnostic) = evaluation else {
      XCTFail("Expected a diagnostic, received \(evaluation)")
      throw TestFailure.unexpectedEvaluation
    }
    return diagnostic
  }

  private func source(afterEvaluating expression: String) -> String {
    let source = "math\n\(expression) ="
    _ = BasicMathDocumentParser().parse(in: source)
    return source
  }

  private func projectionResult(_ projection: EditorProjection) throws
    -> CalculationPresentation
  {
    for decoration in projection.decorations {
      if case .result(_, let result) = decoration {
        return result
      }
    }
    throw TestFailure.unexpectedEvaluation
  }

  private func expectedRangeToEnd(_ range: NSRange, source: String) -> NSRange {
    NSRange(location: NSMaxRange(range), length: source.utf16.count - NSMaxRange(range))
  }

  @MainActor
  private func makeEditor(
    source: String,
    mathSettings: MathSettings = MathSettings(),
    pasteboard: NSPasteboard = .general
  ) -> (window: NSWindow, container: ProjectionEditorContainer) {
    let container = ProjectionEditorContainer(
      initialText: source,
      mathSettings: mathSettings,
      pasteboard: pasteboard
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.contentView = container
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    container.layoutSubtreeIfNeeded()
    return (window, container)
  }

  @MainActor
  private func settle(_ container: ProjectionEditorContainer) async {
    await container.waitForPendingProjection()
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(20))
    container.layoutSubtreeIfNeeded()
  }

  private enum TestFailure: Error {
    case unexpectedEvaluation
  }
}
