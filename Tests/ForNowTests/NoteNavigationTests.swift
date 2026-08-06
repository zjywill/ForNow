import AppKit
import ForNowCore
import XCTest

@testable import ForNow

final class NoteNavigationTests: XCTestCase {
  @MainActor
  func test_UT_NOTE_003_PreviousNextAndNewestBoundaryAreDeterministic() async throws {
    let fixture = makeThreeNoteFixture()
    try await fixture.repository.prepare()
    try await fixture.session.start()

    XCTAssertEqual(fixture.session.currentNoteID, fixture.newest.id)
    try await fixture.session.navigate(.previous)
    XCTAssertEqual(fixture.session.currentNoteID, fixture.middle.id)
    try await fixture.session.navigate(.previous)
    XCTAssertEqual(fixture.session.currentNoteID, fixture.oldest.id)
    try await fixture.session.navigate(.previous)
    XCTAssertEqual(fixture.session.currentNoteID, fixture.oldest.id)

    try await fixture.session.navigate(.next)
    XCTAssertEqual(fixture.session.currentNoteID, fixture.middle.id)
    try await fixture.session.navigate(.next)
    XCTAssertEqual(fixture.session.currentNoteID, fixture.newest.id)
    try await fixture.session.navigate(.next)
    XCTAssertEqual(fixture.session.currentNoteID, fixture.boundaryID)
    XCTAssertEqual(fixture.session.phase, .transient)
    XCTAssertEqual(fixture.session.text, "")

    try await fixture.session.navigate(.next)
    XCTAssertEqual(fixture.session.currentNoteID, fixture.boundaryID)
    try await fixture.session.navigate(.previous)
    XCTAssertEqual(fixture.session.currentNoteID, fixture.newest.id)
  }

  @MainActor
  func test_UT_NOTE_003_OneNoteAndBlankBoundaryDoNotMultiplyRows() async throws {
    let note = makeNote(idSuffix: 41, body: "only", orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [note])
    let blankID = uuid(suffix: 42)
    let session = makeSession(repository: repository, generatedIDs: [blankID])
    try await repository.prepare()
    try await session.start()

    try await session.navigate(.previous)
    XCTAssertEqual(session.currentNoteID, note.id)
    try await session.navigate(.next)
    XCTAssertEqual(session.currentNoteID, blankID)
    try await session.navigate(.next)
    try await session.navigate(.next)
    _ = try await repository.flush()

    XCTAssertEqual(session.currentNoteID, blankID)
    let persistedNoteIDs = try await repository.allNotes().map(\.id)
    XCTAssertEqual(persistedNoteIDs, [note.id])
  }

  @MainActor
  func test_ET_NOTE_003_RapidNavigationFlushesLatestSourceBeforeSwitch() async throws {
    let fixture = makeThreeNoteFixture()
    try await fixture.repository.prepare()
    try await fixture.session.start()
    let editedSource = "edited immediately before navigation 中文"

    fixture.session.editorTextChanged(editedSource, hasMarkedText: false)
    try await fixture.session.navigate(.previous)

    XCTAssertEqual(fixture.session.currentNoteID, fixture.middle.id)
    let persistedNewest = try await fixture.repository.note(id: fixture.newest.id)
    XCTAssertEqual(persistedNewest?.body, editedSource)
  }

  @MainActor
  func test_ET_EDIT_002_NavigationPersistsAndRestoresSelectionAndScroll() async throws {
    let fixture = makeThreeNoteFixture()
    try await fixture.repository.prepare()
    try await fixture.session.start()
    let selection = NSRange(location: 2, length: 3)

    fixture.session.editorViewportChanged(selectionRange: selection, scrollOffset: 96)
    try await fixture.session.navigate(.previous)

    let savedNewest = try await fixture.repository.note(id: fixture.newest.id)
    let persistedNewest = try XCTUnwrap(savedNewest)
    XCTAssertEqual(persistedNewest.selection, NoteSelection(location: 2, length: 3))
    XCTAssertEqual(persistedNewest.scrollOffset, 96)

    try await fixture.session.navigate(.next)
    XCTAssertEqual(fixture.session.currentNoteID, fixture.newest.id)
    XCTAssertEqual(fixture.session.editorSelectionRange, selection)
    XCTAssertEqual(fixture.session.editorScrollOffset, 96)
  }

  @MainActor
  func test_UT_NOTE_004_JumpAndPromoteUseStableIDsAndMonotonicOrder() async throws {
    let fixture = makeThreeNoteFixture()
    try await fixture.repository.prepare()
    try await fixture.session.start()
    try await fixture.session.navigate(.previous)
    try await fixture.session.navigate(.previous)
    XCTAssertEqual(fixture.session.currentNoteID, fixture.oldest.id)

    try await fixture.session.jumpToNewest()
    XCTAssertEqual(fixture.session.currentNoteID, fixture.newest.id)
    try await fixture.session.navigate(.previous)
    let promotedID = try XCTUnwrap(fixture.session.currentNoteID)

    try await fixture.session.promoteCurrent()

    XCTAssertEqual(fixture.session.currentNoteID, promotedID)
    let ordered = try await fixture.repository.allNotes()
    XCTAssertEqual(ordered.first?.id, promotedID)
    XCTAssertEqual(Set(ordered.map(\.orderKey)).count, ordered.count)
  }

  @MainActor
  func test_UIT_NOTE_005A_DeleteAlertIsCancelFirstAndCancelIsDefault() {
    let alert = DeleteConfirmationCoordinator().makeAlert()

    XCTAssertEqual(alert.buttons.map(\.title), ["Cancel", "Delete"])
    XCTAssertEqual(alert.buttons[0].keyEquivalent, "\r")
    XCTAssertTrue(alert.buttons[1].hasDestructiveAction)
    XCTAssertEqual(alert.suppressionButton?.title, "Do not ask again")
  }

