import AppKit
import ForNowEditor
import ForNowModes
import XCTest

final class ListModeTests: XCTestCase {
  func test_UT_LIST_001A_OnlyListNotesProduceItemsAndEmptyBodiesStayEmpty() {
    XCTAssertTrue(items(in: "").isEmpty)
    XCTAssertTrue(items(in: "list").isEmpty)
    XCTAssertTrue(items(in: "list\n").isEmpty)
    XCTAssertTrue(items(in: "plain\nTask").isEmpty)
    XCTAssertTrue(items(in: "Task").isEmpty)
  }

  func test_UT_LIST_001B_EveryOrdinaryBodyLineIsAnItem() {
    let source = "list: Errands\nBuy milk\n  电话 Alice 📝  \n#### Still an item"

    XCTAssertEqual(itemSource(in: source), ["Buy milk", "  电话 Alice 📝  ", "#### Still an item"])
  }

  func test_UT_LIST_001C_BlankLinesRemainSourceSeparators() {
    let source = "list\nFirst\n\n \t \nSecond\n"

    XCTAssertEqual(itemSource(in: source), ["First", "Second"])
    XCTAssertEqual(source, "list\nFirst\n\n \t \nSecond\n")
  }

  func test_UT_LIST_001D_CommentsAreNotItems() {
    let source = "list\n// comment\n  // indented comment\n/ ordinary\nTask // suffix"

    XCTAssertEqual(itemSource(in: source), ["/ ordinary", "Task // suffix"])
  }

  func test_UT_LIST_001E_HeadingLevelsOneThroughThreeAreNotItems() {
    let source = "list\n# One\n## Two\n### Three\n#### Four\n#not-a-heading"

    XCTAssertEqual(itemSource(in: source), ["#### Four", "#not-a-heading"])
  }

  func test_UT_LIST_001F_ListModeSuppressesCalculationResults() {
    let listSource = "list\n20 + 22 =\n100 USD in EUR ="
    let listProjection = projection(for: listSource)
    let mathProjection = projection(for: "math\n20 + 22 =")

    XCTAssertEqual(checkboxes(in: listProjection).count, 2)
    XCTAssertTrue(results(in: listProjection).isEmpty)
    XCTAssertEqual(results(in: mathProjection).map(\.canonicalValue), ["42"])
  }

  func test_UT_LIST_002_PointerAndKeyboardUseTheSameTogglePlan() throws {
    let source = "list\nFirst\nSecond"
    let item = try XCTUnwrap(items(in: source).first)
    let selection = NSRange(location: 7, length: 2)
    let planner = ListModeTogglePlanner()

    let pointerPlan = planner.plan(
      in: source,
      itemRange: item.lineRange,
      selection: selection
    )
    let keyboardPlan = planner.plan(
      in: source,
      itemRange: item.lineRange,
      selection: selection
    )

    XCTAssertEqual(pointerPlan, keyboardPlan)
    XCTAssertEqual(pointerPlan?.replacementRange, NSRange(location: 10, length: 0))
    XCTAssertEqual(pointerPlan?.replacement, " /x")
    XCTAssertEqual(pointerPlan?.selectionAfterEdit, selection)
  }

