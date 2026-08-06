import ForNowCore
import Foundation
import GRDB

public actor PersistenceStore {
  public nonisolated let databaseURL: URL
  public nonisolated let backupDirectoryURL: URL

  var pool: DatabasePool
  let faultInjector: PersistenceFaultInjector

  public init(
    databaseURL: URL,
    backupDirectoryURL: URL,
    faultInjector: PersistenceFaultInjector = .none
  ) throws {
    self.databaseURL = databaseURL
    self.backupDirectoryURL = backupDirectoryURL
    self.faultInjector = faultInjector

    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)
    try Self.removeStaleBackupTemporaryFiles(in: backupDirectoryURL)

    let pool = try Self.openPool(at: databaseURL)
    try PersistenceSchema.migrate(pool)
    self.pool = pool
  }

  public func saveDraft(_ draft: NoteDraft) throws -> Note {
    try faultInjector.hit(.beforeDatabaseWrite)
    return try pool.write { db in
      if let existing = try Self.fetchNote(id: draft.id, in: db) {
        var sourceRevision = existing.sourceRevision
        if existing.body != draft.body {
          let nextRevision = sourceRevision.addingReportingOverflow(1)
          guard !nextRevision.overflow else {
            throw PersistenceStoreError.sourceRevisionOverflow
          }
          sourceRevision = nextRevision.partialValue
        }
        try db.execute(
          sql: """
            UPDATE note
            SET body = ?, modified_at = ?, expires_at = ?, slot_index = ?,
                selection_start = ?, selection_length = ?, scroll_offset = ?,
                source_revision = ?
            WHERE id = ?
            """,
          arguments: [
            draft.body,
            draft.modifiedAt.timeIntervalSince1970,
            draft.expiresAt?.timeIntervalSince1970,
            draft.slotIndex,
            draft.selection.location,
            draft.selection.length,
            draft.scrollOffset,
            sourceRevision,
            draft.id.uuidString,
          ]
        )
      } else {
        let orderKey = try Self.nextOrderKey(in: db)
        let timestamp = draft.modifiedAt.timeIntervalSince1970
        let createdTimestamp = (draft.createdAt ?? draft.modifiedAt).timeIntervalSince1970
        try db.execute(
          sql: """
            INSERT INTO note (
                id, body, created_at, modified_at, order_key, expires_at,
                slot_index, selection_start, selection_length, scroll_offset,
                source_revision
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """,
          arguments: [
            draft.id.uuidString,
            draft.body,
            createdTimestamp,
            timestamp,
            orderKey,
            draft.expiresAt?.timeIntervalSince1970,
            draft.slotIndex,
            draft.selection.location,
            draft.selection.length,
            draft.scrollOffset,
          ]
        )
      }
      try Self.replaceFTS(id: draft.id, body: draft.body, in: db)
      guard let savedNote = try Self.fetchNote(id: draft.id, in: db) else {
        throw PersistenceStoreError.noteNotFound(draft.id)
      }
      return savedNote
    }
  }

  public func createNote(
    id: UUID = UUID(),
    body: String,
    at date: Date = Date()
  ) throws -> Note {
    try saveDraft(NoteDraft(id: id, body: body, modifiedAt: date))
  }

  public func updateNote(
    id: UUID,
    body: String,
    at date: Date = Date()
  ) throws -> Note {
    guard let existing = try note(id: id) else {
      throw PersistenceStoreError.noteNotFound(id)
    }
    return try saveDraft(
      NoteDraft(
        id: id,
        body: body,
        modifiedAt: date,
        expiresAt: existing.expiresAt,
        slotIndex: existing.slotIndex,
        selection: existing.selection,
        scrollOffset: existing.scrollOffset
      )
    )
  }

  public func note(id: UUID) throws -> Note? {
    try pool.read { db in
      try Self.fetchNote(id: id, in: db)
    }
  }

  public func allNotes() throws -> [Note] {
    try pool.read { db in
      try NoteRow.fetchAll(in: db).map { try $0.note() }
    }
  }

  public func search(_ query: String) throws -> [Note] {
    try pool.read { db in
      try Self.searchRows(query, in: db).map { try $0.note() }
    }
  }

  public func searchPage(_ query: String, limit: Int, offset: Int) throws -> NoteSearchPage {
    let boundedLimit = min(max(1, limit), 200)
    let boundedOffset = max(0, offset)
    return try pool.read { db in
      let rows = try Self.searchRows(
        query,
        limit: boundedLimit + 1,
        offset: boundedOffset,
        in: db
      )
      return NoteSearchPage(
        notes: try rows.prefix(boundedLimit).map { try $0.note() },
        hasMore: rows.count > boundedLimit
      )
    }
  }

  @discardableResult
  public func promoteNote(id: UUID, at date: Date = Date()) throws -> Note {
    try faultInjector.hit(.beforeDatabaseWrite)
    return try pool.write { db in
      guard try Self.fetchNote(id: id, in: db) != nil else {
        throw PersistenceStoreError.noteNotFound(id)
      }
      let orderKey = try Self.nextOrderKey(in: db)
      try db.execute(
        sql: "UPDATE note SET order_key = ?, modified_at = ? WHERE id = ?",
        arguments: [orderKey, date.timeIntervalSince1970, id.uuidString]
      )
      guard let promoted = try Self.fetchNote(id: id, in: db) else {
        throw PersistenceStoreError.noteNotFound(id)
      }
      return promoted
    }
  }

  @discardableResult
  public func promoteNote(id: UUID, at date: Date, expiresAt: Date?) throws -> Note {
    try faultInjector.hit(.beforeDatabaseWrite)
    return try pool.write { db in
      guard try Self.fetchNote(id: id, in: db) != nil else {
        throw PersistenceStoreError.noteNotFound(id)
      }
      let orderKey = try Self.nextOrderKey(in: db)
      try db.execute(
        sql: "UPDATE note SET order_key = ?, modified_at = ?, expires_at = ? WHERE id = ?",
        arguments: [
          orderKey,
          date.timeIntervalSince1970,
          expiresAt?.timeIntervalSince1970,
          id.uuidString,
        ]
      )
      guard let promoted = try Self.fetchNote(id: id, in: db) else {
        throw PersistenceStoreError.noteNotFound(id)
      }
      return promoted
    }
  }

  public func deleteNote(id: UUID) throws {
    try faultInjector.hit(.beforeDatabaseWrite)
    try pool.write { db in
      try db.execute(sql: "DELETE FROM note_fts WHERE note_id = ?", arguments: [id.uuidString])
      try db.execute(sql: "DELETE FROM note WHERE id = ?", arguments: [id.uuidString])
    }
  }

  @discardableResult
  public func applyExpirationPolicy(
    _ policy: NoteExpirationPolicy,
    effectiveAt date: Date
  ) throws -> [Note] {
    try faultInjector.hit(.beforeDatabaseWrite)
    return try pool.write { db in
      let rows = try NoteRow.fetchAll(in: db)
      for row in rows {
        let note = try row.note()
        let referenceDate = max(note.modifiedAt, date)
        try db.execute(
          sql: "UPDATE note SET expires_at = ? WHERE id = ?",
          arguments: [
            policy.expirationDate(referenceDate: referenceDate)?.timeIntervalSince1970,
            note.id.uuidString,
          ]
        )
      }
      return try NoteRow.fetchAll(in: db).map { try $0.note() }
    }
  }

  @discardableResult
  public func deleteExpiredNotes(at date: Date) throws -> ExpirationDeletionReceipt {
    try faultInjector.hit(.beforeDatabaseWrite)
    let deletedIDs = try pool.write { db in
      let ids = try String.fetchAll(
        db,
        sql: """
          SELECT id FROM note
          WHERE expires_at IS NOT NULL AND expires_at <= ?
          ORDER BY id ASC
          """,
        arguments: [date.timeIntervalSince1970]
      ).map { value in
        guard let id = UUID(uuidString: value) else {
          throw PersistenceStoreError.invalidStoredNoteID(value)
        }
        return id
      }
      try Self.deleteNotes(ids: ids, in: db)
      return ids
    }
    return ExpirationDeletionReceipt(evaluatedAt: date, deletedNoteIDs: deletedIDs)
  }

  public func previewBulkDeletion(before cutoff: Date) throws -> BulkDeletionPreview {
    try pool.read { db in
      let ids = try String.fetchAll(
        db,
        sql: "SELECT id FROM note WHERE modified_at < ? ORDER BY id ASC",
        arguments: [cutoff.timeIntervalSince1970]
      ).map { value in
        guard let id = UUID(uuidString: value) else {
          throw PersistenceStoreError.invalidStoredNoteID(value)
        }
        return id
      }
      return BulkDeletionPreview(cutoff: cutoff, noteIDs: ids)
    }
  }

  @discardableResult
  public func deleteNotes(matching preview: BulkDeletionPreview) throws -> [UUID] {
    try faultInjector.hit(.beforeDatabaseWrite)
    return try pool.write { db in
      var eligibleIDs: [UUID] = []
      for id in preview.noteIDs {
        let modifiedAt = try Double.fetchOne(
          db,
          sql: "SELECT modified_at FROM note WHERE id = ?",
          arguments: [id.uuidString]
        )
        if let modifiedAt, modifiedAt < preview.cutoff.timeIntervalSince1970 {
          eligibleIDs.append(id)
        }
      }
      try Self.deleteNotes(ids: eligibleIDs, in: db)
      return eligibleIDs
    }
  }

  public func currentTimer() throws -> NoteTimer? {
    try pool.read { db in
      guard let row = try Row.fetchOne(db, sql: "SELECT * FROM timer LIMIT 1") else {
        return nil
      }
      return try TimerRow(row: row).timer()
    }
  }

  public func saveCurrentTimer(_ timer: NoteTimer) throws {
    try faultInjector.hit(.beforeDatabaseWrite)
    try pool.write { db in
      try db.execute(sql: "DELETE FROM timer")
      try db.execute(
        sql: """
          INSERT INTO timer (
              id, note_id, kind, title, phase, state, started_at,
              accumulated_seconds, work_seconds, rest_seconds
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          timer.id.uuidString,
          timer.noteID.uuidString,
          timer.kind.rawValue,
          timer.title,
          timer.phase.rawValue,
          timer.state.rawValue,
          timer.startedAt?.timeIntervalSince1970,
          TimerDuration.seconds(timer.accumulated),
          timer.workDuration.map(TimerDuration.seconds),
          timer.restDuration.map(TimerDuration.seconds),
        ]
      )
    }
  }

  public func deleteTimer(id: TimerID) throws {
    try faultInjector.hit(.beforeDatabaseWrite)
    try pool.write { db in
      try db.execute(sql: "DELETE FROM timer WHERE id = ?", arguments: [id.uuidString])
    }
  }

  public func schemaVersion() throws -> Int {
    try pool.read(PersistenceSchema.version(in:))
  }

  public func verifyIntegrity() throws {
    try Self.verifyDatabase(pool)
  }

  public func checkpoint() throws {
    _ = try pool.writeWithoutTransaction { db in
      try db.checkpoint(.truncate)
    }
  }

  public func close() throws {
    try pool.close()
  }

  static func openPool(at url: URL) throws -> DatabasePool {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    configuration.busyMode = .timeout(5)
    return try DatabasePool(path: url.path, configuration: configuration)
  }

  private static func searchRows(
    _ query: String,
    limit: Int? = nil,
    offset: Int = 0,
    in db: Database
  ) throws -> [NoteRow] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let pageClause = limit.map { " LIMIT \($0) OFFSET \(offset)" } ?? ""
    if normalizedQuery.isEmpty {
      return try NoteRow.fetchAll(in: db, orderBy: "order_key DESC\(pageClause)")
    }
    if normalizedQuery.unicodeScalars.contains(where: isCJK) {
      return try Row.fetchAll(
        db,
        sql: """
          SELECT * FROM note
          WHERE instr(body, ?) > 0
          ORDER BY order_key DESC\(pageClause)
          """,
        arguments: [normalizedQuery]
      ).map(NoteRow.init(row:))
    }
    guard let pattern = FTS5Pattern(matchingAllTokensIn: normalizedQuery) else {
      return []
    }
    return try Row.fetchAll(
      db,
      sql: """
        SELECT n.*
        FROM note AS n
        JOIN note_fts ON note_fts.note_id = n.id
        WHERE note_fts MATCH ?
        ORDER BY bm25(note_fts), n.order_key DESC\(pageClause)
        """,
      arguments: [pattern]
    ).map(NoteRow.init(row:))
  }

  static func verifyDatabase(_ pool: DatabasePool) throws {
    try pool.writeWithoutTransaction { db in
      try verifyDatabaseConnection(db)
    }
  }

  static func verifyDatabase(_ queue: DatabaseQueue) throws {
    try queue.read { db in
      try verifyDatabaseConnection(db)
    }
  }

  static func verifyDatabaseConnection(_ db: Database) throws {
    let integrity = try String.fetchOne(db, sql: "PRAGMA quick_check") ?? "missing result"
    guard integrity == "ok" else {
      throw PersistenceStoreError.databaseIntegrityCheckFailed(integrity)
    }

    let noteCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note") ?? 0
    let ftsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts") ?? 0
    let missingFTS =
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*)
          FROM note AS n
          LEFT JOIN note_fts AS f ON f.note_id = n.id
          WHERE f.note_id IS NULL
          """
      ) ?? 0
    let orphanedFTS =
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*)
          FROM note_fts AS f
          LEFT JOIN note AS n ON n.id = f.note_id
          WHERE n.id IS NULL
          """
      ) ?? 0
    let orphanedTimers =
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*)
          FROM timer AS t
          LEFT JOIN note AS n ON n.id = t.note_id
          WHERE n.id IS NULL
          """
      ) ?? 0
    guard noteCount == ftsCount, missingFTS == 0, orphanedFTS == 0, orphanedTimers == 0 else {
      throw PersistenceStoreError.ftsIndexDiverged
    }
  }

  static func fetchNote(id: UUID, in db: Database) throws -> Note? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: "SELECT * FROM note WHERE id = ?",
        arguments: [id.uuidString]
      )
    else { return nil }
    return try NoteRow(row: row).note()
  }

  static func replaceFTS(id: UUID, body: String, in db: Database) throws {
    try db.execute(
      sql: "UPDATE note_fts SET body = ? WHERE note_id = ?",
      arguments: [body, id.uuidString]
    )
    if db.changesCount == 0 {
      try db.execute(
        sql: "INSERT INTO note_fts (note_id, body) VALUES (?, ?)",
        arguments: [id.uuidString, body]
      )
    }
  }

  static func deleteNotes(ids: [UUID], in db: Database) throws {
    for id in ids {
      try db.execute(sql: "DELETE FROM note_fts WHERE note_id = ?", arguments: [id.uuidString])
      try db.execute(sql: "DELETE FROM note WHERE id = ?", arguments: [id.uuidString])
    }
  }

  static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
      true
    default:
      false
    }
  }

  static func nextOrderKey(in db: Database) throws -> Int64 {
    let storedData = try Data.fetchOne(
      db,
      sql: "SELECT value FROM metadata WHERE key = 'order_sequence'"
    )
    let storedValue = storedData.flatMap { Int64(String(decoding: $0, as: UTF8.self)) }
    let maximumOrder = try Int64.fetchOne(db, sql: "SELECT MAX(order_key) FROM note") ?? 0
    let current = max(storedValue ?? 0, maximumOrder)
    let next = current.addingReportingOverflow(1)
    guard !next.overflow else {
      throw PersistenceStoreError.orderSequenceOverflow
    }
    try db.execute(
      sql: """
        INSERT INTO metadata (key, value) VALUES ('order_sequence', ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
      arguments: [Data(String(next.partialValue).utf8)]
    )
    return next.partialValue
  }
}
