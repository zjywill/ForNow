import AppKit
import ForNowEditor
import Foundation
import XCTest

final class EditorProjectionSpikeTests: XCTestCase {
  func test_UT_EDIT_002A_UTF16FixturesRoundTrip() throws {
    let fixtures = [
      "ASCII",
      "简体中文與繁體中文",
      "Emoji 📝 👨‍👩‍👧‍👦",
      "Cafe\u{301}",
      "first\nsecond\nthird",
      "مرحبا بالعالم",
    ]

    for fixture in fixtures {
      for index in fixture.indices {
        let offset = fixture[..<index].utf16.count
        let range = NSRange(location: offset, length: 0)
        XCTAssertNotNil(Range(range, in: fixture), "fixture: \(fixture), offset: \(offset)")
      }
      XCTAssertEqual(fixture.utf16.count, (fixture as NSString).length)
    }
  }

  func test_UT_EDIT_001_ProjectionNeverEntersSource() {
    let source = "[ ] Buy milk\n20 + 22 =\nhttps://example.com/a/very/long/path"
    let snapshot = SourceSnapshot(version: 7, text: source)
    let projection = SpikeProjectionParser().parse(snapshot)

    XCTAssertEqual(snapshot.text, source)
    XCTAssertFalse(snapshot.text.contains(" = 42"))
    XCTAssertTrue(
      projection.decorations.contains { decoration in
        if case .result(_, let result) = decoration { return result.canonicalValue == "42" }
        return false
      })
  }

  func test_UT_EDIT_004A_DuplicateLinksKeepOriginalURLAndStableSuffix() {
    let url = "https://example.com/a/very/long/path"
    let snapshot = SourceSnapshot(version: 1, text: "\(url)\n\(url)")
    let links = SpikeProjectionParser().parse(snapshot).decorations.compactMap { decoration in
      if case .link(_, let presentation) = decoration { return presentation }
      return nil
    }

    XCTAssertEqual(links.map(\.originalURL), [url, url])
    XCTAssertEqual(links.map(\.duplicateIndex), [1, 2])
    XCTAssertFalse(links[0].displayText.contains("· 2"))
    XCTAssertTrue(links[1].displayText.contains("· 2"))
  }

  func test_UT_CLIP_001A_CopyUsesSelectionOrExactSource() {
    let source = "中文 https://example.com/path"
    let snapshot = SourceSnapshot(version: 0, text: source)
    let policy = ProjectionCopyPolicy()
    let selectedRange = (source as NSString).range(of: "https://example.com/path")

    XCTAssertEqual(
      policy.copyText(
        from: snapshot,
        selection: SourceSelection(range: SourceRange(selectedRange))
      ),
      "https://example.com/path"
    )
    XCTAssertEqual(
      policy.copyText(
        from: snapshot,
        selection: SourceSelection(
          range: SourceRange(location: SourceOffset(utf16Offset: 0), length: 0)
        )
      ),
      source
    )
  }

  func test_UT_EDIT_002B_MultilineSelectionCopiesExactSourceRange() {
    let source = "first line\n第二行 📝\nCafe\u{301} third line"
    let snapshot = SourceSnapshot(version: 0, text: source)
    let selectedText = "line\n第二行 📝\nCafe\u{301}"
    let selection = (source as NSString).range(of: selectedText)

    XCTAssertEqual(
      ProjectionCopyPolicy().copyText(
        from: snapshot,
        selection: SourceSelection(range: SourceRange(selection))
      ),
      selectedText
    )
  }

  func test_UT_EDIT_002C_EditsBeforeInsideAndAfterDecorationsRoundTrip() throws {
    let original = "Task\n20 + 22 =\nhttps://example.com/path"
    var session = ProjectionEditingSession(text: original)

    try session.replace(
      SourceEdit(
        range: SourceRange(location: SourceOffset(utf16Offset: 0), length: 0),
        replacement: "Before\n"
      )
    )
    let pathRange = (session.snapshot.text as NSString).range(of: "/path")
    try session.replace(
      SourceEdit(
        range: SourceRange(
          location: SourceOffset(utf16Offset: pathRange.location + 1),
          length: 0
        ),
        replacement: "inside-"
      )
    )
    try session.replace(
      SourceEdit(
        range: SourceRange(
          location: SourceOffset(utf16Offset: session.snapshot.utf16Count),
          length: 0
        ),
        replacement: "\nAfter"
      )
    )

    XCTAssertEqual(
      session.snapshot.text,
      "Before\nTask\n20 + 22 =\nhttps://example.com/inside-path\nAfter"
    )
    XCTAssertEqual(session.projection.decorations.count, 2)
    XCTAssertTrue(
      session.projection.decorations.allSatisfy { decoration in
        guard let range = decoration.sourceRange else { return true }
        return session.snapshot.contains(range)
      })

    XCTAssertTrue(session.undo())
    XCTAssertTrue(session.undo())
    XCTAssertTrue(session.undo())
    XCTAssertEqual(session.snapshot.text, original)
    XCTAssertTrue(session.redo())
    XCTAssertTrue(session.redo())
    XCTAssertTrue(session.redo())
    XCTAssertEqual(
      session.snapshot.text,
      "Before\nTask\n20 + 22 =\nhttps://example.com/inside-path\nAfter"
    )
  }

