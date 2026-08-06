import ForNowEditor
import Foundation
import XCTest

final class FindReplaceTests: XCTestCase {
  func test_UT_NOTE_008A_ContainsUsesIndependentCaseSensitivity() throws {
    let source = "Alpha alpha ALPHA 你好"
    let engine = FindReplaceEngine()

    XCTAssertEqual(
      try matchedSource(
        engine.matches(
          in: source,
          request: FindRequest(query: "alpha", mode: .contains, isCaseSensitive: false)
        ),
        in: source
      ),
      ["Alpha", "alpha", "ALPHA"]
    )
    XCTAssertEqual(
      try matchedSource(
        engine.matches(
          in: source,
          request: FindRequest(query: "Alpha", mode: .contains, isCaseSensitive: true)
        ),
        in: source
      ),
      ["Alpha"]
    )
  }

  func test_UT_NOTE_008B_WholeWordUsesUnicodeWordBoundaries() throws {
    let source = "cat scatter cat_ cat 中文 中文字"
    let engine = FindReplaceEngine()

    XCTAssertEqual(
      try matchedSource(
        engine.matches(
          in: source,
          request: FindRequest(query: "cat", mode: .wholeWord)
        ),
        in: source
      ),
      ["cat", "cat"]
    )
    XCTAssertEqual(
      try matchedSource(
        engine.matches(
          in: source,
          request: FindRequest(query: "中文", mode: .wholeWord)
        ),
        in: source
      ),
      ["中文"]
    )
  }

  func test_UT_NOTE_008C_LinePrefixAndSuffixExcludeLineEndings() throws {
    let source = "alpha beta\nbeta alpha\r\nalpha\n"
    let engine = FindReplaceEngine()

    XCTAssertEqual(
      try matchedSource(
        engine.matches(
          in: source,
          request: FindRequest(query: "alpha", mode: .linePrefix)
        ),
        in: source
      ),
      ["alpha", "alpha"]
    )
    XCTAssertEqual(
      try matchedSource(
        engine.matches(
          in: source,
          request: FindRequest(query: "alpha", mode: .lineSuffix)
        ),
        in: source
      ),
      ["alpha", "alpha"]
    )
  }

  func test_UT_NOTE_008D_RegularExpressionValidationPrecedesMutation() throws {
    let source = "item-12 item-345"
    let engine = FindReplaceEngine()

    XCTAssertEqual(
      try matchedSource(
        engine.matches(
          in: source,
          request: FindRequest(query: #"(?<=item-)\d+"#, mode: .regularExpression)
        ),
        in: source
      ),
      ["12", "345"]
    )
    XCTAssertThrowsError(
      try engine.replacingAll(
        in: source,
        request: FindRequest(query: "(", mode: .regularExpression),
        replacement: "changed"
      )
    ) { error in
      XCTAssertEqual(error as? FindReplaceError, .invalidRegularExpression)
    }
    XCTAssertEqual(source, "item-12 item-345")
  }

  func test_UT_NOTE_008E_ZeroLengthRegularExpressionReplacementIsFinite() throws {
    let source = "a\nb"
    let plan = try FindReplaceEngine().replacingAll(
      in: source,
      request: FindRequest(query: "^|$", mode: .regularExpression),
      replacement: "|"
    )

    XCTAssertEqual(plan.replacementCount, 4)
    XCTAssertEqual(plan.replacementSource, "|a|\n|b|")
  }

  func test_UT_NOTE_008F_UnicodeReplacementPlanUsesOnlySourceCoordinates() throws {
    let source = "🧑🏽‍💻 alpha 📝 alpha"
    let engine = FindReplaceEngine()
    let request = FindRequest(query: "alpha", mode: .contains, isCaseSensitive: true)
    let matches = try engine.matches(in: source, request: request)
    let plan = try engine.replacingAll(in: source, request: request, replacement: "你好")

    XCTAssertEqual(try matchedSource(matches, in: source), ["alpha", "alpha"])
    XCTAssertEqual(plan.replacementSource, "🧑🏽‍💻 你好 📝 你好")
    XCTAssertEqual(plan.replacementCount, 2)
  }

  @MainActor
  func test_ET_NOTE_008_ReplaceAllIsOneUndoableSourceOnlyEdit() throws {
    let source = "alpha https://example.com/long/path alpha"
    let container = ProjectionEditorContainer(initialText: source)
    let target = EditorFindReplaceTarget()
    target.attach(to: container)
    let engine = FindReplaceEngine()
    let plan = try engine.replacingAll(
      in: target.source,
      request: FindRequest(query: "alpha"),
      replacement: "beta"
    )

    XCTAssertTrue(target.replaceAll(with: plan))
    XCTAssertEqual(container.textView.string, "beta https://example.com/long/path beta")
    XCTAssertTrue(
      try engine.matches(
        in: target.source,
        request: FindRequest(query: "/...", mode: .contains)
      ).isEmpty
    )

    let undoManager = try XCTUnwrap(container.textView.undoManager)
    undoManager.undo()
    XCTAssertEqual(container.textView.string, source)
    undoManager.redo()
    XCTAssertEqual(container.textView.string, "beta https://example.com/long/path beta")
  }

  private func matchedSource(_ matches: [FindSourceMatch], in source: String) throws -> [String] {
    let snapshot = SourceSnapshot(version: 1, text: source)
    return try matches.map { match in
      try XCTUnwrap(snapshot.substring(in: match.range))
    }
  }
}
