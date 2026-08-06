import ForNowCore
import ForNowEditor
import ForNowModes
import XCTest

final class VariableTests: XCTestCase {
  func test_UT_MATH_005A_SpacedAssignmentFeedsLaterExpression() throws {
    let source = """
      math
      number of guests: 9
      number of guests + 1 =
      """
    let result = try XCTUnwrap(results(in: source).last)

    XCTAssertEqual(result.canonicalValue, "10")
    XCTAssertEqual(result.dependencyIDs, ["number of guests"])
  }

  func test_UT_MATH_005B_ForwardReferencesAndEditsRecomputeDependents() throws {
    let initial = """
      math
      total + 1 =
      total: base * 2
      base: 4
      """
    let edited = initial.replacingOccurrences(of: "base: 4", with: "base: 5")

    XCTAssertEqual(try XCTUnwrap(results(in: initial).first).canonicalValue, "9")
    XCTAssertEqual(try XCTUnwrap(results(in: edited).first).canonicalValue, "11")
  }

  func test_UT_MATH_005C_TransitiveDependencyIDsUseDeclarationOrder() throws {
    let source = """
      math
      base amount: 100
      tax rate: 0.2
      total amount: base amount * (1 + tax rate)
      total amount =
      """
    let result = try XCTUnwrap(results(in: source).last)

    XCTAssertEqual(result.canonicalValue, "120")
    XCTAssertEqual(result.dependencyIDs, ["base amount", "tax rate", "total amount"])
  }

  func test_UT_MATH_005D_DuplicateNamesRejectEveryDeclarationAndReference() {
    let source = """
      math
      Guests: 2
      guests: 3
      GUESTS + 1 =
      """
    let duplicateDiagnostics = diagnostics(in: source).filter {
      $0.code == .variableDuplicateName
    }

    XCTAssertEqual(duplicateDiagnostics.count, 3)
    XCTAssertTrue(results(in: source).isEmpty)
  }

  func test_UT_MATH_005E_CyclesProduceStableDiagnosticsWithoutResults() {
    let source = """
      math
      first: second + 1
      second: first + 1
      first =
      """
    let cycleDiagnostics = diagnostics(in: source).filter { $0.code == .variableCycle }

    XCTAssertEqual(cycleDiagnostics.count, 3)
    XCTAssertTrue(results(in: source).isEmpty)
  }

  func test_UT_MATH_005F_DependencyDepthIsIndependentOfDeclarationOrder() {
    let declarations = (0...64).map { index in
      index == 0 ? "value 0: 1" : "value \(index): value \(index - 1) + 1"
    }
    let source = (["math"] + declarations + ["value 64 ="]).joined(separator: "\n")

    XCTAssertTrue(
      diagnostics(in: source).contains(where: { $0.code == .variableDepthLimit })
    )
    XCTAssertTrue(results(in: source).isEmpty)
  }

  func test_UT_MATH_005G_ConversionAssignmentsStoreOnlyCanonicalNumber() throws {
    let source = """
      math
      trip distance: 1 km to m
      trip distance + 1 =
      trip distance m to km =
      """
    let results = results(in: source)

    XCTAssertEqual(results.map(\.canonicalValue), ["1001", "1"])
    XCTAssertEqual(results[0].copiedText, "1001")
    XCTAssertEqual(results[1].copiedText, "1 km")
    XCTAssertEqual(results[1].dependencyIDs, ["trip distance"])
  }

  func test_UT_MATH_005H_AssignmentEqualsCanDisplayConversionMetadata() throws {
    let source = """
      math
      table width: 58 cm to in =
      table width =
      """
    let results = results(in: source)

    XCTAssertEqual(results.count, 2)
    XCTAssertTrue(results[0].displayText.hasSuffix(" in"))
    XCTAssertFalse(results[1].displayText.contains("in"))
    XCTAssertEqual(results[1].dependencyIDs, ["table width"])
  }