  func test_UT_EDIT_002F_StaleProjectionIsRejected() {
    let parser = SpikeProjectionParser()
    let oldSnapshot = SourceSnapshot(version: 1, text: "1 + 1 =")
    let currentSnapshot = SourceSnapshot(version: 2, text: "1 + 2 =")
    let projection = parser.parse(oldSnapshot)

    XCTAssertFalse(ProjectionGate().accepts(projection, for: currentSnapshot))
    XCTAssertTrue(ProjectionGate().accepts(parser.parse(currentSnapshot), for: currentSnapshot))
  }

  func test_ET_NOTE_003_HorizontalGestureThresholdAndDirection() {
    var interpreter = HorizontalNavigationGestureInterpreter(threshold: 60)

    XCTAssertNil(interpreter.update(deltaX: 30, deltaY: 2, isComplete: false))
    XCTAssertEqual(interpreter.update(deltaX: 30, deltaY: 2, isComplete: true), .previous)
    XCTAssertEqual(interpreter.update(deltaX: -70, deltaY: 1, isComplete: true), .next)
    XCTAssertNil(interpreter.update(deltaX: 10, deltaY: 80, isComplete: true))
  }

  @MainActor
  func test_ET_NOTE_003_DirectionalEntryUsesStartAndEndBeforeCaretMovement() throws {
    let container = ProjectionEditorContainer(initialText: "abcdef")
    container.textView.setSelectedRange(NSRange(location: 3, length: 0))
    container.armDirectionalEntry(token: 1)

    container.textView.keyDown(with: try arrowEvent(keyCode: 125))
    XCTAssertEqual(container.textView.selectedRange(), NSRange(location: 0, length: 0))

    container.armDirectionalEntry(token: 2)
    container.textView.keyDown(with: try arrowEvent(keyCode: 126))
    XCTAssertEqual(container.textView.selectedRange(), NSRange(location: 6, length: 0))
  }

  func test_ET_EDIT_005A_UndoRedoPreservesAllDecorationKinds() throws {
    let source = "[ ] Task\n20 + 22 =\nhttps://example.com/long/path"
    var session = ProjectionEditingSession(text: source)
    let initialDecorationCount = session.projection.decorations.count

    try session.replace(
      SourceEdit(
        range: SourceRange(location: SourceOffset(utf16Offset: 0), length: 0),
        replacement: "Title\n"
      )
    )
    XCTAssertEqual(session.projection.decorations.count, initialDecorationCount)
    XCTAssertTrue(session.undo())
    XCTAssertEqual(session.snapshot.text, source)
    XCTAssertEqual(session.projection.decorations.count, initialDecorationCount)
    XCTAssertTrue(session.redo())
    XCTAssertEqual(session.snapshot.text, "Title\n\(source)")
    XCTAssertEqual(session.projection.decorations.count, initialDecorationCount)
  }

  func test_ET_LIST_002A_CheckboxToggleIsOneUndoableSourceEdit() throws {
    var session = ProjectionEditingSession(text: "list\nTask")

    try session.toggleCheckbox(at: SourceOffset(utf16Offset: 6))
    XCTAssertEqual(session.snapshot.text, "list\nTask /x")
    XCTAssertTrue(session.undo())
    XCTAssertEqual(session.snapshot.text, "list\nTask")
    XCTAssertTrue(session.redo())
    XCTAssertEqual(session.snapshot.text, "list\nTask /x")
  }

  func test_ET_EDIT_006A_MarkedTextFixtureRemainsValidSource() throws {
    let markedText = "拼音输入 📝 e\u{301}"
    let snapshot = SourceSnapshot(version: 0, text: "before  after")
    let offset = SourceOffset(utf16Offset: "before ".utf16.count)
    let updated = try snapshot.applying(
      SourceEdit(range: SourceRange(location: offset, length: 0), replacement: markedText)
    )

    XCTAssertEqual(updated.text, "before \(markedText) after")
    XCTAssertEqual(updated.utf16Count, (updated.text as NSString).length)
  }

