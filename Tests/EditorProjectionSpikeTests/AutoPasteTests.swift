import ForNowModes
import Foundation
import XCTest

final class AutoPasteTests: XCTestCase {
  func test_UT_AUTO_001_CommandParserAcceptsExactCommandAndRejectsLookalikes() {
    let parser = AutoPasteCommandParser()

    XCTAssertEqual(parser.parse("paste"), AutoPasteCommand())
    XCTAssertEqual(parser.parse("PASTE\t"), AutoPasteCommand())
    XCTAssertNil(parser.parse(" paste"))
    XCTAssertNil(parser.parse("paste now"))
    XCTAssertNil(parser.parse("pasted"))
    XCTAssertNil(parser.parse("paste("))
  }

  func test_UT_AUTO_002A_ChangeCountIsProcessedOnlyOnce() {
    var deduplicator = AutoPasteEventDeduplicator()

    XCTAssertTrue(deduplicator.accepts(changeCount: 7, text: "alpha"))
    XCTAssertFalse(deduplicator.accepts(changeCount: 7, text: "beta"))
    XCTAssertEqual(deduplicator.lastObservedChangeCount, 7)
  }

  func test_UT_AUTO_002B_RepeatedContentHashIsRejectedAcrossChangeCounts() {
    var deduplicator = AutoPasteEventDeduplicator()

    XCTAssertTrue(deduplicator.accepts(changeCount: 1, text: "same"))
    XCTAssertFalse(deduplicator.accepts(changeCount: 2, text: "same"))
    XCTAssertEqual(deduplicator.historyCount, 1)
  }

  func test_UT_AUTO_002C_NormalizedLineEndingsDeduplicateAndEmptyTextIsIgnored() {
    var deduplicator = AutoPasteEventDeduplicator()

    XCTAssertTrue(deduplicator.accepts(changeCount: 1, text: "one\r\ntwo"))
    XCTAssertFalse(deduplicator.accepts(changeCount: 2, text: "one\ntwo"))
    XCTAssertFalse(deduplicator.accepts(changeCount: 3, text: "\u{0000}"))
  }

  func test_UT_AUTO_002D_HashHistoryRemainsBoundedAndEvictsOldest() {
    var deduplicator = AutoPasteEventDeduplicator(historyLimit: 2)

    XCTAssertTrue(deduplicator.accepts(changeCount: 1, text: "one"))
    XCTAssertTrue(deduplicator.accepts(changeCount: 2, text: "two"))
    XCTAssertTrue(deduplicator.accepts(changeCount: 3, text: "three"))
    XCTAssertEqual(deduplicator.historyCount, 2)
    XCTAssertTrue(deduplicator.accepts(changeCount: 4, text: "one"))
    XCTAssertEqual(deduplicator.historyCount, 2)
  }

  func test_UT_AUTO_002E_DeduplicatorRetainsHashesRatherThanClipboardText() {
    var deduplicator = AutoPasteEventDeduplicator(historyLimit: 4)
    let privateText = "private clipboard canary"

    XCTAssertTrue(deduplicator.accepts(changeCount: 1, text: privateText))
    XCTAssertEqual(deduplicator.historyCount, 1)
    XCTAssertFalse(String(reflecting: deduplicator).contains(privateText))
  }

  func test_UT_AUTO_002F_OneThousandEventsRespectTheBoundedHistoryWindow() {
    var deduplicator = AutoPasteEventDeduplicator(historyLimit: 64)
    var accepted = 0

    for index in 0..<1_000 {
      if deduplicator.accepts(changeCount: index, text: "item-\(index % 100)") {
        accepted += 1
      }
    }

    XCTAssertEqual(accepted, 1_000)
    XCTAssertEqual(deduplicator.historyCount, 64)
  }

  func test_SOAK_AUTO_001_TenThousandDistinctEventsStayBounded() {
    var deduplicator = AutoPasteEventDeduplicator(historyLimit: 64)

    for index in 0..<10_000 {
      XCTAssertTrue(deduplicator.accepts(changeCount: index, text: "event-\(index)"))
    }

    XCTAssertEqual(deduplicator.historyCount, 64)
  }

