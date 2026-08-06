import ForNowCore
import ForNowIntegrations
import ForNowModes
import Foundation
import XCTest

@testable import ForNow

@MainActor
final class AutoPasteModelTests: XCTestCase {
  func test_UT_AUTO_001_AllExplicitStopReasonsEndMonitoringImmediately() async {
    let clipboard = ManualClipboardService()
    let model = AutoPasteModel(
      clipboard: clipboard,
      clock: FixedWallClock(Date(timeIntervalSince1970: 0)),
      settingsStore: InMemoryAutoPasteSettingsStore(),
      appendHandler: { _, _, _, _, _ in .appended }
    )
    await model.loadSettings()

    for reason in [
      AutoPasteStopReason.escape,
      .repeatedCommand,
      .indicator,
      .destinationDeleted,
      .destinationUnavailable,
      .appTermination,
    ] {
      model.startSession(
        destinationNoteID: UUID(),
        destinationName: "Inbox",
        command: AutoPasteCommand()
      )
      XCTAssertTrue(model.isActive)
      XCTAssertTrue(clipboard.isMonitoring)

      model.stop(reason)

      XCTAssertFalse(model.isActive)
      XCTAssertFalse(clipboard.isMonitoring)
      XCTAssertEqual(model.lastStopReason, reason)
    }
  }

  func test_IT_AUTO_001_ScopedSessionKeepsOriginalDestinationAfterNavigation() async throws {
    let clipboard = ManualClipboardService()
    let repository = InMemoryNoteRepository()
    let destinationID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    let nextNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    let environment = AppEnvironment.test(
      repository: repository,
      uuidGenerator: SequenceUUIDGenerator(values: [destinationID, nextNoteID]),
      clipboard: clipboard
    )
    try await environment.start()
    XCTAssertFalse(clipboard.isMonitoring)
    XCTAssertEqual(clipboard.pollingActivityCount, 0)

    try await environment.executeAutoPasteCommand(
      AutoPasteCommand(),
      source: "Inbox\npaste\n"
    )
    XCTAssertEqual(environment.noteSession.currentNoteID, destinationID)
    XCTAssertEqual(environment.autoPasteModel.session?.destinationName, "Inbox")
    XCTAssertTrue(clipboard.isMonitoring)

    clipboard.emit(changeCount: 1, text: "alpha")
    await environment.autoPasteModel.waitForPendingEvents()
    XCTAssertEqual(environment.noteSession.text, "Inbox\npaste\nalpha")

    clipboard.emit(changeCount: 2, text: "alpha")
    await environment.autoPasteModel.waitForPendingEvents()
    XCTAssertEqual(environment.noteSession.text, "Inbox\npaste\nalpha")

    clipboard.setPasteboard(changeCount: 3, text: "copied inside ForNow")
    environment.markCurrentClipboardChangeAsOwn()
    clipboard.poll()
    await environment.autoPasteModel.waitForPendingEvents()
    XCTAssertEqual(environment.noteSession.text, "Inbox\npaste\nalpha")

    try await environment.noteSession.navigate(.next)
    XCTAssertNotEqual(environment.noteSession.currentNoteID, destinationID)
    XCTAssertEqual(environment.noteSession.text, "")

    clipboard.emit(changeCount: 4, text: "beta")
    await environment.autoPasteModel.waitForPendingEvents()
    XCTAssertEqual(environment.noteSession.text, "")
    let destination = try await repository.note(id: destinationID)
    XCTAssertEqual(
      destination?.body,
      "Inbox\npaste\nalpha\nbeta"
    )

    let pollingBeforeStop = clipboard.pollingActivityCount
    environment.stopAutoPaste(.indicator)
    clipboard.emit(changeCount: 5, text: "ignored")
    XCTAssertEqual(clipboard.pollingActivityCount, pollingBeforeStop)
    XCTAssertNil(environment.autoPasteModel.session)
    try await environment.shutdown()
  }

  func test_IT_AUTO_001_RepeatedCommandAndEscapeStopWithoutCapturingCurrentClipboard() async throws {
    let clipboard = ManualClipboardService()
    let environment = AppEnvironment.test(clipboard: clipboard)
    try await environment.start()

    try await environment.executeAutoPasteCommand(
      AutoPasteCommand(separatorOverride: ", "),
      source: "paste(, )\n"
    )
    XCTAssertTrue(environment.autoPasteModel.isActive)
    XCTAssertEqual(environment.autoPasteModel.session?.policy.separator, ", ")
    XCTAssertEqual(environment.noteSession.text, "paste(, )\n")

    try await environment.executeAutoPasteCommand(
      AutoPasteCommand(),
      source: "paste(, )\npaste\n"
    )
    XCTAssertFalse(environment.autoPasteModel.isActive)
    XCTAssertEqual(environment.autoPasteModel.lastStopReason, .repeatedCommand)

    try await environment.executeAutoPasteCommand(
      AutoPasteCommand(),
      source: "paste(, )\npaste\npaste\n"
    )
    environment.stopAutoPaste(.escape)
    XCTAssertFalse(environment.autoPasteModel.isActive)
    XCTAssertEqual(environment.autoPasteModel.lastStopReason, .escape)
    try await environment.shutdown()
  }

