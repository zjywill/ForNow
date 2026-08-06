import Carbon.HIToolbox
import CoreGraphics
import ForNowWindowing
import XCTest

final class WindowSpikeTests: XCTestCase {
  func test_UT_WIN_001_DefaultShortcutAndConflictDiagnostics() {
    let optionA = GlobalShortcutCandidate.optionA
    XCTAssertEqual(optionA.modifiers, .option)
    XCTAssertEqual(optionA.displayName, "⌥A")

    XCTAssertEqual(
      ShortcutRegistrationDiagnostic.evaluate(
        status: Int32(eventHotKeyExistsErr),
        candidate: optionA,
        operatingSystem: OperatingSystemVersion(
          majorVersion: 15,
          minorVersion: 0,
          patchVersion: 0
        )
      ),
      .optionOnlyUnavailable
    )
    XCTAssertEqual(
      ShortcutRegistrationDiagnostic.evaluate(
        status: Int32(eventHotKeyExistsErr),
        candidate: optionA,
        operatingSystem: OperatingSystemVersion(
          majorVersion: 15,
          minorVersion: 2,
          patchVersion: 0
        )
      ),
      .conflict
    )
  }

  func test_UT_WIN_001_UnmodifiedCandidateIsRejectedByRecorderPolicy() {
    let unmodified = GlobalShortcutCandidate(
      keyCode: GlobalShortcutCandidate.optionA.keyCode,
      modifiers: []
    )

    XCTAssertFalse(unmodified.isEligibleForGlobalRegistration)
    XCTAssertFalse(ShortcutRegistrationResult.invalid.isAccepted)
    XCTAssertTrue(ShortcutRegistrationResult.invalid.message.contains("previous shortcut"))
  }

  func test_UT_WIN_001_ConflictPreservesPreviousBinding() {
    let previous = GlobalShortcutCandidate.optionA
    let candidate = GlobalShortcutCandidate(
      keyCode: previous.keyCode,
      modifiers: [.command, .option]
    )
    var binding = GlobalShortcutBindingState(current: previous)

    let rejected = binding.apply(
      candidate,
      registrationStatus: Int32(eventHotKeyExistsErr),
      operatingSystem: OperatingSystemVersion(
        majorVersion: 26,
        minorVersion: 0,
        patchVersion: 0
      )
    )

    XCTAssertEqual(rejected, .conflict)
    XCTAssertEqual(binding.current, previous)
    XCTAssertEqual(
      binding.apply(
        candidate,
        registrationStatus: noErr,
        operatingSystem: OperatingSystemVersion(
          majorVersion: 26,
          minorVersion: 0,
          patchVersion: 0
        )
      ),
      .accepted
    )
    XCTAssertEqual(binding.current, candidate)
  }

  func test_UT_WIN_002_PresenceModesRetainAnInvocationSurface() {
    XCTAssertTrue(ApplicationPresenceMode.dock.showsDockIcon)
    XCTAssertFalse(ApplicationPresenceMode.dock.showsStatusItem)
    XCTAssertFalse(ApplicationPresenceMode.menuBar.showsDockIcon)
    XCTAssertTrue(ApplicationPresenceMode.menuBar.showsStatusItem)
    XCTAssertTrue(ApplicationPresenceMode.both.showsDockIcon)
    XCTAssertTrue(ApplicationPresenceMode.both.showsStatusItem)
    XCTAssertFalse(ApplicationPresenceMode.neither.showsDockIcon)
    XCTAssertFalse(ApplicationPresenceMode.neither.showsStatusItem)
  }

  func test_UT_WIN_002_DropdownDimensionsClampToVisibleScreen() {
    XCTAssertEqual(
      DropdownDimensions(width: 2_000, height: 40).clamped(
        to: CGSize(width: 1_200, height: 800)
      ),
      CGSize(width: 1_200, height: 280)
    )
    XCTAssertEqual(
      DropdownDimensions(width: 100, height: 2_000).clamped(
        to: CGSize(width: 320, height: 240)
      ),
      CGSize(width: 320, height: 240)
    )
  }

