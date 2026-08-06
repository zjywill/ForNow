import ForNowCore
import ForNowPersistence
import XCTest

@testable import ForNow

final class NoteLifecycleTests: XCTestCase {
  func test_UT_NOTE_002A_EmptySourceIsBlank() {
    XCTAssertEqual(MeaningfulContentPolicy().classify("", hasMarkedText: false), .blank)
  }

  func test_UT_NOTE_002B_SpacesAndTabsAreBlank() {
    XCTAssertEqual(
      MeaningfulContentPolicy().classify("  \t  ", hasMarkedText: false),
      .blank
    )
  }

  func test_UT_NOTE_002C_NewlinesAreBlank() {
    XCTAssertEqual(
      MeaningfulContentPolicy().classify("\n\r\n  \n", hasMarkedText: false),
      .blank
    )
  }

  func test_UT_NOTE_002D_KeywordOnlyIsBlankButTitleOrBodyIsMeaningful() {
    let policy = MeaningfulContentPolicy()

    XCTAssertEqual(policy.classify("math", hasMarkedText: false), .blank)
    XCTAssertEqual(policy.classify(" MATH:  ", hasMarkedText: false), .blank)
    XCTAssertEqual(policy.classify("math\n\t", hasMarkedText: false), .blank)
    XCTAssertEqual(policy.classify("math: Trip total", hasMarkedText: false), .meaningful)
    XCTAssertEqual(policy.classify("math\n1 + 1", hasMarkedText: false), .meaningful)
    XCTAssertEqual(policy.classify("not-a-mode", hasMarkedText: false), .meaningful)
  }

  @MainActor
  func test_UT_NOTE_002E_MarkedTextStaysTransientUntilCommitted() async throws {
    let repository = InMemoryNoteRepository()
    let session = makeSession(repository: repository)
    try await repository.prepare()
    try await session.start()

    try await session.applyEditorText("你", hasMarkedText: true)
    _ = try await repository.flush()
    let notesWithMarkedText = try await repository.allNotes()
    XCTAssertTrue(notesWithMarkedText.isEmpty)
    XCTAssertEqual(session.phase, .transient)

    try await session.applyEditorText("你", hasMarkedText: false)
    _ = try await repository.flush()
    let committedNotes = try await repository.allNotes()
    let note = try XCTUnwrap(committedNotes.first)
    XCTAssertEqual(note.body, "你")
    XCTAssertEqual(session.phase, .durable)
  }

  @MainActor
  func test_UT_NOTE_002F_TypeThenUndoToBlankLeavesNoRow() async throws {
    let repository = InMemoryNoteRepository()
    let session = makeSession(repository: repository)
    try await repository.prepare()
    try await session.start()

    try await session.applyEditorText("temporary", hasMarkedText: false)
    try await session.applyEditorText("", hasMarkedText: false)
    try await session.prepareForDeparture()
    _ = try await repository.flush()

    let notes = try await repository.allNotes()
    XCTAssertTrue(notes.isEmpty)
    XCTAssertEqual(session.phase, .transient)
    XCTAssertEqual(session.noteCount, 0)
  }

  @MainActor
  func test_IT_NOTE_002_FirstMeaningfulEditPersistsExactSourceAndStableID() async throws {
    let repository = InMemoryNoteRepository()
    let session = makeSession(repository: repository)
    try await repository.prepare()
    try await session.start()
    let transientID = try XCTUnwrap(session.currentNoteID)
    let source = "第一行 👩🏽‍💻\nhttps://example.com/a?b=1"

    try await session.applyEditorText(source, hasMarkedText: false)
    _ = try await repository.flush()
    let notesAfterFirstSave = try await repository.allNotes()
    let firstSave = try XCTUnwrap(notesAfterFirstSave.first)
    XCTAssertEqual(firstSave.id, transientID)
    XCTAssertEqual(firstSave.body, source)

    try await session.applyEditorText(source + "\nnext", hasMarkedText: false)
    _ = try await repository.flush()
    let notesAfterSecondSave = try await repository.allNotes()
    let secondSave = try XCTUnwrap(notesAfterSecondSave.first)
    XCTAssertEqual(secondSave.id, transientID)
    XCTAssertEqual(secondSave.body, source + "\nnext")
    XCTAssertEqual(session.noteCount, 1)
  }

