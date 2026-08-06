import Foundation

public protocol WallClock: Sendable {
  func now() -> Date
}

public struct SystemWallClock: WallClock {
  public init() {}

  public func now() -> Date {
    Date()
  }
}

public struct FixedWallClock: WallClock {
  public let date: Date

  public init(_ date: Date) {
    self.date = date
  }

  public func now() -> Date {
    date
  }
}

public protocol UUIDGenerating: Sendable {
  func next() async -> UUID
}

public struct SystemUUIDGenerator: UUIDGenerating {
  public init() {}

  public func next() async -> UUID {
    UUID()
  }
}

public actor SequenceUUIDGenerator: UUIDGenerating {
  private var values: [UUID]
  private var index = 0

  public init(values: [UUID]) {
    precondition(!values.isEmpty, "SequenceUUIDGenerator requires at least one value")
    self.values = values
  }

  public func next() -> UUID {
    let value = values[min(index, values.count - 1)]
    index += 1
    return value
  }
}

public protocol NoteRepository: Sendable {
  func prepare() async throws
  func schedule(_ draft: NoteDraft) async throws
  func discardPending(noteID: UUID) async
  @discardableResult func flush() async throws -> [Note]
  func note(id: UUID) async throws -> Note?
  func allNotes() async throws -> [Note]
  func search(_ query: String) async throws -> [Note]
  func searchPage(_ query: String, limit: Int, offset: Int) async throws -> NoteSearchPage
  @discardableResult func promoteNote(id: UUID, at date: Date) async throws -> Note
  @discardableResult func promoteNote(
    id: UUID,
    at date: Date,
    expiresAt: Date?
  ) async throws -> Note
  func deleteNote(id: UUID) async throws
  @discardableResult func applyExpirationPolicy(
    _ policy: NoteExpirationPolicy,
    effectiveAt date: Date
  ) async throws -> [Note]
  @discardableResult func deleteExpiredNotes(at date: Date) async throws
    -> ExpirationDeletionReceipt
  func previewBulkDeletion(before cutoff: Date) async throws -> BulkDeletionPreview
  @discardableResult func confirmBulkDeletion(
    _ preview: BulkDeletionPreview,
    backupAt date: Date
  ) async throws -> BulkDeletionReceipt
  func currentTimer() async throws -> NoteTimer?
  func saveCurrentTimer(_ timer: NoteTimer) async throws
  func deleteTimer(id: TimerID) async throws
  func shutdown() async throws
}

public enum InMemoryNoteRepositoryError: Error, Equatable, Sendable {
  case noteNotFound(UUID)
  case safetyBackupFailed
  case shutDown
}

