import ForNowCore
import ForNowEditor
import ForNowModes
import XCTest

final class ExportDocumentTests: XCTestCase {
  func test_UT_EXP_001A_CanonicalDocumentPreservesUnicodeAndLineEndings() {
    let source = "标题 📝\r\nCafe\u{301}\tvalue  \r\n"
    let note = makeNote(body: source, sourceRevision: 7)

    let document = ExportDocumentBuilder().document(
      from: note,
      settings: ExportSettings(usesFirstLineAsTitle: false),
      modeSettings: ModeSettings(),
      exportedAt: exportDate
    )

    XCTAssertEqual(document.text, source)
    XCTAssertEqual(document.content, source)
    XCTAssertNil(document.title)
    XCTAssertEqual(document.sourceRevision, 7)
  }

  func test_UT_EXP_001B_KeywordOmissionUsesConfiguredModeRegistry() {
    let source = "math: Quarterly totals\n1 + 1 ="
    let note = makeNote(body: source)
    let builder = ExportDocumentBuilder()

    let omitted = builder.document(
      from: note,
      settings: ExportSettings(omitsKeywords: true, usesFirstLineAsTitle: false),
      modeSettings: ModeSettings(),
      exportedAt: exportDate
    )
    let retained = builder.document(
      from: note,
      settings: ExportSettings(omitsKeywords: false, usesFirstLineAsTitle: false),
      modeSettings: ModeSettings(),
      exportedAt: exportDate
    )

    XCTAssertEqual(omitted.text, "Quarterly totals\n1 + 1 =")
    XCTAssertEqual(retained.text, source)
  }

  func test_UT_EXP_001C_FirstLineTitleKeepsFullTextAndExactRemainder() {
    let note = makeNote(body: "  Project Atlas  \r\nSecond line\r\n")

    let document = ExportDocumentBuilder().document(
      from: note,
      settings: ExportSettings(usesFirstLineAsTitle: true),
      modeSettings: ModeSettings(),
      exportedAt: exportDate
    )

    XCTAssertEqual(document.title, "Project Atlas")
    XCTAssertEqual(document.content, "Second line\r\n")
    XCTAssertEqual(document.text, "  Project Atlas  \r\nSecond line\r\n")
  }

  func test_UT_EXP_001D_OriginalLinkSurvivesCanonicalProjection() {
    let url = "https://example.com/a/long/path?first=A%20B&second=C#anchor"
    let note = makeNote(body: "Links\nOpen \(url)")

    let document = ExportDocumentBuilder().document(
      from: note,
      settings: ExportSettings(),
      modeSettings: ModeSettings(),
      exportedAt: exportDate
    )

    XCTAssertEqual(document.content, "Open \(url)")
    XCTAssertTrue(document.text.contains(url))
  }

  func test_UT_EXP_001E_ConfiguredChecklistTriggerIsAlwaysRemoved() {
    var modeSettings = ModeSettings()
    modeSettings.checklistTrigger = "done"
    let note = makeNote(body: "list: Tasks\nFirst done\nLiteral done value\nSecond /x")

    let document = ExportDocumentBuilder().document(
      from: note,
      settings: ExportSettings(),
      modeSettings: modeSettings,
      exportedAt: exportDate
    )

    XCTAssertEqual(document.title, "Tasks")
    XCTAssertEqual(document.content, "First\nLiteral done value\nSecond /x")
  }

  func test_UT_EXP_001F_BuildingEveryPolicyNeverMutatesNote() {
    let source = "list: Source title\nFirst /x\nhttps://example.com/full"
    let note = makeNote(body: source, sourceRevision: 42)
    let original = note
    let builder = ExportDocumentBuilder()

    for omitsKeywords in [false, true] {
      for usesTitle in [false, true] {
        _ = builder.document(
          from: note,
          settings: ExportSettings(
            omitsKeywords: omitsKeywords,
            usesFirstLineAsTitle: usesTitle
          ),
          modeSettings: ModeSettings(),
          exportedAt: exportDate
        )
      }
    }

    XCTAssertEqual(note, original)
    XCTAssertEqual(note.body, source)
    XCTAssertEqual(note.sourceRevision, 42)
  }

  private var exportDate: Date {
    Date(timeIntervalSince1970: 1_704_067_200)
  }

  private func makeNote(body: String, sourceRevision: Int64 = 0) -> Note {
    Note(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
      body: body,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
      orderKey: 1,
      sourceRevision: sourceRevision
    )
  }
}
