import AppKit
import ForNowEditor
import XCTest

@testable import ForNow

final class FindReplaceModelTests: XCTestCase {
  func test_UT_NOTE_008G_FieldCommandsAreSpecificToFindAndReplacement() {
    XCTAssertEqual(
      FindReplaceCommandRouter.command(
        for: #selector(NSResponder.insertTab(_:)),
        role: .find,
        hasShiftModifier: false
      ),
      .showReplacement
    )
    XCTAssertEqual(
      FindReplaceCommandRouter.command(
        for: #selector(NSResponder.insertNewline(_:)),
        role: .find,
        hasShiftModifier: false
      ),
      .nextMatch
    )
    XCTAssertEqual(
      FindReplaceCommandRouter.command(
        for: #selector(NSResponder.insertNewline(_:)),
        role: .find,
        hasShiftModifier: true
      ),
      .previousMatch
    )
    XCTAssertEqual(
      FindReplaceCommandRouter.command(
        for: #selector(NSResponder.insertNewline(_:)),
        role: .replacement,
        hasShiftModifier: false
      ),
      .replaceCurrent
    )
    XCTAssertEqual(
      FindReplaceCommandRouter.command(
        for: #selector(NSResponder.insertNewline(_:)),
        role: .replacement,
        hasShiftModifier: true
      ),
      .replaceAll
    )
  }

  @MainActor
  func testFindReplaceModelNavigatesReplacesAndRestoresLinkPresentationPolicy() throws {
    let source = "Alpha alpha https://example.com/long/path alpha"
    let container = ProjectionEditorContainer(initialText: source)
    container.textView.setSelectedRange(NSRange(location: 0, length: 0))
    let target = EditorFindReplaceTarget()
    target.attach(to: container)
    let model = FindReplaceModel(editorTarget: target)

    model.present()
    XCTAssertTrue(model.isPresented)
    XCTAssertTrue(container.temporarilyExpandsLinks)
    model.setQuery("alpha")
    XCTAssertEqual(model.matches.count, 3)
    XCTAssertEqual(model.statusText, "1 of 3")
    model.navigate(by: -1)
    XCTAssertEqual(model.statusText, "3 of 3")

    model.showReplacement()
    model.setReplacement("beta")
    XCTAssertEqual(model.replaceAll(), 3)
    XCTAssertEqual(container.textView.string, "beta beta https://example.com/long/path beta")
    XCTAssertEqual(model.statusText, "Replaced 3")

    let undoManager = try XCTUnwrap(container.textView.undoManager)
    undoManager.undo()
    XCTAssertEqual(container.textView.string, source)

    model.setMatchMode(.regularExpression)
    model.setQuery("(")
    let sourceBeforeInvalidReplace = container.textView.string
    XCTAssertEqual(model.replaceAll(), 0)
    XCTAssertEqual(container.textView.string, sourceBeforeInvalidReplace)
    XCTAssertEqual(model.errorMessage, "Invalid regular expression.")

    model.dismiss()
    XCTAssertFalse(container.temporarilyExpandsLinks)
  }

  @MainActor
  func testReplaceCurrentAdvancesPastReplacementThatStillMatches() throws {
    let container = ProjectionEditorContainer(initialText: "alpha alpha")
    let target = EditorFindReplaceTarget()
    target.attach(to: container)
    let model = FindReplaceModel(editorTarget: target)

    model.present()
    model.setQuery("alpha")
    model.setReplacement("alphabet")

    XCTAssertTrue(model.replaceCurrent())
    XCTAssertEqual(container.textView.string, "alphabet alpha")
    XCTAssertEqual(model.selectedMatch?.range.nsRange, NSRange(location: 9, length: 5))
  }
}