  @MainActor
  func test_ET_LIST_002B_AppKitPointerAndKeyboardTogglesPreserveSelectionAndUndo() async throws {
    let pointer = makeEditor(source: "list\nTask")
    let keyboard = makeEditor(source: "list\nTask")
    defer {
      pointer.window.close()
      keyboard.window.close()
    }
    await settle(pointer.container)
    await settle(keyboard.container)

    let sourceSelection = NSRange(location: 6, length: 2)
    pointer.container.textView.setSelectedRange(sourceSelection)
    let pointerButton = try checkboxButton(in: pointer.container)
    XCTAssertEqual(pointerButton.accessibilityRole(), .checkBox)
    XCTAssertEqual(pointerButton.accessibilityValue() as? String, "Unchecked")
    XCTAssertFalse(pointer.container.hasPresentationAttributes(at: 5))
    let firstItemRect = try editorRect(
      for: NSRange(location: 5, length: 1),
      in: pointer.container
    )
    XCTAssertLessThanOrEqual(pointerButton.frame.maxX, firstItemRect.minX)

    pointerButton.performClick(nil)
    XCTAssertEqual(pointer.container.textView.string, "list\nTask /x")
    XCTAssertEqual(pointer.container.textView.selectedRange(), sourceSelection)

    let undoManager = try XCTUnwrap(pointer.container.textView.undoManager)
    XCTAssertTrue(undoManager.canUndo)
    undoManager.undo()
    XCTAssertEqual(pointer.container.textView.string, "list\nTask")
    XCTAssertEqual(pointer.container.textView.selectedRange(), sourceSelection)
    XCTAssertTrue(undoManager.canRedo)
    undoManager.redo()
    XCTAssertEqual(pointer.container.textView.string, "list\nTask /x")
    XCTAssertEqual(pointer.container.textView.selectedRange(), sourceSelection)

    keyboard.container.textView.setSelectedRange(sourceSelection)
    let keyboardButton = try checkboxButton(in: keyboard.container)
    XCTAssertTrue(keyboard.window.makeFirstResponder(keyboardButton))
    keyboardButton.keyDown(with: try spaceEvent(windowNumber: keyboard.window.windowNumber))

    XCTAssertEqual(keyboard.container.textView.string, pointer.container.textView.string)
    XCTAssertEqual(keyboard.container.textView.selectedRange(), sourceSelection)
    await settle(keyboard.container)
    let checkedButton = try checkboxButton(in: keyboard.container)
    XCTAssertEqual(checkedButton.accessibilityValue() as? String, "Checked")
  }

  func test_UT_LIST_003A_DefaultMarkerMustBeTrailingAndWhitespaceSeparated() {
    let source = "list\nChecked /x\nAlso checked\t/x  \n/x\nLiteral/x\n/x in middle text"
    let parsed = items(in: source)

    XCTAssertEqual(parsed.map(\.isChecked), [true, true, false, false, false])
    XCTAssertEqual(
      parsed.compactMap { item in
        item.markerRange.map { (source as NSString).substring(with: $0) }
      },
      [" /x", "\t/x  "]
    )
  }

  func test_UT_LIST_003B_CustomMarkerControlsParsingAndToggleEdits() throws {
    var settings = ModeSettings()
    settings.checklistTrigger = "done"
    let source = "list\nFirst /x\nSecond done"
    let parsed = items(in: source, settings: settings)

    XCTAssertEqual(parsed.map(\.isChecked), [false, true])
    let first = try XCTUnwrap(parsed.first)
    let plan = try XCTUnwrap(
      ListModeTogglePlanner().plan(
        in: source,
        itemRange: first.lineRange,
        selection: NSRange(location: source.utf16.count, length: 0),
        settings: settings
      )
    )
    XCTAssertEqual(plan.replacement, " done")
    XCTAssertEqual(apply(plan, to: source), "list\nFirst /x done\nSecond done")

    var session = ProjectionEditingSession(text: "list\nTask", modeSettings: settings)
    try session.toggleCheckbox(at: SourceOffset(utf16Offset: 6))
    XCTAssertEqual(session.snapshot.text, "list\nTask done")
  }

  func test_UT_LIST_003C_ToggleMutatesExactlyOneCorrespondingLine() throws {
    let source = "list\nFirst\nSecond /x\nThird"
    let parsed = items(in: source)
    let second = try XCTUnwrap(parsed.dropFirst().first)
    let uncheck = try XCTUnwrap(
      ListModeTogglePlanner().plan(
        in: source,
        itemRange: second.lineRange,
        selection: NSRange(location: 5, length: 5)
      )
    )

    XCTAssertEqual((source as NSString).substring(with: uncheck.replacementRange), " /x")
    XCTAssertEqual(uncheck.replacement, "")
    XCTAssertEqual(apply(uncheck, to: source), "list\nFirst\nSecond\nThird")
    XCTAssertEqual(uncheck.selectionAfterEdit, NSRange(location: 5, length: 5))
  }