  func test_IT_AUTO_001_DestinationDeletionAndShutdownStopObservation() async throws {
    let clipboard = ManualClipboardService()
    let lifecycleSettings = InMemoryLifecycleSettingsStore(
      settings: LifecycleSettings(suppressesDeleteWarning: true)
    )
    let environment = AppEnvironment.test(
      clipboard: clipboard,
      lifecycleSettings: lifecycleSettings
    )
    try await environment.start()
    try await environment.executeAutoPasteCommand(
      AutoPasteCommand(),
      source: "Disposable\npaste\n"
    )

    try await environment.deleteCurrentNote()

    XCTAssertFalse(environment.autoPasteModel.isActive)
    XCTAssertFalse(clipboard.isMonitoring)
    XCTAssertEqual(environment.autoPasteModel.lastStopReason, .destinationDeleted)

    try await environment.executeAutoPasteCommand(
      AutoPasteCommand(),
      source: "Shutdown target\npaste\n"
    )
    XCTAssertTrue(clipboard.isMonitoring)
    try await environment.shutdown()
    XCTAssertFalse(clipboard.isMonitoring)
    XCTAssertEqual(environment.autoPasteModel.lastStopReason, .appTermination)
  }

  func test_IT_AUTO_001_MissingBackgroundDestinationStopsSessionSafely() async throws {
    let clipboard = ManualClipboardService()
    let repository = InMemoryNoteRepository()
    let destinationID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    let nextNoteID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    let environment = AppEnvironment.test(
      repository: repository,
      uuidGenerator: SequenceUUIDGenerator(values: [destinationID, nextNoteID]),
      clipboard: clipboard
    )
    try await environment.start()
    try await environment.executeAutoPasteCommand(
      AutoPasteCommand(),
      source: "Vanishing\npaste\n"
    )
    XCTAssertEqual(environment.noteSession.currentNoteID, destinationID)
    try await environment.noteSession.navigate(.next)
    try await repository.deleteNote(id: destinationID)

    clipboard.emit(changeCount: 1, text: "must not recreate")
    await environment.autoPasteModel.waitForPendingEvents()

    XCTAssertFalse(environment.autoPasteModel.isActive)
    XCTAssertFalse(clipboard.isMonitoring)
    XCTAssertEqual(environment.autoPasteModel.lastStopReason, .destinationUnavailable)
    let deletedDestination = try await repository.note(id: destinationID)
    XCTAssertNil(deletedDestination)
    try await environment.shutdown()
  }

  func test_UIT_AUTO_001_IndicatorExposesDestinationAndCaptureCount() {
    let session = AutoPasteSession(
      id: UUID(),
      destinationNoteID: UUID(),
      destinationName: "Project Inbox",
      policy: AutoPasteCapturePolicy(),
      captureCount: 3
    )

    XCTAssertEqual(session.destinationName, "Project Inbox")
    XCTAssertEqual(session.captureCount, 3)
    XCTAssertEqual("AutoPaste active for \(session.destinationName)", "AutoPaste active for Project Inbox")
  }

  func testAutoPasteSettingsRoundTripAndEnvironmentLoadsThem() async throws {
    let suiteName = "ForNowAutoPasteSettingsTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let expected = AutoPasteSettings(
      prefix: "[",
      suffix: "]",
      separatorPreset: .blankLine,
      linkTreatment: .readableText,
      timestampPolicy: .iso8601
    )
    let store = UserDefaultsAutoPasteSettingsStore(suiteName: suiteName)
    try await store.save(expected)
    let environment = AppEnvironment.test(autoPasteSettings: store)

    try await environment.start()

    XCTAssertEqual(environment.autoPasteModel.settings, expected)
    try await environment.shutdown()
  }
}

@MainActor
private final class ManualClipboardService: ClipboardService {
  private(set) var isMonitoring = false
  private(set) var pollingActivityCount: UInt64 = 0
  private var changeHandler: (@MainActor (ClipboardTextChange) -> Void)?
  private var changeCount = 0
  private var text = ""
  private var ownChangeCounts: Set<Int> = []

  func startMonitoring(
    changeHandler: @escaping @MainActor (ClipboardTextChange) -> Void
  ) {
    isMonitoring = true
    self.changeHandler = changeHandler
  }

  func stopMonitoring() {
    isMonitoring = false
    changeHandler = nil
    ownChangeCounts.removeAll()
  }

  func markCurrentChangeAsOwn() {
    ownChangeCounts.insert(changeCount)
  }

  func setPasteboard(changeCount: Int, text: String) {
    self.changeCount = changeCount
    self.text = text
  }

  func emit(changeCount: Int, text: String) {
    setPasteboard(changeCount: changeCount, text: text)
    poll()
  }

  func poll() {
    guard isMonitoring else { return }
    pollingActivityCount &+= 1
    guard ownChangeCounts.remove(changeCount) == nil else { return }
    changeHandler?(ClipboardTextChange(changeCount: changeCount, text: text))
  }
}
