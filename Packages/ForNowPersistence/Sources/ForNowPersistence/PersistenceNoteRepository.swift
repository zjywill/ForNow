import ForNowCore
import Foundation

public enum PersistenceNoteRepositoryError: Error, Equatable, Sendable {
  case notPrepared
}

public actor PersistenceNoteRepository: NoteRepository {
  public nonisolated let databaseURL: URL
  public nonisolated let backupDirectoryURL: URL

  private let debounce: Duration
  private let faultInjector: PersistenceFaultInjector
  private var store: PersistenceStore?
  private var saver: DebouncedNoteSaver?

  public init(
    databaseURL: URL,
    backupDirectoryURL: URL,
    debounce: Duration = .milliseconds(250),
    faultInjector: PersistenceFaultInjector = .none
  ) {
    self.databaseURL = databaseURL
    self.backupDirectoryURL = backupDirectoryURL
    self.debounce = debounce
    self.faultInjector = faultInjector
  }

  public func prepare() async throws {
    guard store == nil else { return }
    let store = try PersistenceStore(
      databaseURL: databaseURL,
      backupDirectoryURL: backupDirectoryURL,
      faultInjector: faultInjector
    )
    try await store.verifyIntegrity()
    self.store = store
    saver = DebouncedNoteSaver(store: store, debounce: debounce)
  }

  public func schedule(_ draft: NoteDraft) async throws {
    let (_, saver) = try components()
    await saver.schedule(draft)
  }

  public func discardPending(noteID: UUID) async {
    guard let saver else { return }
    await saver.discard(noteID: noteID)
  }

  @discardableResult
  public func flush() async throws -> [Note] {
    let (store, saver) = try components()
    let notes = try await saver.flushAll()
    try await store.checkpoint()
    return notes
  }

  public func note(id: UUID) async throws -> Note? {
    let (store, _) = try components()
    return try await store.note(id: id)
  }

  public func allNotes() async throws -> [Note] {
    let (store, _) = try components()
    return try await store.allNotes()
  }

  public func search(_ query: String) async throws -> [Note] {
    let (store, _) = try components()
    return try await store.search(query)
  }

  public func searchPage(
    _ query: String,
    limit: Int,
    offset: Int
  ) async throws -> NoteSearchPage {
    let (store, _) = try components()
    return try await store.searchPage(query, limit: limit, offset: offset)
  }

  @discardableResult
  public func promoteNote(id: UUID, at date: Date) async throws -> Note {
    let (store, _) = try components()
    return try await store.promoteNote(id: id, at: date)
  }

  @discardableResult
  public func promoteNote(id: UUID, at date: Date, expiresAt: Date?) async throws -> Note {
    let (store, _) = try components()
    return try await store.promoteNote(id: id, at: date, expiresAt: expiresAt)
  }

  public func deleteNote(id: UUID) async throws {
    let (store, saver) = try components()
    await saver.discard(noteID: id)
    try await store.deleteNote(id: id)
  }

  @discardableResult
  public func applyExpirationPolicy(
    _ policy: NoteExpirationPolicy,
    effectiveAt date: Date
  ) async throws -> [Note] {
    let (store, saver) = try components()
    _ = try await saver.flushAll()
    return try await store.applyExpirationPolicy(policy, effectiveAt: date)
  }

  @discardableResult
  public func deleteExpiredNotes(at date: Date) async throws -> ExpirationDeletionReceipt {
    let (store, saver) = try components()
    _ = try await saver.flushAll()
    return try await store.deleteExpiredNotes(at: date)
  }

  public func previewBulkDeletion(before cutoff: Date) async throws -> BulkDeletionPreview {
    let (store, _) = try components()
    return try await store.previewBulkDeletion(before: cutoff)
  }

  @discardableResult
  public func confirmBulkDeletion(
    _ preview: BulkDeletionPreview,
    backupAt date: Date
  ) async throws -> BulkDeletionReceipt {
    let (store, saver) = try components()
    _ = try await saver.flushAll()
    let descriptor = try await store.createBackup(at: date)
    let deletedIDs = try await store.deleteNotes(matching: preview)
    return BulkDeletionReceipt(
      preview: preview,
      deletedNoteIDs: deletedIDs,
      safetyBackup: SafetyBackupReceipt(
        createdAt: descriptor.manifest.createdAt,
        noteCount: descriptor.manifest.noteCount
      )
    )
  }

  public func currentTimer() async throws -> NoteTimer? {
    let (store, _) = try components()
    return try await store.currentTimer()
  }

  public func saveCurrentTimer(_ timer: NoteTimer) async throws {
    let (store, _) = try components()
    try await store.saveCurrentTimer(timer)
  }

  public func deleteTimer(id: TimerID) async throws {
    let (store, _) = try components()
    try await store.deleteTimer(id: id)
  }

  public func shutdown() async throws {
    guard let store, let saver else { return }
    _ = try await saver.flushAll()
    try await store.checkpoint()
    try await store.close()
    self.store = nil
    self.saver = nil
  }

  private func components() throws -> (PersistenceStore, DebouncedNoteSaver) {
    guard let store, let saver else {
      throw PersistenceNoteRepositoryError.notPrepared
    }
    return (store, saver)
  }
}