  func test_UT_MATH_005I_LongestCompleteCaseInsensitiveReferenceWins() throws {
    let source = """
      math
      guest: 2
      guest count: 5
      GUEST   COUNT + guest =
      """
    let result = try XCTUnwrap(results(in: source).last)

    XCTAssertEqual(result.canonicalValue, "7")
    XCTAssertEqual(result.dependencyIDs, ["guest", "guest count"])
  }

  func test_UT_MATH_005J_InvalidAndExcessDeclarationsAreBounded() {
    let declarations = (0...128).map { "value \($0): \($0)" }
    let source = (["math", "bad_name: 1"] + declarations).joined(separator: "\n")
    let codes = diagnostics(in: source).map(\.code)

    XCTAssertTrue(codes.contains(.variableInvalidDeclaration))
    XCTAssertTrue(codes.contains(.variableResourceLimit))
  }

  func testColonProseFallsBackToBasicMathWithoutConsumingDeclarationLimit() throws {
    let prose = (0...128).map { "Lunch \($0): $10 + USD 20 dollars =" }
    let declarations = (0..<128).map { "value \($0): \($0)" }
    let source = (["math"] + prose + declarations + ["value 127 ="]).joined(separator: "\n")
    let evaluations = evaluations(in: source)

    XCTAssertFalse(
      evaluations.contains {
        guard case .diagnostic(let diagnostic) = $0 else { return false }
        return diagnostic.code == .variableResourceLimit
      }
    )
    XCTAssertEqual(try XCTUnwrap(results(in: source).last).canonicalValue, "127")
  }

  func testUnreferencedUnambiguousDeclarationRemainsAvailableToAutocomplete() throws {
    let source = "math\nnumber of guests: 9\nnum"
    let context = try XCTUnwrap(
      VariableAutocompleteEngine().context(
        in: source,
        selection: NSRange(location: source.utf16.count, length: 0)
      )
    )

    XCTAssertEqual(context.suggestions.map(\.name), ["number of guests"])
  }

  func testReferenceMatchingSpansBoundedExpressionChunks() throws {
    let prose = (0..<128).map {
      "prose candidate number \($0): $10 + USD 20 dollars ="
    }
    let source =
      (["math"] + prose + ["hidden value: 2", "derived amount: hidden value + 1", "der"]).joined(
        separator: "\n")
    let context = try XCTUnwrap(
      VariableAutocompleteEngine().context(
        in: source,
        selection: NSRange(location: source.utf16.count, length: 0)
      )
    )

    XCTAssertEqual(context.suggestions.map(\.name), ["derived amount"])
  }

  func test_UT_MATH_005K_AutocompleteBeginsAtThreeCharactersInSourceOrder() throws {
    let source = """
      math
      number of guests: 9
      number of groups: 3
      num
      """
    let engine = VariableAutocompleteEngine()
    let twoCharacterSource = source.replacingOccurrences(of: "num", with: "nu")

    XCTAssertNil(
      engine.context(
        in: twoCharacterSource,
        selection: NSRange(location: twoCharacterSource.utf16.count, length: 0)
      )
    )
    let context = try XCTUnwrap(
      engine.context(
        in: source,
        selection: NSRange(location: source.utf16.count, length: 0)
      )
    )
    XCTAssertEqual(context.query, "num")
    XCTAssertEqual(context.suggestions.map(\.name), ["number of guests", "number of groups"])
  }

  func test_UT_MATH_005L_TabPlanAcceptsFirstWithoutMutatingDuringPresentation() throws {
    let source = "math\nnumber of guests: 9\nnum"
    let engine = VariableAutocompleteEngine()
    let context = try XCTUnwrap(
      engine.context(
        in: source,
        selection: NSRange(location: source.utf16.count, length: 0)
      )
    )

    XCTAssertEqual(source, "math\nnumber of guests: 9\nnum")
    let plan = try XCTUnwrap(engine.editPlan(in: source, context: context, selecting: 0))
    XCTAssertEqual(plan.replacement, "number of guests")
    XCTAssertEqual((source as NSString).substring(with: plan.replacementRange), "num")
  }