  @MainActor
  func test_ET_EDIT_006B_TextViewDoesNotCommitMarkedTextEarly() {
    let source = "before  after"
    let container = ProjectionEditorContainer(initialText: source)
    var sourceChanges: [(source: String, hasMarkedText: Bool)] = []
    container.sourceDidChange = { source, hasMarkedText in
      sourceChanges.append((source, hasMarkedText))
    }
    let insertionOffset = "before ".utf16.count
    container.textView.setSelectedRange(NSRange(location: insertionOffset, length: 0))

    container.textView.setMarkedText(
      "拼音",
      selectedRange: NSRange(location: 2, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0)
    )

    XCTAssertTrue(container.textView.hasMarkedText())
    XCTAssertEqual(container.textView.markedRange(), NSRange(location: insertionOffset, length: 2))
    XCTAssertEqual(container.textView.string, "before 拼音 after")
    container.textDidChange(Notification(name: NSText.didChangeNotification))
    XCTAssertEqual(sourceChanges.last?.source, "before 拼音 after")
    XCTAssertEqual(sourceChanges.last?.hasMarkedText, true)

    container.textView.unmarkText()
    XCTAssertFalse(container.textView.hasMarkedText())
    XCTAssertEqual(container.textView.string, "before 拼音 after")
    container.textDidChange(Notification(name: NSText.didChangeNotification))
    XCTAssertEqual(sourceChanges.last?.source, "before 拼音 after")
    XCTAssertEqual(sourceChanges.last?.hasMarkedText, false)
  }

  func test_UT_EDIT_002E_TenThousandRandomizedUnicodeEditsPreserveInvariants() throws {
    var generator = LinearCongruentialGenerator(seed: 0xF0_4E_4F_57)
    var snapshot = SourceSnapshot(
      version: 0,
      text: "[ ] 初始 📝\n20 + 22 =\nhttps://example.com/long/path\nCafe\u{301}"
    )
    let replacements = ["", "a", "中文", "📝", "e\u{301}", "\n", "[x] ", " ="]
    let parser = SpikeProjectionParser()

    for _ in 0..<10_000 {
      let boundaries = characterBoundaryOffsets(in: snapshot.text)
      let firstIndex = Int(generator.next() % UInt64(boundaries.count))
      let secondIndex = Int(generator.next() % UInt64(boundaries.count))
      let lower = min(firstIndex, secondIndex)
      let upper = max(firstIndex, secondIndex)
      let range = NSRange(
        location: boundaries[lower],
        length: boundaries[upper] - boundaries[lower]
      )
      let replacement = replacements[Int(generator.next() % UInt64(replacements.count))]
      let expected = NSMutableString(string: snapshot.text)
      expected.replaceCharacters(in: range, with: replacement)

      snapshot = try snapshot.applying(
        SourceEdit(range: SourceRange(range), replacement: replacement)
      )
      let projection = parser.parse(snapshot)

      XCTAssertEqual(snapshot.text, expected as String)
      XCTAssertEqual(projection.sourceVersion, snapshot.version)
      for decoration in projection.decorations {
        if let sourceRange = decoration.sourceRange {
          XCTAssertTrue(snapshot.contains(sourceRange))
        }
      }
      let oversizedSelection = SourceSelection(
        range: SourceRange(
          location: SourceOffset(utf16Offset: snapshot.utf16Count + 10),
          length: 20
        )
      )
      XCTAssertLessThanOrEqual(
        snapshot.clamped(oversizedSelection).range.upperBound,
        snapshot.utf16Count
      )
    }
  }

  func test_UT_EDIT_002F_ProjectionPipelineCancelsSupersededSourceVersion() async throws {
    let parser = DelayedProjectionParser()
    let pipeline = ProjectionParsePipeline(parser: parser)
    let firstSnapshot = SourceSnapshot(version: 1, text: "first")
    let secondSnapshot = SourceSnapshot(version: 2, text: "second")

    let firstRequest = Task {
      try await pipeline.projection(for: firstSnapshot)
    }
    try await Task.sleep(for: .milliseconds(30))
    let currentProjection = try await pipeline.projection(for: secondSnapshot)

    do {
      _ = try await firstRequest.value
      XCTFail("The superseded projection should be cancelled")
    } catch is CancellationError {
      // Expected.
    }
    XCTAssertEqual(currentProjection.sourceVersion, secondSnapshot.version)
    let diagnostics = await pipeline.diagnostics()
    XCTAssertEqual(diagnostics.latestRequestedVersion, secondSnapshot.version)
    XCTAssertEqual(diagnostics.latestAppliedVersion, secondSnapshot.version)
    XCTAssertEqual(diagnostics.completedCount, 1)
    XCTAssertGreaterThanOrEqual(diagnostics.cancelledCount, 1)
  }

