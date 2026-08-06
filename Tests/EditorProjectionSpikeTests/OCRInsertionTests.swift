import AppKit
import ForNowCore
import XCTest

@testable import ForNowEditor

@MainActor
final class OCRInsertionTests: XCTestCase {
  func test_IT_OCR_001E_ImagePasteCapturesSelectionAndSourceVersion() throws {
    let container = ProjectionEditorContainer(initialText: "Before selected After")
    let target = EditorOCRTarget()
    target.attach(to: container)
    container.textView.setSelectedRange(
      (container.textView.string as NSString).range(of: "selected")
    )
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    let imageData = Data([0x89, 0x50, 0x4E, 0x47])
    pasteboard.clearContents()
    pasteboard.setData(imageData, forType: .png)
    var captured: EditorOCRRequest?
    target.requestHandler = { captured = $0 }

    XCTAssertTrue(container.submitOCRInput(from: pasteboard, source: .paste))
    let request = try XCTUnwrap(captured)
    XCTAssertEqual(request.source, .paste)
    XCTAssertEqual(request.anchor.sourceVersion, 0)
    XCTAssertEqual(
      request.anchor.replacementRange.nsRange,
      NSRange(location: 7, length: 8)
    )
    XCTAssertEqual(
      request.image,
      .encodedData(imageData, contentTypeIdentifier: "public.png")
    )
  }

  func test_IT_OCR_001F_ImageDropCapturesDropPositionInsteadOfSelection() throws {
    let container = ProjectionEditorContainer(initialText: "Alpha Omega")
    let target = EditorOCRTarget()
    target.attach(to: container)
    container.textView.setSelectedRange(NSRange(location: 0, length: 5))
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    pasteboard.clearContents()
    pasteboard.setData(Data([1, 2, 3]), forType: .png)
    var captured: EditorOCRRequest?
    target.requestHandler = { captured = $0 }

    XCTAssertTrue(
      container.submitOCRInput(
        from: pasteboard,
        source: .dragAndDrop,
        replacementRange: NSRange(location: 6, length: 0)
      )
    )
    let request = try XCTUnwrap(captured)
    XCTAssertEqual(request.source, .dragAndDrop)
    XCTAssertEqual(request.anchor.replacementRange.nsRange, NSRange(location: 6, length: 0))
  }

  func test_ET_OCR_003A_UnchangedSourceInsertsAtCapturedPosition() {
    let container = ProjectionEditorContainer(initialText: "Alpha Omega")
    let target = EditorOCRTarget()
    target.attach(to: container)
    let anchor = EditorOCRInsertionAnchor(
      sourceVersion: 0,
      replacementRange: SourceRange(location: SourceOffset(utf16Offset: 6), length: 0)
    )
    container.textView.setSelectedRange(NSRange(location: 0, length: 0))

    XCTAssertEqual(target.insertRecognizedText("Beta ", at: anchor), .inserted)
    XCTAssertEqual(container.textView.string, "Alpha Beta Omega")
  }

  func test_ET_OCR_003B_ChangedSourceRequiresCurrentSelectionInsertion() {
    let container = ProjectionEditorContainer(initialText: "Alpha Omega")
    let target = EditorOCRTarget()
    target.attach(to: container)
    let anchor = EditorOCRInsertionAnchor(
      sourceVersion: 0,
      replacementRange: SourceRange(location: SourceOffset(utf16Offset: 6), length: 0)
    )
    container.textView.insertText("Updated ", replacementRange: NSRange(location: 0, length: 0))
    container.textView.setSelectedRange(
      NSRange(location: container.textView.string.utf16.count, length: 0)
    )

    XCTAssertEqual(target.insertRecognizedText("Beta", at: anchor), .sourceChanged)
    XCTAssertEqual(container.textView.string, "Updated Alpha Omega")
    XCTAssertTrue(target.insertRecognizedTextAtCurrentSelection(" Beta"))
    XCTAssertEqual(container.textView.string, "Updated Alpha Omega Beta")
  }

  func test_ET_OCR_003D_InsertionIsExactlyOneUndoableEdit() throws {
    let container = ProjectionEditorContainer(initialText: "Before After")
    let target = EditorOCRTarget()
    target.attach(to: container)
    let anchor = EditorOCRInsertionAnchor(
      sourceVersion: 0,
      replacementRange: SourceRange(location: SourceOffset(utf16Offset: 7), length: 0)
    )

    XCTAssertEqual(target.insertRecognizedText("Text ", at: anchor), .inserted)
    XCTAssertEqual(container.textView.string, "Before Text After")
    let undoManager = try XCTUnwrap(container.textView.undoManager)
    XCTAssertTrue(undoManager.canUndo)
    undoManager.undo()
    XCTAssertEqual(container.textView.string, "Before After")
    XCTAssertFalse(undoManager.canUndo)
    XCTAssertTrue(undoManager.canRedo)
    undoManager.redo()
    XCTAssertEqual(container.textView.string, "Before Text After")
  }

  func test_ET_OCR_003E_RecognizedTextRemainsCanonicalSource() {
    let container = ProjectionEditorContainer(initialText: "")
    let target = EditorOCRTarget()
    target.attach(to: container)
    let anchor = EditorOCRInsertionAnchor(
      sourceVersion: 0,
      replacementRange: SourceRange(location: SourceOffset(utf16Offset: 0), length: 0)
    )

    XCTAssertEqual(target.insertRecognizedText("Hello\n你好", at: anchor), .inserted)
    XCTAssertEqual(container.textView.string, "Hello\n你好")
    XCTAssertEqual(container.contextualCopyText(for: NSRange(location: 0, length: 0)), "Hello\n你好")
    XCTAssertFalse(container.textView.string.contains("Recognizing"))
  }
}