  func test_UT_MATH_005M_NumberPlanSelectsSpecificVisibleResultOnly() throws {
    let source = "math\nnumber one: 1\nnumber two: 2\nnum"
    let engine = VariableAutocompleteEngine()
    let context = try XCTUnwrap(
      engine.context(
        in: source,
        selection: NSRange(location: source.utf16.count, length: 0)
      )
    )

    XCTAssertEqual(
      engine.editPlan(in: source, context: context, selecting: 1)?.replacement,
      "number two"
    )
    XCTAssertNil(engine.editPlan(in: source, context: context, selecting: 2))
  }

  @MainActor
  func test_ET_MATH_005_AppKitAutocompleteRequiresTabNumberOrPointerConfirmation() throws {
    let source = "math\nnumber one: 1\nnumber two: 2\nnum"
    let container = ProjectionEditorContainer(initialText: source)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.contentView = container
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    container.textView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
    container.refreshVariableAutocomplete()

    XCTAssertEqual(container.textView.string, source)
    XCTAssertEqual(
      container.currentVariableAutocompleteContext?.suggestions.map(\.name),
      ["number one", "number two"]
    )
    XCTAssertNotNil(
      container.subviews.first { $0.accessibilityLabel() == "Variable autocomplete" }
    )

    container.textView.keyDown(with: keyEvent(characters: "\t", keyCode: 48))
    XCTAssertEqual(container.textView.string, "math\nnumber one: 1\nnumber two: 2\nnumber one")
    let undoManager = try XCTUnwrap(container.textView.undoManager)
    undoManager.undo()
    XCTAssertEqual(container.textView.string, source)

    container.textView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
    container.refreshVariableAutocomplete()
    container.textView.keyDown(with: keyEvent(characters: "2", keyCode: 19))
    XCTAssertEqual(container.textView.string, "math\nnumber one: 1\nnumber two: 2\nnumber two")
  }

  @MainActor
  func testAutocompleteSelectionIsolatedFromPriorUndoableEdit() throws {
    let prefix = "math\nnumber one: 1\nnumber two: 2\n"
    let container = ProjectionEditorContainer(initialText: prefix)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.contentView = container
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    container.textView.setSelectedRange(NSRange(location: prefix.utf16.count, length: 0))
    container.textView.insertText("num", replacementRange: container.textView.selectedRange())
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    container.refreshVariableAutocomplete()

    container.textView.keyDown(with: keyEvent(characters: "\t", keyCode: 48))
    XCTAssertEqual(container.textView.string, prefix + "number one")

    let undoManager = try XCTUnwrap(container.textView.undoManager)
    undoManager.undo()
    XCTAssertEqual(container.textView.string, prefix + "num")
    undoManager.undo()
    XCTAssertEqual(container.textView.string, prefix)
    undoManager.redo()
    XCTAssertEqual(container.textView.string, prefix + "num")
    undoManager.redo()
    XCTAssertEqual(container.textView.string, prefix + "number one")
  }

  func testCancelledLargeVariableParseStopsBeforeGraphPreparation() async {
    let declarations = (0..<5_000).map { "value \($0): \($0)" }
    let source = (["math"] + declarations).joined(separator: "\n")
    let task = Task {
      try BasicMathDocumentParser(locale: .periodDecimal).parseCancellable(in: source)
    }

    task.cancel()
    do {
      _ = try await task.value
      XCTFail("A cancelled variable parse must not build the graph")
    } catch is CancellationError {
      // Expected.
    } catch {
      XCTFail("Expected CancellationError, received \(error)")
    }
  }

  private func results(in source: String) -> [BasicMathResult] {
    evaluations(in: source).compactMap { evaluation in
      guard case .result(let result) = evaluation else { return nil }
      return result
    }
  }

  private func diagnostics(in source: String) -> [BasicMathDiagnostic] {
    evaluations(in: source).compactMap { evaluation in
      guard case .diagnostic(let diagnostic) = evaluation else { return nil }
      return diagnostic
    }
  }

  private func evaluations(in source: String) -> [BasicMathLineEvaluation] {
    BasicMathDocumentParser(locale: .periodDecimal).parse(in: source)
  }

  @MainActor
  private func keyEvent(characters: String, keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: keyCode
    )!
  }
}
