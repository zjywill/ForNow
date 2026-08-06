import ForNowCore
import ForNowModes
import XCTest

@testable import ForNow

final class NoteRetentionTests: XCTestCase {
  func test_UT_NOTE_006A_TodayExpiresAtStartOfNextLocalDay() throws {
    let calendar = utcCalendar()
    let reference = try date(2026, 8, 6, 21, 30, calendar: calendar)
    let expected = try date(2026, 8, 7, 0, 0, calendar: calendar)

    XCTAssertEqual(
      NoteExpirationPolicy(choice: .today, calendar: calendar)
        .expirationDate(referenceDate: reference),
      expected
    )
  }

  func test_UT_NOTE_006B_OneWeekUsesSevenLocalCalendarDaysAcrossDST() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let reference = try date(2026, 3, 7, 12, 15, calendar: calendar)
    let expiration = try XCTUnwrap(
      NoteExpirationPolicy(choice: .oneWeek, calendar: calendar)
        .expirationDate(referenceDate: reference)
    )
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: expiration
    )

    XCTAssertEqual(components.year, 2026)
    XCTAssertEqual(components.month, 3)
    XCTAssertEqual(components.day, 14)
    XCTAssertEqual(components.hour, 12)
    XCTAssertEqual(components.minute, 15)
  }

  func test_UT_NOTE_006C_OneMonthClampsToLastValidCalendarDay() throws {
    let calendar = utcCalendar()
    let reference = try date(2024, 1, 31, 12, 0, calendar: calendar)
    let expected = try date(2024, 2, 29, 12, 0, calendar: calendar)

    XCTAssertEqual(
      NoteExpirationPolicy(choice: .oneMonth, calendar: calendar)
        .expirationDate(referenceDate: reference),
      expected
    )
  }

  func test_UT_NOTE_006D_OneYearClampsLeapDay() throws {
    let calendar = utcCalendar()
    let reference = try date(2024, 2, 29, 9, 45, calendar: calendar)
    let expected = try date(2025, 2, 28, 9, 45, calendar: calendar)

    XCTAssertEqual(
      NoteExpirationPolicy(choice: .oneYear, calendar: calendar)
        .expirationDate(referenceDate: reference),
      expected
    )
  }

  func test_UT_NOTE_006E_NeverIsNilAndVersionOneSettingsMigrate() async throws {
    let reference = Date(timeIntervalSince1970: 1_000)
    XCTAssertNil(
      NoteExpirationPolicy(choice: .never, calendar: utcCalendar())
        .expirationDate(referenceDate: reference)
    )

    let suiteName = "ForNowTests.RetentionMigration.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(
      Data(
        #"{"version":1,"createsNewNoteOnLaunch":false,"reopenNewNotePolicy":"never","showsNoteCount":true,"suppressesDeleteWarning":false}"#
          .utf8
      ),
      forKey: "app.fornow.lifecycle.settings.v1"
    )

    let migrated = await UserDefaultsLifecycleSettingsStore(suiteName: suiteName).load()
    XCTAssertEqual(migrated.version, LifecycleSettings.currentVersion)
    XCTAssertEqual(migrated.noteExpirationChoice, .never)
    XCTAssertFalse(migrated.createsNewNoteOnLaunch)
    XCTAssertTrue(migrated.showsNoteCount)
  }

  @MainActor
  func test_IT_NOTE_006_LaunchClockChangesAndRepeatedRunsAreIdempotent() async throws {
    let expired = makeNote(suffix: 1, modifiedAt: 10, expiresAt: 99, orderKey: 0)
    let survivor = makeNote(suffix: 2, modifiedAt: 20, expiresAt: 200, orderKey: 1)
    let repository = InMemoryNoteRepository(notes: [expired, survivor])
    try await repository.prepare()
    try await repository.saveCurrentTimer(
      NoteTimer(
        id: UUID(),
        noteID: survivor.id,
        kind: .stopwatch,
        phase: .primary,
        state: .paused,
        accumulated: .seconds(10)
      )
    )
    let clock = RetentionMutableWallClock(Date(timeIntervalSince1970: 100))
    let environment = AppEnvironment.test(
      repository: repository,
      clock: clock,
      lifecycleSettings: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: false)
      )
    )

    try await environment.start()
    let expiredAfterLaunch = try await repository.note(id: expired.id)
    let timerAfterLaunch = try await repository.currentTimer()
    XCTAssertNil(expiredAfterLaunch)
    XCTAssertEqual(timerAfterLaunch?.noteID, survivor.id)
    XCTAssertEqual(environment.timerModel.snapshot?.timer.noteID, survivor.id)
    XCTAssertEqual(environment.noteSession.currentNoteID, survivor.id)
    XCTAssertEqual(environment.lastExpirationReceipt?.deletedNoteIDs, [expired.id])
    environment.autoPasteModel.startSession(
      destinationNoteID: survivor.id,
      destinationName: "Expiring destination",
      command: AutoPasteCommand()
    )
    XCTAssertTrue(environment.autoPasteModel.isActive)

    let repeated = try await environment.processExpiredNotes()
    XCTAssertEqual(repeated?.deletedNoteIDs, [])
    clock.set(Date(timeIntervalSince1970: 50))
    await environment.synchronizeWallClock()
    let survivorAfterRollback = try await repository.note(id: survivor.id)
    XCTAssertNotNil(survivorAfterRollback)

    clock.set(Date(timeIntervalSince1970: 200))
    await environment.synchronizeWallClock()
    let survivorAfterExpiration = try await repository.note(id: survivor.id)
    XCTAssertNil(survivorAfterExpiration)
    XCTAssertEqual(environment.noteSession.noteCount, 0)
    XCTAssertEqual(environment.lastExpirationReceipt?.deletedNoteIDs, [survivor.id])
    XCTAssertNil(environment.timerModel.snapshot)
    XCTAssertFalse(environment.autoPasteModel.isActive)
    XCTAssertEqual(environment.autoPasteModel.lastStopReason, .destinationDeleted)

    await environment.synchronizeWallClock()
    XCTAssertEqual(environment.lastExpirationReceipt?.deletedNoteIDs, [])
    try await environment.shutdown()
  }

  @MainActor
  func test_IT_NOTE_006_MetadataPreservesDatesWhileSourceAndPromotionRefreshThem()
    async throws
  {
    let calendar = utcCalendar()
    let original = makeNote(suffix: 3, modifiedAt: 100, expiresAt: 500, orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [original])
    let clock = RetentionMutableWallClock(Date(timeIntervalSince1970: 200))
    let session = NoteSessionModel(
      repository: repository,
      clock: clock,
      uuidGenerator: SequenceUUIDGenerator(values: [UUID()]),
      settingsStore: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(
          createsNewNoteOnLaunch: false,
          noteExpirationChoice: .oneWeek
        )
      ),
      expirationCalendar: calendar
    )
    try await repository.prepare()
    try await session.start()

    session.editorViewportChanged(selectionRange: NSRange(location: 2, length: 1), scrollOffset: 7)
    try await session.prepareForDeparture()
    _ = try await repository.flush()
    let metadataOnlyValue = try await repository.note(id: original.id)
    let metadataOnly = try XCTUnwrap(metadataOnlyValue)
    XCTAssertEqual(metadataOnly.modifiedAt, original.modifiedAt)
    XCTAssertEqual(metadataOnly.expiresAt, original.expiresAt)

    clock.set(Date(timeIntervalSince1970: 300))
    try await session.applyEditorText("note-3 edited", hasMarkedText: false)
    _ = try await repository.flush()
    let editedValue = try await repository.note(id: original.id)
    let edited = try XCTUnwrap(editedValue)
    XCTAssertEqual(edited.modifiedAt, clock.now())
    XCTAssertEqual(
      edited.expiresAt,
      NoteExpirationPolicy(choice: .oneWeek, calendar: calendar)
        .expirationDate(referenceDate: clock.now())
    )

    clock.set(Date(timeIntervalSince1970: 400))
    try await session.promoteCurrent()
    let promotedValue = try await repository.note(id: original.id)
    let promoted = try XCTUnwrap(promotedValue)
    XCTAssertEqual(promoted.modifiedAt, clock.now())
    XCTAssertEqual(
      promoted.expiresAt,
      NoteExpirationPolicy(choice: .oneWeek, calendar: calendar)
        .expirationDate(referenceDate: clock.now())
    )
  }

  @MainActor
  func test_IT_NOTE_006_PolicyChangeGivesExistingNotesANewGracePeriod() async throws {
    let calendar = utcCalendar()
    let note = makeNote(suffix: 4, modifiedAt: 10, orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [note])
    let clock = RetentionMutableWallClock(Date(timeIntervalSince1970: 100))
    let session = NoteSessionModel(
      repository: repository,
      clock: clock,
      uuidGenerator: SequenceUUIDGenerator(values: [UUID()]),
      settingsStore: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: false)
      ),
      expirationCalendar: calendar
    )
    try await repository.prepare()
    try await session.start()

    var settings = session.settings
    settings.noteExpirationChoice = .oneWeek
    try await session.updateSettings(settings)
    let finiteValue = try await repository.note(id: note.id)
    let finite = try XCTUnwrap(finiteValue)
    XCTAssertEqual(finite.modifiedAt, note.modifiedAt)
    XCTAssertEqual(
      finite.expiresAt,
      NoteExpirationPolicy(choice: .oneWeek, calendar: calendar)
        .expirationDate(referenceDate: clock.now())
    )

    settings.noteExpirationChoice = .never
    try await session.updateSettings(settings)
    let never = try await repository.note(id: note.id)
    XCTAssertNil(never?.expiresAt)
    XCTAssertEqual(never?.modifiedAt, note.modifiedAt)
  }

  func test_UT_NOTE_010A_PreviewUsesStrictEarlierThanPredicate() async throws {
    let cutoff = Date(timeIntervalSince1970: 100)
    let old = makeNote(suffix: 11, modifiedAt: 99, orderKey: 0)
    let equal = makeNote(suffix: 12, modifiedAt: 100, orderKey: 1)
    let new = makeNote(suffix: 13, modifiedAt: 101, orderKey: 2)
    let repository = InMemoryNoteRepository(notes: [old, equal, new])
    try await repository.prepare()

    let preview = try await repository.previewBulkDeletion(before: cutoff)
    XCTAssertEqual(preview.noteIDs, [old.id])
    XCTAssertEqual(preview.count, 1)
  }

  func test_UT_NOTE_010B_ExactCutoffRemainsExcludedAtConfirmation() async throws {
    let cutoff = Date(timeIntervalSince1970: 100)
    let equal = makeNote(suffix: 14, modifiedAt: 100, orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [equal])
    try await repository.prepare()

    let preview = BulkDeletionPreview(cutoff: cutoff, noteIDs: [equal.id])
    let receipt = try await repository.confirmBulkDeletion(preview, backupAt: cutoff)
    XCTAssertEqual(receipt.deletedNoteIDs, [])
    XCTAssertEqual(receipt.skippedNoteIDs, [equal.id])
    let equalAfterConfirmation = try await repository.note(id: equal.id)
    XCTAssertNotNil(equalAfterConfirmation)
  }

  func test_UT_NOTE_010C_FrozenPreviewNeverAddsLaterMatchingNotes() async throws {
    let cutoff = Date(timeIntervalSince1970: 100)
    let previewed = makeNote(suffix: 15, modifiedAt: 10, orderKey: 0)
    let later = makeNote(suffix: 16, modifiedAt: 20, orderKey: 1)
    let repository = InMemoryNoteRepository(notes: [previewed])
    try await repository.prepare()
    let preview = try await repository.previewBulkDeletion(before: cutoff)
    try await repository.schedule(draft(from: later))
    _ = try await repository.flush()

    let receipt = try await repository.confirmBulkDeletion(preview, backupAt: cutoff)
    XCTAssertEqual(receipt.deletedNoteIDs, [previewed.id])
    let laterAfterConfirmation = try await repository.note(id: later.id)
    XCTAssertNotNil(laterAfterConfirmation)
    XCTAssertEqual(receipt.safetyBackup.noteCount, 2)
  }

  func test_UT_NOTE_010D_ConfirmationRevalidatesEditedPreviewMembers() async throws {
    let cutoff = Date(timeIntervalSince1970: 100)
    let note = makeNote(suffix: 17, modifiedAt: 10, orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [note])
    try await repository.prepare()
    let preview = try await repository.previewBulkDeletion(before: cutoff)
    var edited = draft(from: note)
    edited.modifiedAt = cutoff
    try await repository.schedule(edited)

    let receipt = try await repository.confirmBulkDeletion(preview, backupAt: cutoff)
    XCTAssertEqual(receipt.deletedNoteIDs, [])
    XCTAssertEqual(receipt.skippedNoteIDs, [note.id])
    let revalidatedNote = try await repository.note(id: note.id)
    XCTAssertEqual(revalidatedNote?.modifiedAt, cutoff)
  }

  @MainActor
  func test_UT_NOTE_010E_CancellationLeavesEveryNoteAndBackupCountUnchanged() async throws {
    let note = makeNote(suffix: 18, modifiedAt: 10, orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [note])
    let environment = AppEnvironment.test(
      repository: repository,
      clock: FixedWallClock(Date(timeIntervalSince1970: 100)),
      lifecycleSettings: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: false)
      )
    )
    try await environment.start()
    _ = try await environment.previewBulkDeletion(before: Date(timeIntervalSince1970: 50))

    environment.cancelBulkDeletion()
    XCTAssertNil(environment.bulkDeletionPreview)
    let notesAfterCancellation = try await repository.allNotes()
    let backupCountAfterCancellation = await repository.safetyBackupCount()
    XCTAssertEqual(notesAfterCancellation, [note])
    XCTAssertEqual(backupCountAfterCancellation, 0)
    try await environment.shutdown()
  }

  func test_UT_NOTE_010F_BackupFailureDeletesNothing() async throws {
    let note = makeNote(suffix: 19, modifiedAt: 10, orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [note], failsSafetyBackup: true)
    try await repository.prepare()
    let preview = try await repository.previewBulkDeletion(before: Date(timeIntervalSince1970: 50))

    do {
      _ = try await repository.confirmBulkDeletion(
        preview,
        backupAt: Date(timeIntervalSince1970: 100)
      )
      XCTFail("A failed safety backup must stop bulk deletion")
    } catch {
      XCTAssertEqual(error as? InMemoryNoteRepositoryError, .safetyBackupFailed)
    }
    let notesAfterFailure = try await repository.allNotes()
    let backupCountAfterFailure = await repository.safetyBackupCount()
    XCTAssertEqual(notesAfterFailure, [note])
    XCTAssertEqual(backupCountAfterFailure, 0)
  }

  @MainActor
  func test_IT_NOTE_010_EnvironmentReconcilesCurrentNoteAutoPasteAndTimer() async throws {
    let deleting = makeNote(suffix: 20, modifiedAt: 10, orderKey: 1)
    let survivor = makeNote(suffix: 21, modifiedAt: 60, orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [deleting, survivor])
    try await repository.prepare()
    try await repository.saveCurrentTimer(
      NoteTimer(
        id: UUID(),
        noteID: deleting.id,
        kind: .stopwatch,
        phase: .primary,
        state: .paused,
        accumulated: .seconds(5)
      )
    )
    let environment = AppEnvironment.test(
      repository: repository,
      clock: FixedWallClock(Date(timeIntervalSince1970: 100)),
      lifecycleSettings: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: false)
      )
    )
    try await environment.start()
    XCTAssertEqual(environment.noteSession.currentNoteID, deleting.id)
    environment.autoPasteModel.startSession(
      destinationNoteID: deleting.id,
      destinationName: "Deleting destination",
      command: AutoPasteCommand()
    )
    _ = try await environment.previewBulkDeletion(before: Date(timeIntervalSince1970: 50))

    let receipt = try await environment.confirmBulkDeletion()
    XCTAssertEqual(receipt?.deletedNoteIDs, [deleting.id])
    XCTAssertEqual(environment.noteSession.currentNoteID, survivor.id)
    XCTAssertEqual(environment.noteSession.noteCount, 1)
    XCTAssertFalse(environment.autoPasteModel.isActive)
    XCTAssertEqual(environment.autoPasteModel.lastStopReason, .destinationDeleted)
    XCTAssertNil(environment.timerModel.snapshot)
    let safetyBackupCount = await repository.safetyBackupCount()
    XCTAssertEqual(safetyBackupCount, 1)
    try await environment.shutdown()
  }

  @MainActor
  func test_UIT_NOTE_010_AlertShowsCountIrreversibleCopyAndCancelFirst() {
    let preview = BulkDeletionPreview(
      cutoff: Date(timeIntervalSince1970: 100),
      noteIDs: [UUID(), UUID()]
    )
    let alert = BulkDeletionConfirmationCoordinator().makeAlert(for: preview)

    XCTAssertEqual(alert.messageText, "Permanently delete 2 notes?")
    XCTAssertEqual(
      alert.informativeText,
      "This action cannot be undone. A safety backup will be created before deletion."
    )
    XCTAssertEqual(alert.buttons.map(\.title), ["Cancel", "Delete 2"])
    XCTAssertEqual(alert.buttons[0].keyEquivalent, "\r")
    XCTAssertTrue(alert.buttons[1].hasDestructiveAction)
  }

  private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int,
    calendar: Calendar
  ) throws -> Date {
    try XCTUnwrap(
      calendar.date(
        from: DateComponents(
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute
        )
      )
    )
  }

  private func makeNote(
    suffix: Int,
    modifiedAt: TimeInterval,
    expiresAt: TimeInterval? = nil,
    orderKey: Int64
  ) -> Note {
    Note(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!,
      body: "note-\(suffix)",
      createdAt: Date(timeIntervalSince1970: modifiedAt - 1),
      modifiedAt: Date(timeIntervalSince1970: modifiedAt),
      orderKey: orderKey,
      expiresAt: expiresAt.map(Date.init(timeIntervalSince1970:))
    )
  }

  private func draft(from note: Note) -> NoteDraft {
    NoteDraft(
      id: note.id,
      body: note.body,
      createdAt: note.createdAt,
      modifiedAt: note.modifiedAt,
      expiresAt: note.expiresAt,
      slotIndex: note.slotIndex,
      selection: note.selection,
      scrollOffset: note.scrollOffset
    )
  }
}

private final class RetentionMutableWallClock: WallClock, @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) {
    self.date = date
  }

  func now() -> Date {
    lock.withLock { date }
  }

  func set(_ date: Date) {
    lock.withLock { self.date = date }
  }
}
