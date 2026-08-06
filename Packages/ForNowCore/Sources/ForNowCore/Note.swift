import Foundation

public struct NoteSelection: Codable, Equatable, Sendable {
  public var location: Int
  public var length: Int

  public init(location: Int = 0, length: Int = 0) {
    self.location = location
    self.length = length
  }
}

public struct Note: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public var body: String
  public let createdAt: Date
  public var modifiedAt: Date
  public var orderKey: Int64
  public var expiresAt: Date?
  public var slotIndex: Int?
  public var selection: NoteSelection
  public var scrollOffset: Int
  public var sourceRevision: Int64

  public init(
    id: UUID,
    body: String,
    createdAt: Date,
    modifiedAt: Date,
    orderKey: Int64,
    expiresAt: Date? = nil,
    slotIndex: Int? = nil,
    selection: NoteSelection = NoteSelection(),
    scrollOffset: Int = 0,
    sourceRevision: Int64 = 0
  ) {
    self.id = id
    self.body = body
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.orderKey = orderKey
    self.expiresAt = expiresAt
    self.slotIndex = slotIndex
    self.selection = selection
    self.scrollOffset = scrollOffset
    self.sourceRevision = sourceRevision
  }
}

public struct NoteDraft: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public var body: String
  public var createdAt: Date?
  public var modifiedAt: Date
  public var expiresAt: Date?
  public var slotIndex: Int?
  public var selection: NoteSelection
  public var scrollOffset: Int

  public init(
    id: UUID = UUID(),
    body: String,
    createdAt: Date? = nil,
    modifiedAt: Date = Date(),
    expiresAt: Date? = nil,
    slotIndex: Int? = nil,
    selection: NoteSelection = NoteSelection(),
    scrollOffset: Int = 0
  ) {
    self.id = id
    self.body = body
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.expiresAt = expiresAt
    self.slotIndex = slotIndex
    self.selection = selection
    self.scrollOffset = scrollOffset
  }
}

public struct NoteSearchPage: Equatable, Sendable {
  public let notes: [Note]
  public let hasMore: Bool

  public init(notes: [Note], hasMore: Bool) {
    self.notes = notes
    self.hasMore = hasMore
  }
}