  @MainActor
  func test_UIT_NOTE_005A_CancelDeletionLeavesNoteAndSettingsUnchanged() async throws {
    let note = makeNote(idSuffix: 51, body: "keep", orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [note])
    let settingsStore = InMemoryLifecycleSettingsStore(
      settings: LifecycleSettings(createsNewNoteOnLaunch: false)
    )
    let session = makeSession(
      repository: repository,
      generatedIDs: [uuid(suffix: 52)],
      settingsStore: settingsStore
    )
    try await repository.prepare()
    try await session.start()

    let requestOutcome = try await session.requestDeletion()
    XCTAssertEqual(requestOutcome, .confirmationRequired)
    XCTAssertTrue(session.isDeleteConfirmationPending)
    try await session.resolveDeletion(confirm: false, suppressFutureWarning: true)

    XCTAssertEqual(session.currentNoteID, note.id)
    XCTAssertFalse(session.isDeleteConfirmationPending)
    XCTAssertFalse(session.settings.suppressesDeleteWarning)
    let persistedNote = try await repository.note(id: note.id)
    XCTAssertNotNil(persistedNote)
  }

  @MainActor
  func test_UIT_NOTE_005B_ConfirmAndSuppressThenResetWarning() async throws {
    let newest = makeNote(idSuffix: 61, body: "delete first", orderKey: 1)
    let oldest = makeNote(idSuffix: 62, body: "delete without prompt", orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [newest, oldest])
    let settingsStore = InMemoryLifecycleSettingsStore(
      settings: LifecycleSettings(createsNewNoteOnLaunch: false)
    )
    let session = makeSession(
      repository: repository,
      generatedIDs: [uuid(suffix: 63)],
      settingsStore: settingsStore
    )
    try await repository.prepare()
    try await session.start()

    let firstRequestOutcome = try await session.requestDeletion()
    XCTAssertEqual(firstRequestOutcome, .confirmationRequired)
    try await session.resolveDeletion(confirm: true, suppressFutureWarning: true)
    XCTAssertEqual(session.currentNoteID, oldest.id)
    XCTAssertTrue(session.settings.suppressesDeleteWarning)
    let deletedNewest = try await repository.note(id: newest.id)
    XCTAssertNil(deletedNewest)

    let secondRequestOutcome = try await session.requestDeletion()
    XCTAssertEqual(secondRequestOutcome, .deleted)
    XCTAssertEqual(session.phase, .transient)
    let deletedOldest = try await repository.note(id: oldest.id)
    XCTAssertNil(deletedOldest)

    try await session.resetDeleteWarning()
    XCTAssertFalse(session.settings.suppressesDeleteWarning)
    let persistedSettings = await settingsStore.load()
    XCTAssertFalse(persistedSettings.suppressesDeleteWarning)
  }

  @MainActor
  func test_IT_NOTE_005_BlankDeletionNeedsNoConfirmationOrPersistentRow() async throws {
    let repository = InMemoryNoteRepository()
    let firstID = uuid(suffix: 71)
    let replacementID = uuid(suffix: 72)
    let session = makeSession(repository: repository, generatedIDs: [firstID, replacementID])
    try await repository.prepare()
    try await session.start()

    let requestOutcome = try await session.requestDeletion()
    XCTAssertEqual(requestOutcome, .deleted)
    XCTAssertEqual(session.currentNoteID, replacementID)
    let persistedNotes = try await repository.allNotes()
    XCTAssertTrue(persistedNotes.isEmpty)
  }

  @MainActor
  private func makeThreeNoteFixture() -> ThreeNoteFixture {
    let newest = makeNote(idSuffix: 31, body: "newest", orderKey: 2)
    let middle = makeNote(idSuffix: 32, body: "middle", orderKey: 1)
    let oldest = makeNote(idSuffix: 33, body: "oldest", orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [oldest, newest, middle])
    let boundaryID = uuid(suffix: 34)
    let session = makeSession(repository: repository, generatedIDs: [boundaryID])
    return ThreeNoteFixture(
      repository: repository,
      session: session,
      newest: newest,
      middle: middle,
      oldest: oldest,
      boundaryID: boundaryID
    )
  }

  @MainActor
  private func makeSession(
    repository: InMemoryNoteRepository,
    generatedIDs: [UUID],
    settingsStore: InMemoryLifecycleSettingsStore = InMemoryLifecycleSettingsStore(
      settings: LifecycleSettings(createsNewNoteOnLaunch: false)
    )
  ) -> NoteSessionModel {
    NoteSessionModel(
      repository: repository,
      clock: FixedWallClock(Date(timeIntervalSince1970: 100)),
      uuidGenerator: SequenceUUIDGenerator(values: generatedIDs),
      settingsStore: settingsStore
    )
  }

  private func makeNote(idSuffix: Int, body: String, orderKey: Int64) -> Note {
    Note(
      id: uuid(suffix: idSuffix),
      body: body,
      createdAt: Date(timeIntervalSince1970: Double(orderKey)),
      modifiedAt: Date(timeIntervalSince1970: 100),
      orderKey: orderKey
    )
  }

  private func uuid(suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
  }
}

@MainActor
private struct ThreeNoteFixture {
  let repository: InMemoryNoteRepository
  let session: NoteSessionModel
  let newest: Note
  let middle: Note
  let oldest: Note
  let boundaryID: UUID
}
