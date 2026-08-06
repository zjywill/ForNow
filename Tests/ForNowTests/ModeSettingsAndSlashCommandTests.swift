import ForNowCore
import ForNowEditor
import ForNowModes
import XCTest

@testable import ForNow

final class ModeSettingsAndSlashCommandTests: XCTestCase {
  func testModeSettingsRoundTripAndInvalidPayloadFallback() async throws {
    let suiteName = "ForNowModeSettingsTests.\(UUID().uuidString)"
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
    var settings = ModeSettings()
    settings.definitions[2].aliases.append("calculate")
    settings.definitions[2].mainAlias = "calculate"
    let store = UserDefaultsModeSettingsStore(suiteName: suiteName)

    try await store.save(settings)
    let loadedSettings = await store.load()
    XCTAssertEqual(loadedSettings, settings)

    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.set(Data("not-json".utf8), forKey: "app.fornow.mode.settings.v1")
    let fallbackSettings = await store.load()
    XCTAssertEqual(fallbackSettings, ModeSettings())
  }

  func testModeSettingsStoreRejectsConflictingAliasesBeforeWriting() async throws {
    let store = InMemoryModeSettingsStore()
    var settings = ModeSettings()
    settings.definitions[0].aliases = ["plain", "math"]

    do {
      try await store.save(settings)
      XCTFail("A conflicting alias must be rejected")
    } catch {
      XCTAssertEqual(
        error as? ModeAliasRegistryError,
        .aliasCollision("math", .plain, .math)
      )
    }
    let storedSettings = await store.load()
    XCTAssertEqual(storedSettings, ModeSettings())
  }

  @MainActor
  func testKeywordMasterSwitchChangesMeaningfulContentWithoutChangingSource() async throws {
    let repository = InMemoryNoteRepository()
    var disabledSettings = ModeSettings()
    disabledSettings.keywordInterpretationEnabled = false
    let environment = AppEnvironment.test(
      repository: repository,
      modeSettings: InMemoryModeSettingsStore(settings: disabledSettings)
    )
    try await environment.start()

    try await environment.noteSession.applyEditorText("math", hasMarkedText: false)
    _ = try await repository.flush()

    XCTAssertEqual(environment.noteSession.text, "math")
    XCTAssertEqual(environment.noteSession.phase, .durable)
    let storedBodies = try await repository.allNotes().map(\.body)
    XCTAssertEqual(storedBodies, ["math"])
    try await environment.shutdown()
  }

  @MainActor
  func testLoadingModeSettingsDoesNotMasqueradeAsPrelaunchEditorInput() async throws {
    let existing = Note(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
      body: "existing source",
      createdAt: Date(timeIntervalSince1970: 1),
      modifiedAt: Date(timeIntervalSince1970: 2),
      orderKey: 0
    )
    let repository = InMemoryNoteRepository(notes: [existing])
    var modeSettings = ModeSettings()
    modeSettings.definitions[2].aliases.append("calculate")
    let environment = AppEnvironment.test(
      repository: repository,
      lifecycleSettings: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: false)
      ),
      modeSettings: InMemoryModeSettingsStore(settings: modeSettings)
    )

    try await environment.start()

    XCTAssertEqual(environment.noteSession.currentNoteID, existing.id)
    XCTAssertEqual(environment.noteSession.text, existing.body)
    XCTAssertEqual(environment.noteSession.phase, .durable)
    try await environment.shutdown()
  }

  @MainActor
  func test_UIT_CMD_003_NumberSelectionReplacesHeaderAndPublishesVoiceOverState() throws {
    let target = EditorSlashCommandTarget()
    let model = SlashCommandModel(editorTarget: target)
    let source = "math: Budget\n1 + 1"
    let container = ProjectionEditorContainer(initialText: source)
    target.attach(to: container)
    container.textView.setSelectedRange(NSRange(location: 0, length: 0))

    XCTAssertTrue(model.present())
    XCTAssertEqual(model.commands.count, ModeID.allCases.count)
    XCTAssertEqual(model.selectedIndex, 0)

    XCTAssertTrue(model.handleKeyCommand(.moveDown))
    XCTAssertEqual(model.selectedIndex, 1)
    XCTAssertEqual(model.selectedCommand?.modeID, .list)
    XCTAssertTrue(model.handleKeyCommand(.selectNumber(7)))

    XCTAssertFalse(model.isPresented)
    XCTAssertEqual(container.textView.string, "code: Budget\n1 + 1")
    XCTAssertEqual(container.textView.selectedRange(), NSRange(location: 4, length: 0))
  }

  @MainActor
  func testSlashFilteringEscapeAndDisabledSettingsNeverMutateSource() {
    let target = EditorSlashCommandTarget()
    let model = SlashCommandModel(editorTarget: target)
    let container = ProjectionEditorContainer(initialText: "")
    target.attach(to: container)

    XCTAssertTrue(model.present())
    XCTAssertTrue(model.handleKeyCommand(.append("av")))
    XCTAssertEqual(model.commands.map(\.modeID), [.average])
    XCTAssertTrue(model.handleKeyCommand(.dismiss))
    XCTAssertEqual(container.textView.string, "")
    XCTAssertFalse(container.textView.undoManager?.canUndo ?? true)

    var disabled = ModeSettings()
    disabled.keywordInterpretationEnabled = false
    let disabledContainer = ProjectionEditorContainer(initialText: "", modeSettings: disabled)
    target.attach(to: disabledContainer)
    XCTAssertFalse(model.present())
    XCTAssertEqual(disabledContainer.textView.string, "")
  }

  @MainActor
  func testRealTextViewRoutesSlashFilteringAndReturnWithoutProvisionalSource() throws {
    let target = EditorSlashCommandTarget()
    let model = SlashCommandModel(editorTarget: target)
    let container = ProjectionEditorContainer(initialText: "")
    target.attach(to: container)

    container.textView.keyDown(with: keyEvent(characters: "/", keyCode: 44))
    XCTAssertTrue(model.isPresented)
    XCTAssertEqual(container.textView.string, "")

    container.textView.keyDown(with: keyEvent(characters: "m", keyCode: 46))
    container.textView.keyDown(with: keyEvent(characters: "a", keyCode: 0))
    XCTAssertEqual(model.query, "ma")
    XCTAssertEqual(model.commands.map(\.modeID), [.math])
    XCTAssertEqual(container.textView.string, "")

    container.textView.keyDown(with: keyEvent(characters: "\r", keyCode: 36))
    XCTAssertFalse(model.isPresented)
    XCTAssertEqual(container.textView.string, "math")
    let undoManager = try XCTUnwrap(container.textView.undoManager)
    undoManager.undo()
    XCTAssertEqual(container.textView.string, "")
  }

  @MainActor
  private func keyEvent(characters: String, keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: keyCode
    )!
  }
}
