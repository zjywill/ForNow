import AppKit
import ForNowEditor
import XCTest

final class SmokePerformanceTests: XCTestCase {
  func testUTF16OffsetIterationPerformance() {
    let fixture = String(repeating: "ForNow 你好 e\u{301} 📝\n", count: 1_000)

    measure {
      _ = fixture.utf16.count
    }
  }

  @MainActor
  func test_PT_EDIT_001_FiftyThousandCharacterEditStaysBelowSynchronousBudget() async {
    let line = "ordinary source 你好 e\u{301} 📝\n"
    let repetitionCount = 50_000 / line.count + 1
    let fixture = String(String(repeating: line, count: repetitionCount).prefix(50_000))
    XCTAssertEqual(fixture.count, 50_000)
    let container = ProjectionEditorContainer(initialText: fixture)
    await container.waitForPendingProjection()
    var durations: [Double] = []
    let clock = ContinuousClock()

    for index in 0..<30 {
      container.textView.string = fixture + String(index % 10)
      let startedAt = clock.now
      container.textDidChange(Notification(name: NSText.didChangeNotification))
      durations.append(milliseconds(startedAt.duration(to: clock.now)))
    }
    await container.waitForPendingProjection()

    let ordered = durations.sorted()
    let p50 = ordered[ordered.count / 2]
    let percentileIndex = min(ordered.count - 1, Int(ceil(Double(ordered.count) * 0.95)) - 1)
    let p95 = ordered[percentileIndex]
    let worst = ordered[ordered.count - 1]
    print(
      "PT-EDIT-001 samples=\(ordered.count) p50=\(p50)ms p95=\(p95)ms worst=\(worst)ms"
    )
    XCTAssertLessThan(
      p95,
      4,
      "50k synchronous edit processing p95 was \(p95) ms; budget is below 4 ms"
    )
    XCTAssertEqual(container.textView.string.count, 50_001)
    let diagnostics = await container.projectionPipelineDiagnostics()
    XCTAssertEqual(diagnostics.latestAppliedVersion, diagnostics.latestRequestedVersion)
    XCTAssertGreaterThanOrEqual(diagnostics.submittedCount, 31)
  }

  private func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
