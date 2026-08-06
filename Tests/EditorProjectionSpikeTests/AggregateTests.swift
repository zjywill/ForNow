import AppKit
import ForNowEditor
import ForNowModes
import XCTest

final class AggregateTests: XCTestCase {
  func test_UT_MATH_002A_SumExtractsTextCurrencyPunctuationAndMultipleValues() throws {
    let evaluation = try parse("sum: Expenses\nLunch $10, snacks EUR 20 dollars.\n(5), [2]")

    XCTAssertEqual(evaluation.result?.modeID, .sum)
    XCTAssertEqual(evaluation.result?.canonicalValue, "37")
    XCTAssertEqual(evaluation.result?.consumedValueCount, 4)
    XCTAssertTrue(evaluation.diagnostics.isEmpty)
  }

  func test_UT_MATH_002B_AverageUsesAcceptedValueCountAndCheckedDecimalArithmetic() throws {
    let evaluation = try parse("average\n10 and 20\n30")

    XCTAssertEqual(evaluation.result?.modeID, .average)
    XCTAssertEqual(evaluation.result?.canonicalValue, "20")
    XCTAssertEqual(evaluation.result?.consumedValueCount, 3)
  }

  func test_UT_MATH_002C_CommentsBlankLinesAndTextWithoutNumbersAreExcluded() throws {
    let source = "sum\n\n  // 100 and 200\ntext only\n5\n\t// 900"
    let evaluation = try parse(source)

    XCTAssertEqual(evaluation.result?.canonicalValue, "5")
    XCTAssertEqual(evaluation.result?.consumedValueCount, 1)
    XCTAssertTrue(evaluation.diagnostics.isEmpty)
  }

  func test_UT_MATH_002D_FractionsRejectTheWholeLineWithoutBecomingTwoValues() throws {
    let source = "avg\n1/2 and 100\n3\n½ cup\n9"
    let evaluation = try parse(source)

    XCTAssertEqual(evaluation.result?.canonicalValue, "6")
    XCTAssertEqual(evaluation.result?.consumedValueCount, 2)
    XCTAssertEqual(
      evaluation.diagnostics.map(\.code),
      [.fractionUnsupported, .fractionUnsupported]
    )
    XCTAssertEqual(
      evaluation.diagnostics.map { (source as NSString).substring(with: $0.sourceRange) },
      ["1/2 and 100", "½ cup"]
    )
  }

  func test_UT_MATH_002E_InvalidNumericLinesDoNotPoisonValidLines() throws {
    let source = "sum\n1,23 and 100\n4\n1e3\n6"
    let evaluation = try parse(source)

    XCTAssertEqual(evaluation.result?.canonicalValue, "10")
    XCTAssertEqual(evaluation.result?.consumedValueCount, 2)
    XCTAssertEqual(evaluation.diagnostics.map(\.code), [.invalidNumber, .invalidNumber])
  }

  func test_UT_MATH_002F_CountIncludesEveryNonEmptyNonCommentBodyLine() throws {
    let evaluation = try parse("count: Items\nfirst\n\n // ignored\n1/2\n1,23\ntext")

    XCTAssertEqual(evaluation.result?.modeID, .count)
    XCTAssertEqual(evaluation.result?.canonicalValue, "4")
    XCTAssertEqual(evaluation.result?.consumedValueCount, 4)
    XCTAssertTrue(evaluation.diagnostics.isEmpty)
  }

  func test_UT_MATH_002G_LocaleGroupingSignsAndDisplaySettingsAreDeterministic() throws {
    let settings = MathSettings(significantDigits: 2, separatesThousands: true)
    let evaluation = try parse(
      "sum\nEUR 1.000,25\n-,25\n+2.000,50\n−,50",
      settings: settings,
      locale: .commaDecimal
    )

    XCTAssertEqual(evaluation.result?.canonicalValue, "3000")
    XCTAssertEqual(evaluation.result?.displayText, "3.000")
    XCTAssertEqual(evaluation.result?.copiedText, "3000")
    XCTAssertEqual(evaluation.result?.consumedValueCount, 4)
  }

  func test_UT_MATH_002H_EmptyInputsHaveExplicitSumAverageAndCountResults() throws {
    let sum = try parse("sum\n\n// ignored")
    let average = try parse("avg\ntext only")
    let count = try parse("count\n\n // ignored")

    XCTAssertEqual(sum.result?.canonicalValue, "0")
    XCTAssertTrue(sum.diagnostics.isEmpty)
    XCTAssertNil(average.result)
    XCTAssertEqual(average.diagnostics.map(\.code), [.noValues])
    XCTAssertEqual(count.result?.canonicalValue, "0")
    XCTAssertTrue(count.diagnostics.isEmpty)
  }

  func test_UT_MATH_002I_BundledGoldenFixtureCoversRequiredExtractionFamilies() throws {
    let fixture = try AggregateFixtureLoader.loadBundled()

    XCTAssertEqual(fixture.schemaVersion, 1)
    XCTAssertEqual(fixture.grammarID, "fornow-aggregates-v1")
    XCTAssertEqual(
      Set(fixture.cases.map(\.id)),
      [
        "text", "currency", "punctuation", "blank-comment-text", "invalid-number", "fraction",
        "comma-locale", "count-eligibility",
      ]
    )
    for fixtureCase in fixture.cases {
      let evaluation = try XCTUnwrap(
        AggregateDocumentParser(locale: fixtureCase.locale).parse(in: fixtureCase.source),
        fixtureCase.id
      )
      XCTAssertEqual(
        evaluation.result?.canonicalValue,
        fixtureCase.expectedCanonicalValue,
        fixtureCase.id
      )
      XCTAssertEqual(
        evaluation.result?.consumedValueCount ?? 0,
        fixtureCase.expectedConsumedValueCount,
        fixtureCase.id
      )
      XCTAssertEqual(
        evaluation.diagnostics.map(\.code),
        fixtureCase.expectedDiagnosticCodes,
        fixtureCase.id
      )
    }
  }

