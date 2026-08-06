import AppKit
import ForNowDesign
import ForNowEditor
import XCTest

final class AppearanceProjectionTests: XCTestCase {
  @MainActor
  func test_ET_EDIT_007_ForcedDirectionsAndAppearanceNeverRewriteSourceOrUndo() async {
    let source = "English سطر فارسی\nsecond line"
    let container = ProjectionEditorContainer(
      initialText: source,
      editorSettings: EditorSettings(layoutDirection: .rightToLeft),
      appearanceSettings: AppearanceSettings(
        paperStyle: .lined,
        textSize: .large,
        doublesTextSize: true
      )
    )
    await container.waitForPendingProjection()

    XCTAssertEqual(container.textView.string, source)
    XCTAssertEqual(container.textView.baseWritingDirection, .rightToLeft)
    XCTAssertEqual(container.textView.alignment, .right)
    XCTAssertEqual(container.textView.font?.pointSize, 42)
    XCTAssertFalse(container.textView.undoManager?.canUndo ?? false)

    container.editorSettings = EditorSettings(layoutDirection: .leftToRight)
    XCTAssertEqual(container.textView.string, source)
    XCTAssertEqual(container.textView.baseWritingDirection, .leftToRight)
    XCTAssertEqual(container.textView.alignment, .left)
    XCTAssertFalse(container.textView.undoManager?.canUndo ?? false)

    container.editorSettings = EditorSettings(layoutDirection: .natural)
    XCTAssertEqual(container.textView.string, source)
    XCTAssertEqual(container.textView.baseWritingDirection, .natural)
    XCTAssertEqual(container.textView.alignment, .natural)
  }

  @MainActor
  func test_UIT_UI_001_ThemeAndSizeUpdateInPlaceWithoutSourceMutation() {
    let source = "list\nfirst\nsecond"
    let container = ProjectionEditorContainer(initialText: source)
    let initialVersion = container.currentProjection.sourceVersion
    container.appearanceSettings = AppearanceSettings(
      lightThemeID: .sageLight,
      darkThemeID: .charcoalDark,
      paperStyle: .dotted,
      textSize: .extraSmall
    )

    XCTAssertEqual(container.textView.string, source)
    XCTAssertEqual(container.textView.font?.pointSize, 14)
    XCTAssertEqual(container.currentProjection.sourceVersion, initialVersion)
    XCTAssertFalse(container.textView.undoManager?.canUndo ?? false)
  }

  @MainActor
  func test_UIT_UI_002C_ListSpacingUsesSeparateLinedAndBlankMetrics() {
    let source = "list\nfirst\nsecond"
    let container = ProjectionEditorContainer(
      initialText: source,
      appearanceSettings: AppearanceSettings(
        paperStyle: .lined,
        linedPaperListSpacing: .compact,
        blankPaperListSpacing: .spacious
      )
    )

    XCTAssertEqual(container.textView.defaultParagraphStyle?.lineSpacing, 2)

    container.appearanceSettings.paperStyle = .smallGrid
    XCTAssertEqual(container.textView.defaultParagraphStyle?.lineSpacing, 10)
    XCTAssertEqual(container.textView.string, source)
  }

  @MainActor
  func test_UIT_UI_002C_SourceModeChangeRefreshesListSpacing() {
    let container = ProjectionEditorContainer(
      initialText: "plain\nfirst",
      appearanceSettings: AppearanceSettings(
        paperStyle: .lined,
        linedPaperListSpacing: .compact
      )
    )
    XCTAssertEqual(container.textView.defaultParagraphStyle?.lineSpacing, 0)

    container.textView.string = "list\nfirst"
    container.textDidChange(Notification(name: NSText.didChangeNotification))
    XCTAssertEqual(container.textView.defaultParagraphStyle?.lineSpacing, 2)

    container.textView.string = "plain\nfirst"
    container.textDidChange(Notification(name: NSText.didChangeNotification))
    XCTAssertEqual(container.textView.defaultParagraphStyle?.lineSpacing, 0)
  }

  @MainActor
  func test_UIT_UI_002A_Through_UIT_UI_002E_PaperStylesProduceDistinctPixels() throws {
    let blank = renderedEditor(
      settings: AppearanceSettings(paperStyle: .blank)
    )
    let lined = renderedEditor(
      settings: AppearanceSettings(paperStyle: .lined, paperOpacity: .bold)
    )
    let dotted = renderedEditor(
      settings: AppearanceSettings(paperStyle: .dotted, paperOpacity: .bold)
    )
    let smallGrid = renderedEditor(
      settings: AppearanceSettings(paperStyle: .smallGrid, paperOpacity: .bold)
    )
    let largeGrid = renderedEditor(
      settings: AppearanceSettings(paperStyle: .largeGrid, paperOpacity: .bold)
    )

    XCTAssertNotEqual(blank, lined)
    XCTAssertNotEqual(lined, dotted)
    XCTAssertNotEqual(dotted, smallGrid)
    XCTAssertNotEqual(smallGrid, largeGrid)
  }

  @MainActor
  func test_ET_EDIT_007_NaturalRTLListCheckboxUsesRightGutterWithoutCoveringText() async throws {
    let source = "list\nسطر فارسی"
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
    defer { window.close() }
    container.layoutSubtreeIfNeeded()
    await container.waitForPendingProjection()
    await Task.yield()
    container.layoutSubtreeIfNeeded()

    let checkbox = try XCTUnwrap(
      container.decorationAccessibilityContainer.subviews
        .compactMap { $0 as? NSButton }
        .first { $0.accessibilityRole() == .checkBox }
    )
    let frameInTextView = container.textView.convert(
      checkbox.frame,
      from: container.decorationAccessibilityContainer
    )

    XCTAssertGreaterThanOrEqual(frameInTextView.minX, container.textView.bounds.maxX - 21)
    XCTAssertEqual(container.textView.string, source)
    XCTAssertFalse(container.textView.undoManager?.canUndo ?? false)
  }

  @MainActor
  private func renderedEditor(settings: AppearanceSettings) -> Data {
    let container = ProjectionEditorContainer(
      initialText: "",
      appearanceSettings: settings
    )
    container.frame = NSRect(x: 0, y: 0, width: 240, height: 160)
    container.layoutSubtreeIfNeeded()
    container.displayIfNeeded()
    guard let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
      return Data()
    }
    container.cacheDisplay(in: container.bounds, to: bitmap)
    return bitmap.representation(using: .png, properties: [:]) ?? Data()
  }
}
