import ForNowCore
import Foundation

public struct PendingDraftFailure: Equatable, Sendable {
  public let noteID: UUID
  public let message: String

  public init(noteID: UUID, message: String) {
    self.noteID = noteID
    self.message = message
  }
}

public actor DebouncedNoteSaver {
  private let store: PersistenceStore
  private let debounce: Duration
  private var pendingDrafts: [UUID: NoteDraft] = [:]
  private var generations: [UUID: UInt64] = [:]
  private var saveTasks: [UUID: Task<Void, Never>] = [:]
  private var failures: [UUID: PendingDraftFailure] = [:]

  public init(store: PersistenceStore, debounce: Duration = .milliseconds(250)) {
    self.store = store
    self.debounce = debounce
  }

  public func schedule(_ draft: NoteDraft) {
    pendingDrafts[draft.id] = draft
    let generation = (generations[draft.id] ?? 0) &+ 1
    generations[draft.id] = generation
    saveTasks[draft.id]?.cancel()
    saveTasks[draft.id] = Task { [weak self] in
      guard let self else { return }
      do {
        try await Task.sleep(for: debounce)
      } catch {
        return
      }
      await self.commitIfCurrent(noteID: draft.id, generation: generation)
    }
  }

  @discardableResult
  public func flush(noteID: UUID) async throws -> Note {
    saveTasks[noteID]?.cancel()
    saveTasks[noteID] = nil
    guard let draft = pendingDrafts[noteID] else {
      if let saved = try await store.note(id: noteID) {
        return saved
      }
      throw PersistenceStoreError.noteNotFound(noteID)
    }
    return try await commit(draft, expectedGeneration: generations[noteID])
  }

  public func flushAll() async throws -> [Note] {
    let ids = pendingDrafts.keys.sorted { $0.uuidString < $1.uuidString }
    var notes: [Note] = []
    for id in ids {
      notes.append(try await flush(noteID: id))
    }
    return notes
  }

  public func exportableDraft(noteID: UUID) -> NoteDraft? {
    pendingDrafts[noteID]
  }

  public func exportableDrafts() -> [NoteDraft] {
    pendingDrafts.values.sorted { $0.id.uuidString < $1.id.uuidString }
  }

  public func lastFailure(noteID: UUID) -> PendingDraftFailure? {
    failures[noteID]
  }

  public func cancel(noteID: UUID) {
    saveTasks[noteID]?.cancel()
    saveTasks[noteID] = nil
  }

  public func discard(noteID: UUID) {
    cancel(noteID: noteID)
    pendingDrafts[noteID] = nil
    generations[noteID] = nil
    failures[noteID] = nil
  }

  private func commitIfCurrent(noteID: UUID, generation: UInt64) async {
    guard generations[noteID] == generation, let draft = pendingDrafts[noteID] else { return }
    do {
      _ = try await commit(draft, expectedGeneration: generation)
    } catch {
      failures[noteID] = PendingDraftFailure(noteID: noteID, message: String(describing: error))
    }
  }

  private func commit(_ draft: NoteDraft, expectedGeneration: UInt64?) async throws -> Note {
    do {
      let note = try await store.saveDraft(draft)
      if expectedGeneration == nil || generations[draft.id] == expectedGeneration {
        pendingDrafts[draft.id] = nil
        failures[draft.id] = nil
        saveTasks[draft.id] = nil
      }
      return note
    } catch {
      failures[draft.id] = PendingDraftFailure(
        noteID: draft.id,
        message: String(describing: error)
      )
      throw error
    }
  }
}