  @MainActor
  func test_UT_MATH_002J_ResultProjectionCopyAndAccessibilityRemainSourceOnly() async throws {
    let source = "sum: Expenses\n$10\n20 dollars"
    let snapshot = SourceSnapshot(version: 7, text: source)
    let projection = SpikeProjectionParser().parse(snapshot)
    let header = try XCTUnwrap(ModeHeaderParser().parse(in: source))
    let resultDecoration = try XCTUnwrap(
      projection.decorations.first { decoration in
        if case .result = decoration { return true }
        return false
      }
    )
    guard case .result(let anchor, let presentation) = resultDecoration else {
      return XCTFail("Expected aggregate result decoration")
    }

    XCTAssertEqual(anchor.utf16Offset, NSMaxRange(header.sourceRange))
    XCTAssertEqual(presentation.expressionText, "Sum")
    XCTAssertEqual(presentation.canonicalValue, "30")
    XCTAssertEqual(ProjectionCopyPolicy().copyText(for: resultDecoration), "30")
    XCTAssertTrue(projection.diagnostics.isEmpty)
    XCTAssertEqual(snapshot.text, source)

    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    let container = ProjectionEditorContainer(initialText: source, pasteboard: pasteboard)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    defer {
      window.close()
      pasteboard.clearContents()
    }
    window.contentView = container
    window.makeKeyAndOrderFront(nil)
    container.layoutSubtreeIfNeeded()
    await container.waitForPendingProjection()
    await Task.yield()

    let resultButton = try XCTUnwrap(
      container.decorationAccessibilityContainer.subviews
        .compactMap { $0 as? NSButton }
        .first { $0.title == "30" }
    )
    XCTAssertEqual(
      resultButton.accessibilityLabel(),
      "Calculation Sum. Result 30. Copy result"
    )
    resultButton.performClick(nil)
    XCTAssertEqual(pasteboard.string(forType: .string), "30")
    XCTAssertEqual(container.textView.string, source)
  }

  func testAggregateAliasesAndNonAggregateModesKeepCanonicalIdentity() throws {
    var settings = ModeSettings()
    let averageIndex = try XCTUnwrap(settings.definitions.firstIndex { $0.modeID == .average })
    settings.definitions[averageIndex] = ModeAliasDefinition(
      modeID: .average,
      aliases: ["mean"],
      mainAlias: "mean"
    )

    let evaluation = try XCTUnwrap(
      AggregateDocumentParser(modeSettings: settings).parse(in: "MEAN: Values\n2\n4")
    )
    XCTAssertEqual(evaluation.result?.modeID, .average)
    XCTAssertEqual(evaluation.result?.canonicalValue, "3")
    XCTAssertNil(AggregateDocumentParser().parse(in: "math\n1 + 1 ="))
  }

  func testAggregateFixtureLoaderRejectsUnsupportedSchema() throws {
    let fixture = AggregateNumericFixture(
      schemaVersion: 2,
      grammarID: "fornow-aggregates-v1",
      cases: []
    )
    let data = try JSONEncoder().encode(fixture)

    XCTAssertThrowsError(try AggregateFixtureLoader.load(data)) { error in
      XCTAssertEqual(error as? AggregateFixtureError, .unsupportedSchemaVersion(2))
    }
  }

  func testAggregateResultAndDiagnosticOrderAreStable() throws {
    let source = "sum\n1/2\n2\n1,23\n4"
    let first = try parse(source)
    let second = try parse(source)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.result?.canonicalValue, "6")
    XCTAssertEqual(first.diagnostics.map(\.code), [.fractionUnsupported, .invalidNumber])
  }

  func testAggregateValueLimitRejectsAnOversizedSingleLineWithoutPartialResult() throws {
    let values = Array(repeating: "1", count: 10_001).joined(separator: " ")
    let evaluation = try parse("sum\n\(values)")

    XCTAssertNil(evaluation.result)
    XCTAssertEqual(evaluation.diagnostics.map(\.code), [.resourceLimit])
  }

  func testAggregateLineLimitRejectsPartialCount() throws {
    let lines = Array(repeating: "item", count: 10_001).joined(separator: "\n")
    let evaluation = try parse("count\n\(lines)")

    XCTAssertNil(evaluation.result)
    XCTAssertEqual(evaluation.diagnostics.map(\.code), [.resourceLimit])
  }

  func testAggregateParserChecksCancellationInsideOneLargeLine() async {
    let source = "sum\n" + String(repeating: "ordinary text ", count: 100_000)
    let task = Task.detached {
      try AggregateDocumentParser().parseCancellable(in: source)
    }
    try? await Task.sleep(for: .milliseconds(1))
    task.cancel()

    do {
      _ = try await task.value
      XCTFail("Expected aggregate parsing to be cancelled")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func parse(
    _ source: String,
    settings: MathSettings = MathSettings(),
    locale: MathDecimalLocale = .periodDecimal
  ) throws -> AggregateDocumentEvaluation {
    try XCTUnwrap(
      AggregateDocumentParser(mathSettings: settings, locale: locale).parse(in: source)
    )
  }
}
