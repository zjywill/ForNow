import AppKit
import ForNowEditor
import Foundation
import XCTest

final class MarkdownProjectionTests: XCTestCase {
  func test_UT_EDIT_003A_OnlyThreeDocumentedHeadingLevelsAreStyled() {
    let source = "# One\n## Two\n### Three\n#### Four\n#No space"

    XCTAssertEqual(styledSource(.heading(level: 1), in: source), ["# One"])
    XCTAssertEqual(styledSource(.heading(level: 2), in: source), ["## Two"])
    XCTAssertEqual(styledSource(.heading(level: 3), in: source), ["### Three"])
  }

  func test_UT_EDIT_003B_BoldAndItalicUseOnlyDocumentedDelimiters() {
    let source = "**bold** and *italic*; ***unsupported*** and _not italic_"

    XCTAssertEqual(styledSource(.bold, in: source), ["bold"])
    XCTAssertEqual(styledSource(.italic, in: source), ["italic"])
  }

  func test_UT_EDIT_003C_StrikethroughAndUnderlinePreserveTheirSourceMarkers() {
    let source = "~~old~~ then __important__"
    let snapshot = SourceSnapshot(version: 8, text: source)
    let projection = SpikeProjectionParser().parse(snapshot)

    XCTAssertEqual(styledSource(.strikethrough, in: source, projection: projection), ["old"])
    XCTAssertEqual(styledSource(.underline, in: source, projection: projection), ["important"])
    XCTAssertEqual(snapshot.text, source)
  }

  func test_UT_EDIT_003D_InlineAndFencedCodeExcludeNestedMarkdown() {
    let source = """
      `inline` and **outside**
      ```swift
      **not bold**
      let value = 42
      ```
      """

    XCTAssertEqual(styledSource(.inlineCode, in: source), ["inline"])
    XCTAssertEqual(styledSource(.bold, in: source), ["outside"])
    XCTAssertTrue(styledSource(.codeFence, in: source).allSatisfy { $0.hasPrefix("```") })
    XCTAssertEqual(styledSource(.codeBlock(language: .swift), in: source).count, 1)
    XCTAssertTrue(styledSource(.syntax(.keyword), in: source).contains("let"))
  }

  func test_UT_EDIT_003E_CommentsAreStyledAndExcludedFromCalculationsAndItems() {
    let source = "// 1 + 1 =\n  // [ ] hidden item\n2 + 2 ="
    let projection = SpikeProjectionParser().parse(SourceSnapshot(version: 1, text: source))

    XCTAssertEqual(styledSource(.comment, in: source, projection: projection).count, 2)
    XCTAssertEqual(
      projection.decorations.filter {
        if case .result = $0 { return true }
        return false
      }.count,
      1
    )
    XCTAssertFalse(
      projection.decorations.contains {
        if case .checkbox = $0 { return true }
        return false
      }
    )
  }

  func test_UT_EDIT_003F_UnsupportedMarkdownRemainsOrdinaryText() {
    let source = "#### heading\n> quote\n***triple***\n- list\n[label](destination)"

    XCTAssertTrue(styles(in: source).isEmpty)
  }

  func test_UT_EDIT_003G_StyleRangesUseExactUTF16SourceCoordinates() {
    let source = "prefix 🧑🏽‍💻 **你好 📝** suffix"
    let matches = styles(in: source).filter { $0.style == .bold }

    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(
      SourceSnapshot(version: 1, text: source).substring(in: matches[0].range),
      "你好 📝"
    )
  }

  func test_UT_EDIT_003H_CommandSlashTogglesCurrentIndentedLine() throws {
    let source = "first\n  second\nthird"
    let caret = (source as NSString).range(of: "second").location + 2
    let command = LineCommentToggler()

    let commented = try XCTUnwrap(
      command.toggle(
        in: SourceSnapshot(version: 4, text: source),
        selection: SourceSelection(
          range: SourceRange(location: SourceOffset(utf16Offset: caret), length: 0)
        )
      )
    )
    let commentedSnapshot = try SourceSnapshot(version: 4, text: source).applying(commented.edit)
    XCTAssertEqual(commentedSnapshot.text, "first\n  // second\nthird")

    let uncommented = try XCTUnwrap(
      command.toggle(in: commentedSnapshot, selection: commented.selection)
    )
    XCTAssertEqual(try commentedSnapshot.applying(uncommented.edit).text, source)

    let trailingLine = SourceSnapshot(version: 1, text: "first\n")
    let trailingResult = try XCTUnwrap(
      command.toggle(
        in: trailingLine,
        selection: SourceSelection(
          range: SourceRange(
            location: SourceOffset(utf16Offset: trailingLine.utf16Count),
            length: 0
          )
        )
      )
    )
    XCTAssertEqual(try trailingLine.applying(trailingResult.edit).text, "first\n// ")
  }

