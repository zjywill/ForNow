import AppKit
import ForNowEditor
import XCTest

final class ClipboardProjectionTests: XCTestCase {
  func test_UT_CLIP_001B_CaretInsideInlineCodeCopiesOnlyCode() {
    let source = "Run `swift test` now"
    let caret = (source as NSString).range(of: "test").location

    XCTAssertEqual(copy(source, caret: caret), "swift test")
  }

  func test_UT_CLIP_001C_CaretInsideFencedCodeCopiesBlockBody() {
    let source = "Before\n```swift\nlet value = \"你好 📝\"\n```\nAfter"
    let caret = (source as NSString).range(of: "value").location

    XCTAssertEqual(copy(source, caret: caret), "let value = \"你好 📝\"\n")

    let codeNote = "code: swift\nlet snippet = `literal`\nprint(snippet)"
    let codeCaret = (codeNote as NSString).range(of: "literal").location
    XCTAssertEqual(copy(codeNote, caret: codeCaret), "let snippet = `literal`\nprint(snippet)")
  }

  func test_UT_CLIP_001D_DecorationCopyUsesCanonicalResultAndURL() {
    let policy = ProjectionCopyPolicy()
    let range = SourceRange(location: SourceOffset(utf16Offset: 0), length: 1)
    let link = EditorDecoration.link(
      range: range,
      presentation: LinkPresentation(
        originalURL: "https://example.com/full/path",
        displayText: "example.com/.../path",
        duplicateIndex: 1
      )
    )
    let result = EditorDecoration.result(
      anchor: SourceOffset(utf16Offset: 1),
      presentation: CalculationPresentation(canonicalValue: "42", displayText: "42")
    )

    XCTAssertEqual(policy.copyText(for: link), "https://example.com/full/path")
    XCTAssertEqual(policy.copyText(for: result), "42")
    XCTAssertNil(
      policy.copyText(
        for: .checkbox(range: range, markerRange: nil, isChecked: false)
      )
    )
    XCTAssertNil(policy.copyText(for: .style(range: range, style: .bold)))
  }

  func test_UT_CLIP_001E_NoContextCopiesCleanWholeNote() {
    XCTAssertEqual(copy("list: Title\nBody /x", caret: 0), "Title\nBody")
  }

  @MainActor
  func test_ET_CLIP_001_ContainerUsesCurrentSourceForContextualCopy() {
    let container = ProjectionEditorContainer(initialText: "Run `first` now")
    container.applyExternalSource("Run `second` now")
    let caret = (container.textView.string as NSString).range(of: "second").location
    let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    let pasteItem = NSMenuItem(
      title: "Paste",
      action: #selector(NSText.paste(_:)),
      keyEquivalent: "v"
    )

    XCTAssertEqual(
      container.contextualCopyText(for: NSRange(location: caret, length: 0)),
      "second"
    )
    XCTAssertTrue(container.textView.validateUserInterfaceItem(copyItem))
    XCTAssertTrue(container.textView.validateUserInterfaceItem(pasteItem))
  }

  func test_UT_CLIP_002A_ModeHeaderIsOmitted() {
    XCTAssertEqual(cleanExport("plain\nBody"), "Body")
  }

  func test_UT_CLIP_002B_ModeTitleIsPreservedWithOriginalLineEnding() {
    XCTAssertEqual(cleanExport("math: Quarterly totals\r\n1 + 1 ="), "Quarterly totals\r\n1 + 1 =")
  }

  func test_UT_CLIP_002C_ExportPolicyControlsKnownModeHeaders() {
    let source = "custom: Keep me\nBody"

    XCTAssertEqual(cleanExport(source), source)
    XCTAssertEqual(
      cleanExport(
        source,
        policy: ExportProjectionPolicy(modeAliases: ["custom"])
      ),
      "Keep me\nBody"
    )
    XCTAssertEqual(
      cleanExport(
        "plain\nBody",
        policy: ExportProjectionPolicy(omitsModeHeader: false)
      ),
      "plain\nBody"
    )
  }

  func test_UT_CLIP_002D_ConfiguredTrailingChecklistTriggerIsOmitted() {
    let source = "list\nFirst /x\nSecond   done\nLiteral /x value"
    let policy = ExportProjectionPolicy(checklistTrigger: "done")

    XCTAssertEqual(cleanExport(source, policy: policy), "First /x\nSecond\nLiteral /x value")
  }

  func test_UT_CLIP_002E_FullURLsArePreserved() {
    let url = "https://example.com/a/very/long/path?query=full#anchor"
    XCTAssertEqual(cleanExport("Visit \(url)"), "Visit \(url)")
  }

