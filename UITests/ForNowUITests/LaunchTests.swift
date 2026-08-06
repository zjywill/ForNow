import XCTest

final class LaunchTests: XCTestCase {
  @MainActor
  func testApplicationLaunchesWithFocusedScratchpad() {
    let app = XCUIApplication()
    app.launchEnvironment["FORNOW_UI_TESTING"] = "1"
    app.launch()

    XCTAssertTrue(app.textViews["Scratchpad"].waitForExistence(timeout: 5))
  }

  @MainActor
  func test_UIT_UI_003_AppearanceAndLongestShortcutLabelsFitSettingsWindow() {
    let app = XCUIApplication()
    app.launchEnvironment["FORNOW_UI_TESTING"] = "1"
    app.launch()
    app.typeKey(",", modifierFlags: .command)

    XCTAssertTrue(
      app.staticTexts["List spacing on blank or grid paper"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Increase Text Size"].exists)
    XCTAssertTrue(app.staticTexts["Text layout direction"].exists)
    XCTAssertTrue(app.switches["Translucent background"].exists)

    let settingsWindow = app.windows["ForNow Settings"]
    for action in [
      "Previous Note", "Next Note", "Newest Note", "New Note", "Promote Note",
      "Delete Note", "Search Notes", "Toggle Pin", "Increase Text Size", "Decrease Text Size",
    ] {
      let keyField = app.textFields["\(action) key"]
      XCTAssertTrue(keyField.exists)
      XCTAssertGreaterThanOrEqual(keyField.frame.minX, settingsWindow.frame.minX)
      XCTAssertLessThanOrEqual(keyField.frame.maxX, settingsWindow.frame.maxX)
    }
  }

  @MainActor
  func test_UIT_AUTO_001_CommandShowsActionableDestinationIndicator() {
    let app = XCUIApplication()
    app.launchEnvironment["FORNOW_UI_TESTING"] = "1"
    app.launch()
    let editor = app.textViews["Scratchpad"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))

    editor.click()
    editor.typeText("paste")
    editor.typeKey(.return, modifierFlags: [])

    let status = app.descendants(matching: .any)["AutoPaste status"]
    XCTAssertTrue(status.waitForExistence(timeout: 3))
    XCTAssertTrue(status.label.contains("Untitled note"))
    let stop = app.buttons["Stop AutoPaste"].firstMatch
    XCTAssertTrue(stop.waitForExistence(timeout: 2))
    stop.click()
    XCTAssertTrue(status.waitForNonExistence(timeout: 2))
  }
}