  func test_UT_EDIT_003I_CommandSlashHandlesSelectedCRLFLinesAsOneEdit() throws {
    let source = "// alpha\r\n  // beta\r\n\r\ngamma"
    let selectionLength = ("// alpha\r\n  // beta\r\n\r\n" as NSString).length

    let result = try XCTUnwrap(
      LineCommentToggler().toggle(
        in: SourceSnapshot(version: 3, text: source),
        selection: SourceSelection(
          range: SourceRange(location: SourceOffset(utf16Offset: 0), length: selectionLength)
        )
      )
    )

    XCTAssertEqual(result.edit.range.location.utf16Offset, 0)
    XCTAssertEqual(
      try SourceSnapshot(version: 3, text: source).applying(result.edit).text,
      "alpha\r\n  beta\r\n\r\ngamma")
  }

  func test_UT_EDIT_003J_CodeModeAndFencesSuppressOrdinaryMarkdownParsing() {
    let source = "code: swift\n# not a heading\n**not bold**\nlet answer = 42"

    XCTAssertTrue(styledSource(.heading(level: 1), in: source).isEmpty)
    XCTAssertTrue(styledSource(.bold, in: source).isEmpty)
    XCTAssertEqual(styledSource(.modeHeader, in: source), ["code: swift"])
    XCTAssertEqual(styledSource(.codeBlock(language: .swift), in: source).count, 1)
  }

  @MainActor
  func test_ET_EDIT_003_PresentationIsSourceFreeAndCommentToggleIsOneUndoGroup() async throws {
    let source = "# Heading\n**bold**\nordinary"
    let container = ProjectionEditorContainer(initialText: source)
    await container.waitForPendingProjection()

    XCTAssertEqual(container.textView.string, source)
    XCTAssertTrue(
      container.currentProjection.decorations.contains {
        if case .style(_, .heading(level: 1)) = $0 { return true }
        return false
      })
    XCTAssertTrue(container.hasPresentationAttributes(at: 0))

    container.textView.setSelectedRange((source as NSString).range(of: "ordinary"))
    XCTAssertTrue(container.toggleComments())
    XCTAssertEqual(container.textView.string, "# Heading\n**bold**\n// ordinary")

    let undoManager = try XCTUnwrap(container.textView.undoManager)
    undoManager.undo()
    XCTAssertEqual(container.textView.string, source)
    undoManager.redo()
    XCTAssertEqual(container.textView.string, "# Heading\n**bold**\n// ordinary")
  }

  func test_UT_CMD_004A_CodeHeaderParsesLanguageAliasesAndBodyRange() throws {
    let source = " CODE: py \r\nprint('hello')"
    let header = try XCTUnwrap(
      CodeModeHeaderParser().parse(in: source, defaultLanguage: .plainText)
    )

    XCTAssertEqual(header.languageIdentifier, "py")
    XCTAssertEqual(header.language, .python)
    XCTAssertEqual((source as NSString).substring(with: header.bodyRange), "print('hello')")
  }

  func test_UT_CMD_004B_CodeHeaderUsesConfiguredDefaultLanguage() throws {
    let header = try XCTUnwrap(
      CodeModeHeaderParser().parse(in: "code\nlet value = 1", defaultLanguage: .swift)
    )

    XCTAssertNil(header.languageIdentifier)
    XCTAssertEqual(header.language, .swift)

    let unknown = try XCTUnwrap(
      CodeModeHeaderParser().parse(in: "code: rust\nfn main() {}", defaultLanguage: .python)
    )
    XCTAssertEqual(unknown.languageIdentifier, "rust")
    XCTAssertEqual(unknown.language, .plainText)
  }

