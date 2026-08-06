import ForNowCore
import Foundation
import GRDB

struct NoteRow: Sendable {
  let id: String
  let body: String
  let createdAt: Double
  let modifiedAt: Double
  let orderKey: Int64
  let expiresAt: Double?
  let slotIndex: Int?
  let selectionStart: Int?
  let selectionLength: Int?
  let scrollOffset: Int?
  let sourceRevision: Int64

  init(row: Row) {
    id = row["id"]
    body = row["body"]
    createdAt = row["created_at"]
    modifiedAt = row["modified_at"]
    orderKey = row["order_key"]
    expiresAt = row["expires_at"]
    slotIndex = row["slot_index"]
    selectionStart = row["selection_start"]
    selectionLength = row["selection_length"]
    scrollOffset = row["scroll_offset"]
    sourceRevision = row["source_revision"]
  }

  func note() throws -> Note {
    guard let uuid = UUID(uuidString: id) else {
      throw PersistenceStoreError.invalidStoredNoteID(id)
    }
    return Note(
      id: uuid,
      body: body,
      createdAt: Date(timeIntervalSince1970: createdAt),
      modifiedAt: Date(timeIntervalSince1970: modifiedAt),
      orderKey: orderKey,
      expiresAt: expiresAt.map(Date.init(timeIntervalSince1970:)),
      slotIndex: slotIndex,
      selection: NoteSelection(
        location: selectionStart ?? 0,
        length: selectionLength ?? 0
      ),
      scrollOffset: scrollOffset ?? 0,
      sourceRevision: sourceRevision
    )
  }

  static func fetchAll(in db: Database, orderBy clause: String = "order_key DESC") throws
    -> [NoteRow]
  {
    let hasSourceRevision = try db.columns(in: "note").contains { $0.name == "source_revision" }
    let revisionSelection = hasSourceRevision ? "source_revision" : "0 AS source_revision"
    return try Row.fetchAll(
      db,
      sql: """
        SELECT id, body, created_at, modified_at, order_key, expires_at,
               slot_index, selection_start, selection_length, scroll_offset,
               \(revisionSelection)
        FROM note
        ORDER BY \(clause)
        """
    ).map(NoteRow.init(row:))
  }
}
