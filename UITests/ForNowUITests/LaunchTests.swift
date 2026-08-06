import XCTest

final class LaunchTests: XCTestCase {
  @MainActor
  func testApplicationLaunchesWithFocusedScratchpad() {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.textViews["Scratchpad"].waitForExistence(timeout: 5))
  }
}