  @MainActor
  func test_IT_NOTE_002_GRDBPersistsThenDiscardsWithoutBlankRow() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ForNow-NoteLifecycle-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = PersistenceNoteRepository(
      databaseURL: root.appendingPathComponent("ForNow.sqlite"),
      backupDirectoryURL: root.appendingPathComponent("Backups", isDirectory: true),
      debounce: .seconds(30)
    )
    let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
    let session = NoteSessionModel(
      repository: repository,
      clock: FixedWallClock(Date(timeIntervalSince1970: 10)),
      uuidGenerator: SequenceUUIDGenerator(values: [noteID]),
      settingsStore: InMemoryLifecycleSettingsStore()
    )
    let source = "原样 source 👨‍👩‍👧‍👦\nhttps://example.com"
    try await repository.prepare()
    try await session.start()

    try await session.applyEditorText(source, hasMarkedText: false)
    _ = try await repository.flush()
    let persistedNote = try await repository.note(id: noteID)
    let persisted = try XCTUnwrap(persistedNote)
    XCTAssertEqual(persisted.body, source)

    try await session.applyEditorText("", hasMarkedText: false)
    try await session.prepareForDeparture()
    _ = try await repository.flush()
    let notesAfterDiscard = try await repository.allNotes()
    XCTAssertTrue(notesAfterDiscard.isEmpty)
    try await repository.shutdown()
  }

  @MainActor
  func test_IT_NOTE_002_EditorInputBeforeRepositoryLoadIsNotLost() async throws {
    let repository = InMemoryNoteRepository()
    let session = makeSession(repository: repository)
    let source = "typed before startup 完整保留"

    session.editorTextChanged(source, hasMarkedText: false)
    try await repository.prepare()
    try await session.start()
    _ = try await repository.flush()

    let notes = try await repository.allNotes()
    let note = try XCTUnwrap(notes.first)
    XCTAssertEqual(note.body, source)
    XCTAssertEqual(session.text, source)
    XCTAssertEqual(session.currentNoteID, note.id)
  }

  func test_UT_NOTE_009A_LaunchSettingCreatesNewNote() {
    let settings = LifecycleSettings(createsNewNoteOnLaunch: true)
    XCTAssertTrue(
      ResumeNotePolicy().shouldCreateNewNote(
        for: .launch,
        settings: settings,
        now: Date(timeIntervalSince1970: 100),
        lastWindowClosedAt: nil
      )
    )
  }

  func test_UT_NOTE_009B_LaunchSettingResumesExistingNote() {
    let settings = LifecycleSettings(createsNewNoteOnLaunch: false)
    XCTAssertFalse(
      ResumeNotePolicy().shouldCreateNewNote(
        for: .launch,
        settings: settings,
        now: Date(timeIntervalSince1970: 100),
        lastWindowClosedAt: Date(timeIntervalSince1970: 0)
      )
    )
  }

  func test_UT_NOTE_009C_AlwaysAndNeverReopenPolicies() {
    let policy = ResumeNotePolicy()
    let now = Date(timeIntervalSince1970: 100)

    XCTAssertTrue(
      policy.shouldCreateNewNote(
        for: .reopen,
        settings: LifecycleSettings(reopenNewNotePolicy: .always),
        now: now,
        lastWindowClosedAt: nil
      )
    )
    XCTAssertFalse(
      policy.shouldCreateNewNote(
        for: .reopen,
        settings: LifecycleSettings(reopenNewNotePolicy: .never),
        now: now,
        lastWindowClosedAt: Date(timeIntervalSince1970: 0)
      )
    )
  }

  func test_UT_NOTE_009D_ThreeAndThirtyMinuteBoundaries() {
    assertThreshold(.afterThreeMinutes, seconds: 3 * 60)
    assertThreshold(.afterThirtyMinutes, seconds: 30 * 60)
  }

  func test_UT_NOTE_009E_OneHourAndOneDayBoundaries() {
    assertThreshold(.afterOneHour, seconds: 60 * 60)
    assertThreshold(.afterOneDay, seconds: 24 * 60 * 60)
  }

  func test_UT_NOTE_009F_SettingsAndCloseTimestampPersistIndependently() async throws {
    let suiteName = "ForNowTests.Lifecycle.\(UUID().uuidString)"
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsLifecycleSettingsStore(suiteName: suiteName)
    let settings = LifecycleSettings(
      createsNewNoteOnLaunch: false,
      reopenNewNotePolicy: .afterThirtyMinutes,
      showsNoteCount: true
    )
    let closeDate = Date(timeIntervalSince1970: 1234)

    try await store.save(settings)
    await store.recordWindowClosed(at: closeDate)
    let loadedSettings = await store.load()
    let loadedCloseDate = await store.lastWindowClosedAt()

    XCTAssertEqual(loadedSettings, settings)
    XCTAssertEqual(loadedCloseDate, closeDate)
  }

  @MainActor
  func test_IT_NOTE_009_ReopenThresholdCreatesTransientAndCountPreferenceApplies()
    async throws
  {
    let existing = Note(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
      body: "existing",
      createdAt: Date(timeIntervalSince1970: 1),
      modifiedAt: Date(timeIntervalSince1970: 2),
      orderKey: 0
    )
    let repository = InMemoryNoteRepository(notes: [existing])
    let settings = LifecycleSettings(
      createsNewNoteOnLaunch: false,
      reopenNewNotePolicy: .afterThreeMinutes,
      showsNoteCount: true
    )
    let settingsStore = InMemoryLifecycleSettingsStore(
      settings: settings,
      lastWindowClosedAt: Date(timeIntervalSince1970: 0)
    )
    let newID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    let session = NoteSessionModel(
      repository: repository,
      clock: FixedWallClock(Date(timeIntervalSince1970: 3 * 60)),
      uuidGenerator: SequenceUUIDGenerator(values: [newID]),
      settingsStore: settingsStore
    )
    try await repository.prepare()

    try await session.start()
    XCTAssertEqual(session.currentNoteID, existing.id)
    XCTAssertEqual(session.visibleNoteCount, 1)

    try await session.reopen()
    XCTAssertEqual(session.currentNoteID, newID)
    XCTAssertEqual(session.phase, .transient)
    XCTAssertEqual(session.visibleNoteCount, 1)
  }

  @MainActor
  private func makeSession(repository: InMemoryNoteRepository) -> NoteSessionModel {
    NoteSessionModel(
      repository: repository,
      clock: FixedWallClock(Date(timeIntervalSince1970: 10)),
      uuidGenerator: SequenceUUIDGenerator(values: [
        UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
      ]),
      settingsStore: InMemoryLifecycleSettingsStore()
    )
  }

  private func assertThreshold(
    _ reopenPolicy: ReopenNewNotePolicy,
    seconds: TimeInterval,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let policy = ResumeNotePolicy()
    let settings = LifecycleSettings(reopenNewNotePolicy: reopenPolicy)
    let closedAt = Date(timeIntervalSince1970: 1_000)
    XCTAssertFalse(
      policy.shouldCreateNewNote(
        for: .reopen,
        settings: settings,
        now: closedAt.addingTimeInterval(seconds - 0.001),
        lastWindowClosedAt: closedAt
      ),
      file: file,
      line: line
    )
    XCTAssertTrue(
      policy.shouldCreateNewNote(
        for: .reopen,
        settings: settings,
        now: closedAt.addingTimeInterval(seconds),
        lastWindowClosedAt: closedAt
      ),
      file: file,
      line: line
    )
  }
}