  func test_UT_WIN_003_PinAndFullScreenPoliciesRemainSeparate() {
    let standard = WindowPresentationPolicy.resolve(mode: .standard, isPinned: false)
    let pinned = WindowPresentationPolicy.resolve(mode: .standard, isPinned: true)
    let menuPanel = WindowPresentationPolicy.resolve(mode: .menuBarPanel, isPinned: false)
    let dropdownPanel = WindowPresentationPolicy.resolve(mode: .dropdownPanel, isPinned: false)

    XCTAssertEqual(standard.level, .normal)
    XCTAssertEqual(pinned.level, .floating)
    XCTAssertEqual(standard.collectionCapabilities, pinned.collectionCapabilities)
    XCTAssertFalse(standard.usesNonactivatingPanel)
    XCTAssertFalse(standard.collectionCapabilities.contains(.fullScreenAuxiliary))
    XCTAssertTrue(menuPanel.usesNonactivatingPanel)
    XCTAssertTrue(dropdownPanel.usesNonactivatingPanel)
    XCTAssertTrue(menuPanel.collectionCapabilities.contains(.fullScreenAuxiliary))
    XCTAssertTrue(menuPanel.collectionCapabilities.contains(.canJoinAllSpaces))
    XCTAssertFalse(menuPanel.collectionCapabilities.contains(.moveToActiveSpace))
  }

  func test_UT_WIN_003_OwnedPanelSuspendsAutoHideUntilReleased() {
    let suspension = AutoHideSuspension(kind: .save)
    var machine = WindowVisibilityStateMachine(
      state: WindowVisibilityState(
        isVisible: true,
        isApplicationActive: true,
        autoHideEnabled: true
      )
    )

    machine.transition(.beginOwnedPanel(suspension))
    let focusLoss = machine.transition(.applicationFocusChanged(false))
    XCTAssertTrue(focusLoss.current.isVisible)
    XCTAssertTrue(focusLoss.effects.isEmpty)

    let release = machine.transition(.endOwnedPanel(suspension))
    XCTAssertFalse(release.current.isVisible)
    XCTAssertEqual(release.effects, [.flushPendingSource, .orderOut])
  }

  func test_IT_WIN_005_AllHideAndClosePathsFlushFirst() {
    for source in [
      WindowInvocationSource.localCommand,
      WindowInvocationSource.globalShortcut,
      WindowInvocationSource.statusItem,
    ] {
      var machine = WindowVisibilityStateMachine(
        state: WindowVisibilityState(isVisible: true, isApplicationActive: true)
      )
      XCTAssertEqual(
        machine.transition(.toggle(source)).effects,
        [.flushPendingSource, .orderOut]
      )
    }

    var closeMachine = WindowVisibilityStateMachine(
      state: WindowVisibilityState(isVisible: true, isApplicationActive: true)
    )
    XCTAssertEqual(
      closeMachine.transition(.close).effects,
      [.flushPendingSource, .closeWindow]
    )
  }

  func test_IT_WIN_005_RepeatedShowFocusesWithoutAnotherShowEffect() {
    var machine = WindowVisibilityStateMachine()
    XCTAssertEqual(
      machine.transition(.show(.globalShortcut)).effects,
      [.showWindow, .focusEditor]
    )
    for _ in 0..<1_000 {
      XCTAssertEqual(
        machine.transition(.show(.globalShortcut)).effects,
        [.focusEditor]
      )
    }
  }

  func test_MT_WIN_004_SyntheticDualDisplayPlacementNeverLeavesVisibleFrame() {
    let left = ScreenGeometry(
      identifier: "left",
      frame: CGRect(x: -1_440, y: 0, width: 1_440, height: 900),
      visibleFrame: CGRect(x: -1_440, y: 24, width: 1_440, height: 852)
    )
    let right = ScreenGeometry(
      identifier: "right",
      frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
      visibleFrame: CGRect(x: 0, y: 50, width: 1_920, height: 1_030)
    )

    XCTAssertEqual(
      WindowPlacement.targetScreen(
        containing: CGPoint(x: -800, y: 400),
        screens: [left, right]
      ),
      left
    )
    for screen in [left, right] {
      let dropdown = WindowPlacement.frame(
        requestedSize: CGSize(width: 3_000, height: 2_000),
        on: screen,
        style: .dropdown(anchorX: screen.frame.maxX + 500)
      )
      XCTAssertTrue(WindowPlacement.isFullyVisible(dropdown, on: screen))
    }
  }
}