  func test_UT_CLIP_002F_UserWhitespaceIsPreserved() {
    let source = "  First\tline  \n\n\tSecond line\t"
    XCTAssertEqual(cleanExport(source), source)
  }

  @MainActor
  func test_UT_CLIP_003A_PlainTextIsPreferredOverHTMLAndRTF() throws {
    let payload = PasteboardPayload(
      plainText: "Plain wins",
      html: Data("<b>HTML loses</b>".utf8),
      richText: try rtfData(text: "RTF loses")
    )

    XCTAssertEqual(try normalPaste(payload), "Plain wins")
  }

  @MainActor
  func test_UT_CLIP_003B_SafariHTMLLosesStyleAndPreservesSmartLink() throws {
    let html = """
      <html><head><meta charset="utf-8"></head><body>
      <p><span style="font-weight: 700">Open</span> <a href="https://example.com/safari">Safari Guide</a></p>
      </body></html>
      """

    XCTAssertEqual(
      try normalPaste(PasteboardPayload(html: Data(html.utf8))),
      "Open Safari Guide (https://example.com/safari)"
    )
  }

  @MainActor
  func test_UT_CLIP_003C_ChromeHTMLWithURLLabelDoesNotDuplicateURL() throws {
    let html = """
      <meta http-equiv="content-type" content="text/html; charset=utf-8">
      <a href="https://example.com/chrome">https://example.com/chrome</a>
      """

    XCTAssertEqual(
      try normalPaste(PasteboardPayload(html: Data(html.utf8))),
      "https://example.com/chrome"
    )
  }

  @MainActor
  func test_UT_CLIP_003D_NotesRTFStyleIsRemoved() throws {
    let data = try rtfData(text: "Notes styled text", boldRange: NSRange(location: 0, length: 5))

    XCTAssertEqual(try normalPaste(PasteboardPayload(richText: data)), "Notes styled text")
  }

  @MainActor
  func test_UT_CLIP_003E_WordRTFLinkBecomesReadableSmartLink() throws {
    let text = "Read Word Guide"
    let data = try rtfData(
      text: text,
      link: (NSRange(location: 5, length: 10), "https://example.com/word")
    )

    XCTAssertEqual(
      try normalPaste(PasteboardPayload(richText: data)),
      "Read Word Guide (https://example.com/word)"
    )
  }

  @MainActor
  func test_UT_CLIP_003F_ExcelAndNumbersTabsRemainCellSeparators() throws {
    let source = "Name\tCount\nApple\t2\nOrange\t3"
    XCTAssertEqual(try normalPaste(PasteboardPayload(plainText: source)), source)
  }

  @MainActor
  func test_UT_CLIP_003G_TerminalAndIDEIndentSettingIsIndependent() throws {
    let source = "\tcommand --flag\n    let value = 1"
    var settings = allTransformsDisabled
    settings.stripsLeadingWhitespace = true

    XCTAssertEqual(
      try normalPaste(PasteboardPayload(plainText: source), settings: settings),
      "command --flag\nlet value = 1"
    )
    XCTAssertEqual(
      try normalPaste(PasteboardPayload(plainText: source), settings: allTransformsDisabled),
      source
    )
  }

  @MainActor
  func test_UT_CLIP_003H_FiveTransformsCanBeEnabledIndependently() throws {
    try assertSingleTransform(\.stripsLeadingWhitespace, source: "  value", expected: "value")
    try assertSingleTransform(\.stripsListNumbers, source: "  12. value", expected: "  value")
    try assertSingleTransform(\.stripsBullets, source: "\t- value", expected: "\tvalue")
    try assertSingleTransform(\.stripsMarkdown, source: "**value**", expected: "value")
    try assertSingleTransform(
      \.stripsEmptyLines, source: "first\n \nsecond", expected: "first\nsecond")
  }

  @MainActor
  func test_UT_CLIP_003I_MarkdownAndSmartLinksTransformWithoutLosingDestination() throws {
    let source = "# **Heading**\n[Guide](https://example.com/full/path)"
    var settings = allTransformsDisabled
    settings.stripsMarkdown = true

    XCTAssertEqual(
      try normalPaste(PasteboardPayload(plainText: source), settings: settings),
      "Heading\nGuide (https://example.com/full/path)"
    )
  }

  @MainActor
  func test_UT_CLIP_003J_CombinedTransformsNormalizeUnicodeCRLF() throws {
    let source = "  1. **你好 📝**\r\n\r\n\t- [Guide](https://example.com)\rLast"

    XCTAssertEqual(
      try normalPaste(PasteboardPayload(plainText: source)),
      "你好 📝\nGuide (https://example.com)\nLast"
    )
  }