  func test_UT_EDIT_002F_ProjectionPipelineRejectsMismatchedParserVersion() async throws {
    let pipeline = ProjectionParsePipeline(parser: MismatchedVersionParser())
    let snapshot = SourceSnapshot(version: 9, text: "source")

    do {
      _ = try await pipeline.projection(for: snapshot)
      XCTFail("A parser result for another source version must be rejected")
    } catch let error as ProjectionPipelineError {
      XCTAssertEqual(error, .sourceVersionMismatch(expected: 9, actual: 10))
    }
    let diagnostics = await pipeline.diagnostics()
    XCTAssertEqual(diagnostics.rejectedVersionCount, 1)
    XCTAssertNil(diagnostics.latestAppliedVersion)
  }

  func test_UT_EDIT_002D_InvalidDecorationIsDiscardedWithSourceFreeDiagnostic() {
    let snapshot = SourceSnapshot(version: 4, text: "short")
    let invalidProjection = EditorProjection(
      sourceVersion: snapshot.version,
      decorations: [
        .checkbox(
          range: SourceRange(location: SourceOffset(utf16Offset: 99), length: 3),
          markerRange: nil,
          isChecked: false
        )
      ]
    )

    let projection = EditorProjectionValidator().validate(invalidProjection, for: snapshot)

    XCTAssertTrue(projection.decorations.isEmpty)
    XCTAssertEqual(projection.diagnostics.map(\.code), ["invalid-decoration-range"])
    XCTAssertFalse(projection.diagnostics[0].message.contains(snapshot.text))
  }

  func test_ET_EDIT_002_LargeProductionParseCanBeCancelled() async throws {
    let source = String(repeating: "ordinary line with unicode 你好 📝\n", count: 50_000)
    let snapshot = SourceSnapshot(version: 1, text: source)
    let task = Task {
      try await ProductionProjectionParser().parse(snapshot)
    }

    task.cancel()
    do {
      _ = try await task.value
      XCTFail("A cancelled large-note parse must not complete")
    } catch is CancellationError {
      // Expected.
    }
  }

  @MainActor
  func test_ET_EDIT_002_ViewportRestorationAndAccessibilityContainerUseSourceCoordinates() {
    let source = String(repeating: "line 你好 📝\n", count: 100)
    let container = ProjectionEditorContainer(initialText: source)
    container.frame = NSRect(x: 0, y: 0, width: 500, height: 220)
    let selection = NSRange(location: 12, length: 5)
    let state = EditorViewportState(selectionRange: selection, scrollOffset: 120)
    var reportedState: EditorViewportState?
    container.viewportDidChange = { viewport in
      reportedState = viewport
    }

    container.applyViewportRestoration(state, token: 1)
    XCTAssertEqual(container.textView.selectedRange(), selection)
    XCTAssertEqual(container.currentViewportState().selection.range.nsRange, selection)
    XCTAssertEqual(container.decorationAccessibilityContainer.accessibilityRole(), .group)
    XCTAssertEqual(
      container.decorationAccessibilityContainer.accessibilityLabel(),
      "Editor decorations"
    )
    XCTAssertTrue(
      (container.textView.accessibilityChildren() ?? []).contains { child in
        (child as AnyObject) === container.decorationAccessibilityContainer
      }
    )

    let updatedSelection = NSRange(location: 24, length: 0)
    container.textView.setSelectedRange(updatedSelection)
    container.textViewDidChangeSelection(
      Notification(name: NSTextView.didChangeSelectionNotification)
    )
    XCTAssertEqual(reportedState?.selection.range.nsRange, updatedSelection)
  }

  private func characterBoundaryOffsets(in text: String) -> [Int] {
    var offsets = text.indices.map { text[..<$0].utf16.count }
    offsets.append(text.utf16.count)
    return Array(Set(offsets)).sorted()
  }

  private func arrowEvent(keyCode: UInt16) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: keyCode
      )
    )
  }
}

private struct LinearCongruentialGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state = 6_364_136_223_846_793_005 &* state &+ 1_442_695_040_888_963_407
    return state
  }
}

private actor DelayedProjectionParser: ProjectionParsing {
  func parse(_ snapshot: SourceSnapshot) async throws -> EditorProjection {
    if snapshot.version == 1 {
      try await Task.sleep(for: .seconds(5))
    }
    try Task.checkCancellation()
    return EditorProjection(sourceVersion: snapshot.version, decorations: [])
  }
}

private struct MismatchedVersionParser: ProjectionParsing {
  func parse(_ snapshot: SourceSnapshot) async throws -> EditorProjection {
    EditorProjection(sourceVersion: snapshot.version + 1, decorations: [])
  }
}