  func test_UT_LIST_003D_CleanCopyObeysSettingAndOnlyRemovesEligibleMarkers() {
    let source = "list: Trip\nTask /x\n// comment /x\n# Heading /x\n#### Item /x\nLiteral /x value"
    let enabled = ExportProjectionPolicy(omitsChecklistTriggers: true)
    let disabled = ExportProjectionPolicy(omitsChecklistTriggers: false)

    XCTAssertEqual(
      CleanExportProjection().text(from: source, policy: enabled),
      "Trip\nTask\n// comment /x\n# Heading /x\n#### Item\nLiteral /x value"
    )
    XCTAssertEqual(
      CleanExportProjection().text(from: source, policy: disabled),
      "Trip\nTask /x\n// comment /x\n# Heading /x\n#### Item /x\nLiteral /x value"
    )
  }

  func test_UT_LIST_003E_MarkerSettingChangesNeverRewriteSourceAndInvalidMarkersFail() throws {
    let source = "list\nOld /x\nNew done"
    var changedSettings = ModeSettings()
    changedSettings.checklistTrigger = "done"

    XCTAssertEqual(items(in: source).map(\.isChecked), [true, false])
    XCTAssertEqual(items(in: source, settings: changedSettings).map(\.isChecked), [false, true])
    XCTAssertEqual(source, "list\nOld /x\nNew done")

    for invalid in ["", " done", "done ", "two words", "line\nbreak", "\t"] {
      var settings = ModeSettings()
      settings.checklistTrigger = invalid
      XCTAssertThrowsError(try ModeAliasRegistry(settings: settings)) { error in
        XCTAssertEqual(error as? ModeAliasRegistryError, .invalidChecklistTrigger(invalid))
      }
      XCTAssertTrue(items(in: source, settings: settings).isEmpty)
    }
  }

  private func items(
    in source: String,
    settings: ModeSettings = ModeSettings()
  ) -> [ListModeItem] {
    ListModeParser(settings: settings).parse(in: source)
  }

  private func itemSource(
    in source: String,
    settings: ModeSettings = ModeSettings()
  ) -> [String] {
    items(in: source, settings: settings).map {
      (source as NSString).substring(with: $0.lineRange)
    }
  }

  private func projection(for source: String) -> EditorProjection {
    SpikeProjectionParser().parse(SourceSnapshot(version: 1, text: source))
  }

  private func checkboxes(in projection: EditorProjection) -> [EditorDecoration] {
    projection.decorations.filter {
      if case .checkbox = $0 { return true }
      return false
    }
  }

  private func results(in projection: EditorProjection) -> [CalculationPresentation] {
    projection.decorations.compactMap {
      if case .result(_, let presentation) = $0 { return presentation }
      return nil
    }
  }

  private func apply(_ plan: ListModeTogglePlan, to source: String) -> String {
    (source as NSString).replacingCharacters(
      in: plan.replacementRange,
      with: plan.replacement
    )
  }

  @MainActor
  private func makeEditor(source: String) -> (
    window: NSWindow, container: ProjectionEditorContainer
  ) {
    let container = ProjectionEditorContainer(initialText: source)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
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

  @MainActor
  private func checkboxButton(in container: ProjectionEditorContainer) throws -> NSButton {
    try XCTUnwrap(
      container.decorationAccessibilityContainer.subviews
        .compactMap { $0 as? NSButton }
        .first { $0.accessibilityRole() == .checkBox }
    )
  }

  @MainActor
  private func editorRect(
    for range: NSRange,
    in container: ProjectionEditorContainer
  ) throws -> NSRect {
    var actualRange = NSRange(location: NSNotFound, length: 0)
    let screenRect = container.textView.firstRect(
      forCharacterRange: range,
      actualRange: &actualRange
    )
    let window = try XCTUnwrap(container.window)
    let windowRect = window.convertFromScreen(screenRect)
    let textViewRect = container.textView.convert(windowRect, from: nil)
    return container.decorationAccessibilityContainer.convert(
      textViewRect,
      from: container.textView
    )
  }

  @MainActor
  private func spaceEvent(windowNumber: Int) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: windowNumber,
        context: nil,
        characters: " ",
        charactersIgnoringModifiers: " ",
        isARepeat: false,
        keyCode: 49
      )
    )
  }
}
