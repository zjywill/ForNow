import ForNowCore
import Foundation

public enum PersistenceNoteRepositoryError: Error, Equatable, Sendable {
  case notPrepared
}

public actor PersistenceNoteRepository: NoteRepository {
  public nonisolated let databaseURL: URL
  public nonisolated let backupDirectoryURL: URL

  private let debounce: Duration
  private var store: PersistenceStore?
  private var saver: DebouncedNoteSaver?

  public init(
    databaseURL: URL,
    backupDirectoryURL: URL,
    debounce: Duration = .milliseconds(250)
  ) {
    self.databaseURL = databaseURL
    self.backupDirectoryURL = backupDirectoryURL
    self.debounce = debounce
  }

  public func prepare() async throws {
    guard store == nil else { return }
    let store = try PersistenceStore(
      databaseURL: databaseURL,
      backupDirectoryURL: backupDirectoryURL
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

  public func deleteNote(id: UUID) async throws {
    let (store, saver) = try components()
    await saver.discard(noteID: id)
    try await store.deleteNote(id: id)
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
