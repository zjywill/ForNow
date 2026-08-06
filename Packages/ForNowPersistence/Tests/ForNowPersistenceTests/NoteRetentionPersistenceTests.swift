import ForNowCore
import Foundation
import Testing

@testable import ForNowPersistence

@Suite(.serialized)
struct NoteRetentionPersistenceTests {
  @Test("IT-NOTE-006: explicit expiration is transactional and idempotent")
  func expirationDeletesNoteFTSAndLinkedTimerExactlyOnce() async throws {
    try await withRetentionWorkspace { workspace in
      let repository = workspace.makeRepository()
      try await repository.prepare()
      let expiredID = UUID()
      let boundaryID = UUID()
      let survivorID = UUID()
      try await repository.schedule(
        draft(id: expiredID, body: "expired searchable", modifiedAt: 10, expiresAt: 99)
      )
      try await repository.schedule(
        draft(id: boundaryID, body: "boundary searchable", modifiedAt: 20, expiresAt: 100)
      )
      try await repository.schedule(
        draft(id: survivorID, body: "survivor searchable", modifiedAt: 30, expiresAt: 101)
      )
      _ = try await repository.flush()
      try await repository.saveCurrentTimer(
        NoteTimer(
          id: UUID(),
          noteID: boundaryID,
          kind: .countdown,
          phase: .primary,
          state: .running,
          startedAt: Date(timeIntervalSince1970: 90),
          workDuration: .seconds(60)
        )
      )

      let first = try await repository.deleteExpiredNotes(at: Date(timeIntervalSince1970: 100))
      #expect(Set(first.deletedNoteIDs) == Set([expiredID, boundaryID]))
      #expect(try await repository.note(id: expiredID) == nil)
      #expect(try await repository.note(id: boundaryID) == nil)
      #expect(try await repository.note(id: survivorID) != nil)
      #expect(try await repository.search("searchable").map(\.id) == [survivorID])
      #expect(try await repository.currentTimer() == nil)

      let repeated = try await repository.deleteExpiredNotes(
        at: Date(timeIntervalSince1970: 100)
      )
      #expect(repeated.deletedNoteIDs.isEmpty)
      let later = try await repository.deleteExpiredNotes(
        at: Date(timeIntervalSince1970: 1_000)
      )
      #expect(later.deletedNoteIDs == [survivorID])
      let finalRepeat = try await repository.deleteExpiredNotes(
        at: Date(timeIntervalSince1970: 1_000)
      )
      #expect(finalRepeat.deletedNoteIDs.isEmpty)
      try await repository.shutdown()

      let store = try workspace.makeStore()
      try await store.verifyIntegrity()
      try await store.close()
    }
  }

  @Test("IT-NOTE-010: backup precedes strict transactional bulk deletion and restores")
  func bulkDeletionCreatesValidatedRecoverableBackup() async throws {
    try await withRetentionWorkspace { workspace in
      let repository = workspace.makeRepository()
      try await repository.prepare()
      let oldID = UUID()
      let equalID = UUID()
      let newID = UUID()
      try await repository.schedule(draft(id: oldID, body: "bulk old", modifiedAt: 10))
      try await repository.schedule(draft(id: equalID, body: "bulk equal", modifiedAt: 100))
      try await repository.schedule(draft(id: newID, body: "bulk new", modifiedAt: 101))
      _ = try await repository.flush()
      try await repository.saveCurrentTimer(
        NoteTimer(
          id: UUID(),
          noteID: oldID,
          kind: .stopwatch,
          phase: .primary,
          state: .paused,
          accumulated: .seconds(7)
        )
      )

      let cutoff = Date(timeIntervalSince1970: 100)
      let preview = try await repository.previewBulkDeletion(before: cutoff)
      #expect(preview.noteIDs == [oldID])
      let receipt = try await repository.confirmBulkDeletion(
        preview,
        backupAt: Date(timeIntervalSince1970: 200)
      )
      #expect(receipt.deletedNoteIDs == [oldID])
      #expect(receipt.skippedNoteIDs.isEmpty)
      #expect(receipt.safetyBackup.noteCount == 3)
      #expect(try await repository.note(id: oldID) == nil)
      #expect(try await repository.note(id: equalID) != nil)
      #expect(try await repository.note(id: newID) != nil)
      #expect(try await repository.search("bulk old").isEmpty)
      #expect(try await repository.currentTimer() == nil)
      try await repository.shutdown()

      let store = try workspace.makeStore()
      let backups = try await store.availableBackups()
      #expect(backups.count == 1)
      let backup = try #require(backups.first)
      let validated = try await store.validateBackup(manifestURL: backup.manifestURL)
      #expect(validated.manifest.noteCount == 3)
      _ = try await store.restoreBackup(manifestURL: backup.manifestURL)
      #expect(try await store.note(id: oldID)?.body == "bulk old")
      #expect(try await store.note(id: equalID)?.body == "bulk equal")
      #expect(try await store.note(id: newID)?.body == "bulk new")
      #expect(try await store.currentTimer()?.noteID == oldID)
      try await store.verifyIntegrity()
      try await store.close()
    }
  }