  func test_UT_CMD_004C_SyntaxHighlightingAdapterReturnsSourceOnlyRanges() {
    let source = "let greeting = \"// hello\"\n// \"quoted comment\"\nprint(greeting)"
    let range = SourceRange(location: SourceOffset(utf16Offset: 0), length: source.utf16.count)
    let highlights = BuiltInCodeSyntaxHighlighter().highlights(
      in: source,
      range: range,
      language: .swift
    )

    XCTAssertEqual(
      source,
      "let greeting = \"// hello\"\n// \"quoted comment\"\nprint(greeting)"
    )
    XCTAssertTrue(highlights.contains { $0.kind == .keyword })
    XCTAssertTrue(highlights.contains { $0.kind == .string })
    XCTAssertTrue(highlights.contains { $0.kind == .comment })
    XCTAssertTrue(
      highlights.allSatisfy { SourceSnapshot(version: 0, text: source).contains($0.range) })
  }

  @MainActor
  func test_UT_CMD_004D_CodeContextDisablesIndentStrippingWithoutDisablingRawPaste() throws {
    let payload = PasteboardPayload(plainText: "  indented\r\n")
    let settings = PasteSettings(
      stripsLeadingWhitespace: true,
      stripsListNumbers: false,
      stripsBullets: false,
      stripsMarkdown: false,
      stripsEmptyLines: false
    )
    let pipeline = PastePipeline()

    XCTAssertEqual(
      try pipeline.sourceText(from: payload, mode: .normal, settings: settings, context: .code),
      "  indented\n"
    )
    XCTAssertEqual(
      try pipeline.sourceText(from: payload, mode: .normal, settings: settings, context: .plain),
      "indented\n"
    )
    XCTAssertEqual(
      try pipeline.sourceText(from: payload, mode: .raw, settings: settings, context: .code),
      "  indented\n"
    )

    let fenced = "```swift\nlet value = 1\n```\noutside"
    let outside = (fenced as NSString).range(of: "outside").location
    XCTAssertFalse(
      EditorCodeContextPolicy().isCodeContext(
        in: SourceSnapshot(version: 1, text: fenced),
        selection: SourceSelection(
          range: SourceRange(location: SourceOffset(utf16Offset: outside), length: 0)
        )
      )
    )
  }

  @MainActor
  func test_ET_CMD_004_CodeNotePasteAndHighlightNeverMutateExistingSource() async throws {
    let source = "code: swift\nlet value = 42"
    let settings = EditorSettings(
      automaticallyShortensLinks: true,
      hyperlinkFeaturesEnabled: true,
      defaultCodeLanguage: .python,
      codeHighlightTheme: .adaptive
    )
    let container = ProjectionEditorContainer(initialText: source, editorSettings: settings)
    container.pasteSettings = PasteSettings(
      stripsLeadingWhitespace: true,
      stripsListNumbers: false,
      stripsBullets: false,
      stripsMarkdown: false,
      stripsEmptyLines: false
    )
    await container.waitForPendingProjection()

    XCTAssertEqual(container.textView.string, source)
    XCTAssertFalse(
      container.currentProjection.decorations.contains {
        if case .link = $0 { return true }
        return false
      })

    container.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
    try container.performPaste(
      PasteboardPayload(plainText: "\n  print(value)"),
      mode: .normal
    )
    XCTAssertEqual(container.textView.string, source + "\n  print(value)")

    let undoManager = try XCTUnwrap(container.textView.undoManager)
    undoManager.undo()
    XCTAssertEqual(container.textView.string, source)
  }

  private func styledSource(
    _ style: TextStyle,
    in source: String,
    projection: EditorProjection? = nil
  ) -> [String] {
    let snapshot = SourceSnapshot(version: 1, text: source)
    return (projection ?? SpikeProjectionParser().parse(snapshot)).decorations.compactMap {
      guard case .style(let range, let candidate) = $0, candidate == style else { return nil }
      return snapshot.substring(in: range)
    }
  }

  private func styles(in source: String) -> [(range: SourceRange, style: TextStyle)] {
    SpikeProjectionParser().parse(SourceSnapshot(version: 1, text: source)).decorations.compactMap {
      if case .style(let range, let style) = $0 { return (range, style) }
      return nil
    }
  }
}