  func test_UT_AUTO_003A_DefaultDelimiterIsNewlineWithoutDoubleSpacingFirstCapture() {
    let policy = AutoPasteCapturePolicy()

    XCTAssertEqual(policy.separator, "\n")
    XCTAssertEqual(
      policy.appending("first", to: "paste\n", capturedAt: Date(), isFirstCapture: true),
      "paste\nfirst"
    )
    XCTAssertEqual(
      policy.appending("second", to: "paste\nfirst", capturedAt: Date(), isFirstCapture: false),
      "paste\nfirst\nsecond"
    )
  }

  func test_UT_AUTO_003B_CommandParsesLiteralCustomAndEmptyDelimiters() {
    let parser = AutoPasteCommandParser()

    XCTAssertEqual(parser.parse("paste(, )"), AutoPasteCommand(separatorOverride: ", "))
    XCTAssertEqual(parser.parse("paste()"), AutoPasteCommand(separatorOverride: ""))
    XCTAssertNil(parser.parse("paste(\(String(repeating: "x", count: 257)))"))
  }

  func test_UT_AUTO_003C_PrefixIsAppliedToEveryCapturedItem() {
    let policy = AutoPasteCapturePolicy(prefix: "- ")

    XCTAssertEqual(policy.formattedItem("item", capturedAt: Date()), "- item")
  }

  func test_UT_AUTO_003D_SuffixIsAppliedToEveryCapturedItem() {
    let policy = AutoPasteCapturePolicy(suffix: ";")

    XCTAssertEqual(policy.formattedItem("item", capturedAt: Date()), "item;")
  }

  func test_UT_AUTO_003E_PreserveLinkTreatmentLeavesMarkdownUnchanged() {
    let source = "[ForNow](https://example.com/path)"

    XCTAssertEqual(
      AutoPasteCapturePolicy(linkTreatment: .preserve).formattedItem(
        source,
        capturedAt: Date()
      ),
      source
    )
  }

  func test_UT_AUTO_003F_LinkTreatmentsProduceReadableTextOrDestination() {
    let source = "[ForNow](https://example.com/path)"

    XCTAssertEqual(
      AutoPasteCapturePolicy(linkTreatment: .readableText).formattedItem(
        source,
        capturedAt: Date()
      ),
      "ForNow (https://example.com/path)"
    )
    XCTAssertEqual(
      AutoPasteCapturePolicy(linkTreatment: .destinationOnly).formattedItem(
        source,
        capturedAt: Date()
      ),
      "https://example.com/path"
    )
  }

  func test_UT_AUTO_003G_ISO8601TimestampIsDeterministicAndInsideAffixes() {
    let policy = AutoPasteCapturePolicy(
      prefix: "<",
      suffix: ">",
      timestampPolicy: .iso8601
    )

    XCTAssertEqual(
      policy.formattedItem("item", capturedAt: Date(timeIntervalSince1970: 0)),
      "<[1970-01-01T00:00:00Z] item>"
    )
  }

  func test_UT_AUTO_003H_CustomSeparatorAndLineNormalizationCompose() {
    let settings = AutoPasteSettings(separatorPreset: .commaSpace)
    let policy = AutoPasteCapturePolicy(settings: settings, separatorOverride: " | ")

    XCTAssertEqual(
      policy.appending(
        "one\r\ntwo\u{0000}",
        to: "existing",
        capturedAt: Date(),
        isFirstCapture: false
      ),
      "existing | one\ntwo"
    )
  }

  func testDestinationNameUsesFirstNonCommandLineAndBoundsDisplayText() {
    let resolver = AutoPasteDestinationName()

    XCTAssertEqual(resolver.resolve(from: "paste\n"), "Untitled note")
    XCTAssertEqual(resolver.resolve(from: "paste\nProject inbox\nbody"), "Project inbox")
    XCTAssertEqual(resolver.resolve(from: String(repeating: "a", count: 80)).count, 60)
  }
}