  @MainActor
  func test_ET_CLIP_003_NormalPasteIsOneUndoableEditorReplacement() throws {
    let container = ProjectionEditorContainer(initialText: "Before selected After")
    container.textView.setSelectedRange(
      (container.textView.string as NSString).range(of: "selected")
    )

    try container.performPaste(
      PasteboardPayload(plainText: "  1. **你好 📝**\r\n\r\n- Next"),
      mode: .normal
    )
    XCTAssertEqual(container.textView.string, "Before 你好 📝\nNext After")

    let undoManager = try XCTUnwrap(container.textView.undoManager)
    undoManager.undo()
    XCTAssertEqual(container.textView.string, "Before selected After")
    undoManager.redo()
    XCTAssertEqual(container.textView.string, "Before 你好 📝\nNext After")
  }

  @MainActor
  func test_UT_CLIP_004_RawPasteOnlyDecodesAndNormalizesLineEndings() throws {
    let source = "\t1. **Keep**\r\n\r- bullet\r[Guide](https://example.com)"

    XCTAssertEqual(
      try PastePipeline().sourceText(
        from: PasteboardPayload(plainText: source),
        mode: .raw,
        settings: PasteSettings()
      ),
      "\t1. **Keep**\n\n- bullet\n[Guide](https://example.com)"
    )
  }

  @MainActor
  func test_ET_CLIP_004_RawPasteIsOneUndoableEditorReplacement() throws {
    let container = ProjectionEditorContainer(initialText: "AB")
    container.textView.setSelectedRange(NSRange(location: 1, length: 0))

    try container.performPaste(
      PasteboardPayload(plainText: "\t- **raw**\r\n"),
      mode: .raw
    )
    XCTAssertEqual(container.textView.string, "A\t- **raw**\nB")

    let undoManager = try XCTUnwrap(container.textView.undoManager)
    undoManager.undo()
    XCTAssertEqual(container.textView.string, "AB")
    undoManager.redo()
    XCTAssertEqual(container.textView.string, "A\t- **raw**\nB")
  }

  @MainActor
  func testPasteErrorsAreExplicitAndContainNoClipboardBody() throws {
    let emptyPayload = PasteboardPayload()
    let unreadablePayload = PasteboardPayload(html: Data())

    XCTAssertThrowsError(try normalPaste(emptyPayload)) { error in
      XCTAssertEqual(error as? PastePipelineError, .unsupportedClipboardContent)
      XCTAssertEqual(error.localizedDescription, "The clipboard does not contain supported text.")
    }
    XCTAssertThrowsError(try normalPaste(unreadablePayload)) { error in
      XCTAssertEqual(error as? PastePipelineError, .unreadableTextRepresentation)
      XCTAssertEqual(error.localizedDescription, "The clipboard text could not be read.")
    }
    XCTAssertEqual(try normalPaste(PasteboardPayload(plainText: "")), "")
  }

  private func copy(_ source: String, caret: Int) -> String {
    ProjectionCopyPolicy().copyText(
      from: SourceSnapshot(version: 0, text: source),
      selection: SourceSelection(
        range: SourceRange(location: SourceOffset(utf16Offset: caret), length: 0)
      )
    )
  }

  private func cleanExport(
    _ source: String,
    policy: ExportProjectionPolicy = ExportProjectionPolicy()
  ) -> String {
    CleanExportProjection().text(from: source, policy: policy)
  }

  @MainActor
  private func normalPaste(
    _ payload: PasteboardPayload,
    settings: PasteSettings = PasteSettings()
  ) throws -> String {
    try PastePipeline().sourceText(from: payload, mode: .normal, settings: settings)
  }

  @MainActor
  private func assertSingleTransform(
    _ keyPath: WritableKeyPath<PasteSettings, Bool>,
    source: String,
    expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    var settings = allTransformsDisabled
    settings[keyPath: keyPath] = true
    XCTAssertEqual(
      try normalPaste(PasteboardPayload(plainText: source), settings: settings),
      expected,
      file: file,
      line: line
    )
  }

  private var allTransformsDisabled: PasteSettings {
    PasteSettings(
      stripsLeadingWhitespace: false,
      stripsListNumbers: false,
      stripsBullets: false,
      stripsMarkdown: false,
      stripsEmptyLines: false
    )
  }

  @MainActor
  private func rtfData(
    text: String,
    boldRange: NSRange? = nil,
    link: (range: NSRange, destination: String)? = nil
  ) throws -> Data {
    let attributed = NSMutableAttributedString(string: text)
    if let boldRange {
      attributed.addAttribute(
        .font,
        value: NSFont.boldSystemFont(ofSize: 14),
        range: boldRange
      )
    }
    if let link {
      attributed.addAttribute(.link, value: link.destination, range: link.range)
    }
    return try attributed.data(
      from: NSRange(location: 0, length: attributed.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
  }

}
