import Foundation

public enum PersistenceFaultPoint: String, Sendable {
  case beforeDatabaseWrite
  case afterBackupCopyBeforeFinalize
  case afterStoreReplacement
}

public struct PersistenceFaultInjector: Sendable {
  public static let none = PersistenceFaultInjector { _ in }

  private let handler: @Sendable (PersistenceFaultPoint) throws -> Void

  public init(handler: @escaping @Sendable (PersistenceFaultPoint) throws -> Void) {
    self.handler = handler
  }

  func hit(_ point: PersistenceFaultPoint) throws {
    try handler(point)
  }
}

public enum PersistenceStoreError: Error, Equatable, LocalizedError, Sendable {
  case noteNotFound(UUID)
  case invalidStoredNoteID(String)
  case orderSequenceOverflow
  case sourceRevisionOverflow
  case invalidBackupManifest
  case unsupportedBackupSchema(Int)
  case backupChecksumMismatch
  case backupNotesChecksumMismatch
  case databaseIntegrityCheckFailed(String)
  case ftsIndexDiverged
  case restoreRolledBack(String)
  case restoreRollbackFailed(String)

  public var errorDescription: String? {
    switch self {
    case .noteNotFound(let id):
      "Note \(id.uuidString) was not found."
    case .invalidStoredNoteID(let value):
      "Stored note ID is not a UUID: \(value)"
    case .orderSequenceOverflow:
      "The note ordering sequence is exhausted."
    case .sourceRevisionOverflow:
      "The note source revision is exhausted."
    case .invalidBackupManifest:
      "The backup manifest is missing or invalid."
    case .unsupportedBackupSchema(let version):
      "Backup schema version \(version) is not supported."
    case .backupChecksumMismatch:
      "The backup database checksum does not match its manifest."
    case .backupNotesChecksumMismatch:
      "The restored notes do not match the backup manifest."
    case .databaseIntegrityCheckFailed(let result):
      "SQLite integrity check failed: \(result)"
    case .ftsIndexDiverged:
      "The note rows and full-text index have diverged."
    case .restoreRolledBack(let reason):
      "Restore failed and the original store was restored: \(reason)"
    case .restoreRollbackFailed(let reason):
      "Restore and emergency rollback both failed: \(reason)"
    }
  }
}
