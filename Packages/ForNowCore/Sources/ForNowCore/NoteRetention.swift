import Foundation

public enum NoteExpirationChoice: String, CaseIterable, Codable, Sendable {
  case today
  case oneWeek
  case oneMonth
  case oneYear
  case never
}

public struct NoteExpirationPolicy: Sendable {
  public let choice: NoteExpirationChoice
  public let calendar: Calendar

  public init(
    choice: NoteExpirationChoice,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.choice = choice
    self.calendar = calendar
  }

  public func expirationDate(referenceDate: Date) -> Date? {
    switch choice {
    case .today:
      return calendar.dateInterval(of: .day, for: referenceDate)?.end
    case .oneWeek:
      return calendar.date(byAdding: .day, value: 7, to: referenceDate)
    case .oneMonth:
      return calendar.date(byAdding: .month, value: 1, to: referenceDate)
    case .oneYear:
      return calendar.date(byAdding: .year, value: 1, to: referenceDate)
    case .never:
      return nil
    }
  }
}

public struct ExpirationDeletionReceipt: Equatable, Sendable {
  public let evaluatedAt: Date
  public let deletedNoteIDs: [UUID]

  public init(evaluatedAt: Date, deletedNoteIDs: [UUID]) {
    self.evaluatedAt = evaluatedAt
    self.deletedNoteIDs = Self.normalized(deletedNoteIDs)
  }

  private static func normalized(_ noteIDs: [UUID]) -> [UUID] {
    Array(Set(noteIDs)).sorted { $0.uuidString < $1.uuidString }
  }
}

public struct BulkDeletionPreview: Equatable, Sendable {
  public let cutoff: Date
  public let noteIDs: [UUID]

  public var count: Int {
    noteIDs.count
  }

  public init(cutoff: Date, noteIDs: [UUID]) {
    self.cutoff = cutoff
    self.noteIDs = Array(Set(noteIDs)).sorted { $0.uuidString < $1.uuidString }
  }
}

public struct SafetyBackupReceipt: Equatable, Sendable {
  public let createdAt: Date
  public let noteCount: Int

  public init(createdAt: Date, noteCount: Int) {
    self.createdAt = createdAt
    self.noteCount = noteCount
  }
}

public struct BulkDeletionReceipt: Equatable, Sendable {
  public let preview: BulkDeletionPreview
  public let deletedNoteIDs: [UUID]
  public let skippedNoteIDs: [UUID]
  public let safetyBackup: SafetyBackupReceipt

  public var deletedCount: Int {
    deletedNoteIDs.count
  }

  public init(
    preview: BulkDeletionPreview,
    deletedNoteIDs: [UUID],
    safetyBackup: SafetyBackupReceipt
  ) {
    self.preview = preview
    let previewIDs = Set(preview.noteIDs)
    let deleted = Array(Set(deletedNoteIDs).intersection(previewIDs)).sorted {
      $0.uuidString < $1.uuidString
    }
    self.deletedNoteIDs = deleted
    let deletedSet = Set(deleted)
    skippedNoteIDs = preview.noteIDs.filter { !deletedSet.contains($0) }
    self.safetyBackup = safetyBackup
  }
}