  @Test("IT-NOTE-010: backup publication failure performs no deletion")
  func backupFailureLeavesNotesAndFTSUnchanged() async throws {
    try await withRetentionWorkspace { workspace in
      let repository = workspace.makeRepository(
        injector: PersistenceFaultInjector { point in
          if case .afterBackupCopyBeforeFinalize = point {
            throw RetentionPersistenceTestError.injectedBackupFailure
          }
        }
      )
      try await repository.prepare()
      let noteID = UUID()
      try await repository.schedule(draft(id: noteID, body: "must survive", modifiedAt: 10))
      _ = try await repository.flush()
      let preview = try await repository.previewBulkDeletion(
        before: Date(timeIntervalSince1970: 50)
      )

      await #expect(throws: RetentionPersistenceTestError.injectedBackupFailure) {
        _ = try await repository.confirmBulkDeletion(
          preview,
          backupAt: Date(timeIntervalSince1970: 100)
        )
      }
      #expect(try await repository.note(id: noteID)?.body == "must survive")
      #expect(try await repository.search("must survive").map(\.id) == [noteID])
      let backupFiles = try FileManager.default.contentsOfDirectory(
        at: workspace.backupDirectoryURL,
        includingPropertiesForKeys: nil
      )
      #expect(backupFiles.isEmpty)
      try await repository.shutdown()

      let store = try workspace.makeStore()
      try await store.verifyIntegrity()
      try await store.close()
    }
  }

  private func draft(
    id: UUID,
    body: String,
    modifiedAt: TimeInterval,
    expiresAt: TimeInterval? = nil
  ) -> NoteDraft {
    NoteDraft(
      id: id,
      body: body,
      createdAt: Date(timeIntervalSince1970: modifiedAt - 1),
      modifiedAt: Date(timeIntervalSince1970: modifiedAt),
      expiresAt: expiresAt.map(Date.init(timeIntervalSince1970:))
    )
  }
}

private enum RetentionPersistenceTestError: Error {
  case injectedBackupFailure
}

private struct RetentionTestWorkspace {
  let rootURL: URL
  let databaseURL: URL
  let backupDirectoryURL: URL

  init() throws {
    rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("ForNowRetentionPersistenceTests-\(UUID().uuidString)")
    databaseURL = rootURL.appendingPathComponent("notes.sqlite")
    backupDirectoryURL = rootURL.appendingPathComponent("Backups", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
  }

  func makeRepository(
    injector: PersistenceFaultInjector = .none
  ) -> PersistenceNoteRepository {
    PersistenceNoteRepository(
      databaseURL: databaseURL,
      backupDirectoryURL: backupDirectoryURL,
      debounce: .zero,
      faultInjector: injector
    )
  }

  func makeStore() throws -> PersistenceStore {
    try PersistenceStore(
      databaseURL: databaseURL,
      backupDirectoryURL: backupDirectoryURL
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

private func withRetentionWorkspace(
  _ body: (RetentionTestWorkspace) async throws -> Void
) async throws {
  let workspace = try RetentionTestWorkspace()
  do {
    try await body(workspace)
    workspace.remove()
  } catch {
    workspace.remove()
    throw error
  }
}