public actor InMemoryNoteRepository: NoteRepository {
  private var notes: [UUID: Note]
  private var pendingDrafts: [UUID: NoteDraft] = [:]
  private var timer: NoteTimer?
  private var nextOrderKey: Int64
  private var isShutDown = false
  private var failsSafetyBackup: Bool
  private var safetyBackupDates: [Date] = []

  public init(notes: [Note] = [], failsSafetyBackup: Bool = false) {
    self.notes = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
    nextOrderKey = (notes.map(\.orderKey).max() ?? -1) + 1
    self.failsSafetyBackup = failsSafetyBackup
  }

  public func prepare() throws {
    guard !isShutDown else {
      throw InMemoryNoteRepositoryError.shutDown
    }
  }

  public func schedule(_ draft: NoteDraft) throws {
    try prepare()
    pendingDrafts[draft.id] = draft
  }

  public func discardPending(noteID: UUID) {
    pendingDrafts[noteID] = nil
  }

  @discardableResult
  public func flush() throws -> [Note] {
    try prepare()
    let drafts = pendingDrafts.values.sorted { $0.id.uuidString < $1.id.uuidString }
    var saved: [Note] = []
    for draft in drafts {
      let existing = notes[draft.id]
      let note = Note(
        id: draft.id,
        body: draft.body,
        createdAt: existing?.createdAt ?? draft.createdAt ?? draft.modifiedAt,
        modifiedAt: draft.modifiedAt,
        orderKey: existing?.orderKey ?? takeNextOrderKey(),
        expiresAt: draft.expiresAt,
        slotIndex: draft.slotIndex,
        selection: draft.selection,
        scrollOffset: draft.scrollOffset,
        sourceRevision: sourceRevision(existing: existing, body: draft.body)
      )
      notes[draft.id] = note
      pendingDrafts[draft.id] = nil
      saved.append(note)
    }
    return saved
  }

  public func note(id: UUID) throws -> Note? {
    try prepare()
    return notes[id]
  }

  public func allNotes() throws -> [Note] {
    try prepare()
    return notes.values.sorted(by: Self.isOrderedBefore)
  }

  public func search(_ query: String) throws -> [Note] {
    try prepare()
    guard !query.isEmpty else { return try allNotes() }
    return notes.values
      .filter { $0.body.localizedCaseInsensitiveContains(query) }
      .sorted(by: Self.isOrderedBefore)
  }

  public func searchPage(_ query: String, limit: Int, offset: Int) throws -> NoteSearchPage {
    let boundedLimit = max(1, limit)
    let boundedOffset = max(0, offset)
    let matches = try search(query)
    let remaining = matches.dropFirst(boundedOffset)
    return NoteSearchPage(
      notes: Array(remaining.prefix(boundedLimit)),
      hasMore: remaining.count > boundedLimit
    )
  }

  @discardableResult
  public func promoteNote(id: UUID, at date: Date) throws -> Note {
    try promoteNote(id: id, at: date, expiresAt: notes[id]?.expiresAt)
  }

  @discardableResult
  public func promoteNote(id: UUID, at date: Date, expiresAt: Date?) throws -> Note {
    try prepare()
    guard var note = notes[id] else {
      throw InMemoryNoteRepositoryError.noteNotFound(id)
    }
    note.orderKey = takeNextOrderKey()
    note.modifiedAt = date
    note.expiresAt = expiresAt
    notes[id] = note
    return note
  }

  public func deleteNote(id: UUID) throws {
    try prepare()
    removeNotes(ids: [id])
  }

  @discardableResult
  public func applyExpirationPolicy(
    _ policy: NoteExpirationPolicy,
    effectiveAt date: Date
  ) throws -> [Note] {
    _ = try flush()
    for id in notes.keys {
      guard var note = notes[id] else { continue }
      note.expiresAt = policy.expirationDate(referenceDate: max(note.modifiedAt, date))
      notes[id] = note
    }
    return try allNotes()
  }

  @discardableResult
  public func deleteExpiredNotes(at date: Date) throws -> ExpirationDeletionReceipt {
    _ = try flush()
    let expiredIDs: [UUID] = notes.values.compactMap { note in
      guard let expiresAt = note.expiresAt, expiresAt <= date else { return nil }
      return note.id
    }
    removeNotes(ids: expiredIDs)
    return ExpirationDeletionReceipt(evaluatedAt: date, deletedNoteIDs: expiredIDs)
  }

  public func previewBulkDeletion(before cutoff: Date) throws -> BulkDeletionPreview {
    try prepare()
    return BulkDeletionPreview(
      cutoff: cutoff,
      noteIDs: notes.values.filter { $0.modifiedAt < cutoff }.map(\.id)
    )
  }

  @discardableResult
  public func confirmBulkDeletion(
    _ preview: BulkDeletionPreview,
    backupAt date: Date
  ) throws -> BulkDeletionReceipt {
    _ = try flush()
    guard !failsSafetyBackup else {
      throw InMemoryNoteRepositoryError.safetyBackupFailed
    }
    safetyBackupDates.append(date)
    let eligibleIDs = preview.noteIDs.filter { id in
      guard let note = notes[id] else { return false }
      return note.modifiedAt < preview.cutoff
    }
    let backup = SafetyBackupReceipt(createdAt: date, noteCount: notes.count)
    removeNotes(ids: eligibleIDs)
    return BulkDeletionReceipt(
      preview: preview,
      deletedNoteIDs: eligibleIDs,
      safetyBackup: backup
    )
  }

  public func setFailsSafetyBackup(_ fails: Bool) {
    failsSafetyBackup = fails
  }

  public func safetyBackupCount() -> Int {
    safetyBackupDates.count
  }

  public func currentTimer() throws -> NoteTimer? {
    try prepare()
    return timer
  }

  public func saveCurrentTimer(_ timer: NoteTimer) throws {
    try prepare()
    guard notes[timer.noteID] != nil else {
      throw InMemoryNoteRepositoryError.noteNotFound(timer.noteID)
    }
    self.timer = timer
  }

  public func deleteTimer(id: TimerID) throws {
    try prepare()
    if timer?.id == id {
      timer = nil
    }
  }

  public func shutdown() throws {
    guard !isShutDown else { return }
    _ = try flush()
    isShutDown = true
  }

  private func takeNextOrderKey() -> Int64 {
    defer { nextOrderKey += 1 }
    return nextOrderKey
  }

  private func sourceRevision(existing: Note?, body: String) -> Int64 {
    guard let existing else { return 0 }
    return existing.body == body ? existing.sourceRevision : existing.sourceRevision + 1
  }

  private func removeNotes(ids: [UUID]) {
    let idSet = Set(ids)
    for id in idSet {
      notes[id] = nil
      pendingDrafts[id] = nil
    }
    if let timer, idSet.contains(timer.noteID) {
      self.timer = nil
    }
  }

  private static func isOrderedBefore(_ lhs: Note, _ rhs: Note) -> Bool {
    if lhs.orderKey == rhs.orderKey {
      return lhs.id.uuidString < rhs.id.uuidString
    }
    return lhs.orderKey > rhs.orderKey
  }
}

extension NoteRepository {
  public func searchPage(_ query: String, limit: Int, offset: Int) async throws -> NoteSearchPage {
    let boundedLimit = max(1, limit)
    let boundedOffset = max(0, offset)
    let matches = try await search(query)
    let remaining = matches.dropFirst(boundedOffset)
    return NoteSearchPage(
      notes: Array(remaining.prefix(boundedLimit)),
      hasMore: remaining.count > boundedLimit
    )
  }
}
