import CryptoKit
import Foundation
import GRDB

public enum BackupFrequency: String, CaseIterable, Codable, Sendable {
  case minutes10
  case minutes30
  case hour1
  case hours3
  case hours12
  case day1
  case days3
  case week1
  case month1
  case never

  public var interval: TimeInterval? {
    switch self {
    case .minutes10: 10 * 60
    case .minutes30: 30 * 60
    case .hour1: 60 * 60
    case .hours3: 3 * 60 * 60
    case .hours12: 12 * 60 * 60
    case .day1: 24 * 60 * 60
    case .days3: 3 * 24 * 60 * 60
    case .week1: 7 * 24 * 60 * 60
    case .month1: 30 * 24 * 60 * 60
    case .never: nil
    }
  }
}

public struct BackupPolicy: Equatable, Sendable {
  public var frequency: BackupFrequency
  public var retainedCopies: Int
  public var maximumAge: TimeInterval

  public init(
    frequency: BackupFrequency = .hours3,
    retainedCopies: Int = 12,
    maximumAge: TimeInterval = 30 * 24 * 60 * 60
  ) {
    self.frequency = frequency
    self.retainedCopies = max(1, retainedCopies)
    self.maximumAge = max(0, maximumAge)
  }
}

public struct BackupManifest: Codable, Equatable, Sendable {
  public let formatVersion: Int
  public let schemaVersion: Int
  public let createdAt: Date
  public let databaseFileName: String
  public let databaseSHA256: String
  public let notesSHA256: String
  public let noteCount: Int

  public init(
    formatVersion: Int = 1,
    schemaVersion: Int,
    createdAt: Date,
    databaseFileName: String,
    databaseSHA256: String,
    notesSHA256: String,
    noteCount: Int
  ) {
    self.formatVersion = formatVersion
    self.schemaVersion = schemaVersion
    self.createdAt = createdAt
    self.databaseFileName = databaseFileName
    self.databaseSHA256 = databaseSHA256
    self.notesSHA256 = notesSHA256
    self.noteCount = noteCount
  }
}

public struct BackupDescriptor: Equatable, Sendable {
  public let databaseURL: URL
  public let manifestURL: URL
  public let manifest: BackupManifest

  public init(databaseURL: URL, manifestURL: URL, manifest: BackupManifest) {
    self.databaseURL = databaseURL
    self.manifestURL = manifestURL
    self.manifest = manifest
  }
}

extension PersistenceStore {
  @discardableResult
  public func createBackup(
    at date: Date = Date(),
    policy: BackupPolicy = BackupPolicy()
  ) throws -> BackupDescriptor {
    let descriptor = try createBackup(at: date, prefix: "backup")
    try pruneBackups(policy: policy, now: date)
    return descriptor
  }

  public func createBackupIfEligible(
    afterSuccessfulWriteAt writeDate: Date,
    now: Date = Date(),
    policy: BackupPolicy = BackupPolicy()
  ) throws -> BackupDescriptor? {
    guard writeDate <= now, let interval = policy.frequency.interval else { return nil }
    let latestDate = try availableBackups().map(\.manifest.createdAt).max()
    guard latestDate == nil || now.timeIntervalSince(latestDate!) >= interval else { return nil }
    return try createBackup(at: now, policy: policy)
  }

  public func availableBackups() throws -> [BackupDescriptor] {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: backupDirectoryURL.path) else { return [] }
    return try fileManager.contentsOfDirectory(
      at: backupDirectoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.lastPathComponent.hasPrefix("backup-") && $0.pathExtension == "json" }
    .compactMap { try? Self.loadAndValidateManifest(at: $0, validateDatabase: false) }
    .sorted { $0.manifest.createdAt > $1.manifest.createdAt }
  }

  public func validateBackup(manifestURL: URL) throws -> BackupDescriptor {
    try Self.loadAndValidateManifest(at: manifestURL, validateDatabase: true)
  }

  @discardableResult
  public func restoreBackup(manifestURL: URL) throws -> BackupDescriptor {
    let validated = try Self.loadAndValidateManifest(at: manifestURL, validateDatabase: true)
    let emergency = try createBackup(at: Date(), prefix: "emergency")
    let fileManager = FileManager.default
    let stagingURL = databaseURL.deletingLastPathComponent()
      .appendingPathComponent(".restore-\(UUID().uuidString).sqlite")
    try? fileManager.removeItem(at: stagingURL)
    try fileManager.copyItem(at: validated.databaseURL, to: stagingURL)

    var databaseWasClosed = false
    do {
      try pool.close()
      databaseWasClosed = true
      Self.removeSQLiteSidecars(for: databaseURL)
      _ = try fileManager.replaceItemAt(databaseURL, withItemAt: stagingURL)
      pool = try Self.openPool(at: databaseURL)
      databaseWasClosed = false
      try PersistenceSchema.migrate(pool)
      try faultInjector.hit(.afterStoreReplacement)
      try Self.verifyDatabase(pool)
      let restoredIdentity = try Self.databaseIdentity(pool)
      guard restoredIdentity.noteCount == validated.manifest.noteCount else {
        throw PersistenceStoreError.backupNotesChecksumMismatch
      }
      guard restoredIdentity.notesSHA256 == validated.manifest.notesSHA256 else {
        throw PersistenceStoreError.backupNotesChecksumMismatch
      }
      return emergency
    } catch {
      try? fileManager.removeItem(at: stagingURL)
      do {
        if !databaseWasClosed {
          try pool.close()
        }
        try Self.replaceClosedDatabase(at: databaseURL, with: emergency.databaseURL)
        pool = try Self.openPool(at: databaseURL)
        databaseWasClosed = false
        try PersistenceSchema.migrate(pool)
        try Self.verifyDatabase(pool)
        let emergencyIdentity = try Self.databaseIdentity(pool)
        guard emergencyIdentity.noteCount == emergency.manifest.noteCount,
          emergencyIdentity.notesSHA256 == emergency.manifest.notesSHA256
        else {
          throw PersistenceStoreError.backupNotesChecksumMismatch
        }
      } catch {
        throw PersistenceStoreError.restoreRollbackFailed(String(describing: error))
      }
      throw PersistenceStoreError.restoreRolledBack(String(describing: error))
    }
  }

  func createBackup(at date: Date, prefix: String) throws -> BackupDescriptor {
    let fileManager = FileManager.default
    let identifier = "\(Int64(date.timeIntervalSince1970 * 1_000))-\(UUID().uuidString)"
    let databaseFileName = "\(prefix)-\(identifier).sqlite"
    let manifestFileName = "\(prefix)-\(identifier).json"
    let temporaryDatabaseURL =
      backupDirectoryURL
      .appendingPathComponent(".\(databaseFileName).tmp")
    let temporaryManifestURL =
      backupDirectoryURL
      .appendingPathComponent(".\(manifestFileName).tmp")
    let finalDatabaseURL = backupDirectoryURL.appendingPathComponent(databaseFileName)
    let finalManifestURL = backupDirectoryURL.appendingPathComponent(manifestFileName)

    for url in [temporaryDatabaseURL, temporaryManifestURL, finalDatabaseURL, finalManifestURL] {
      try? fileManager.removeItem(at: url)
    }

    do {
      let destination = try DatabaseQueue(path: temporaryDatabaseURL.path)
      try pool.backup(to: destination)
      _ = try destination.writeWithoutTransaction { db in
        try String.fetchOne(db, sql: "PRAGMA journal_mode = DELETE")
      }
      try destination.close()
      Self.removeSQLiteSidecars(for: temporaryDatabaseURL)
      try faultInjector.hit(.afterBackupCopyBeforeFinalize)

      let identity = try Self.validateDatabaseFile(at: temporaryDatabaseURL)
      let databaseChecksum = try Self.sha256(ofFileAt: temporaryDatabaseURL)
      let manifest = BackupManifest(
        schemaVersion: identity.schemaVersion,
        createdAt: date,
        databaseFileName: databaseFileName,
        databaseSHA256: databaseChecksum,
        notesSHA256: identity.notesSHA256,
        noteCount: identity.noteCount
      )
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(manifest).write(to: temporaryManifestURL, options: .atomic)

      try fileManager.moveItem(at: temporaryDatabaseURL, to: finalDatabaseURL)
      do {
        try fileManager.moveItem(at: temporaryManifestURL, to: finalManifestURL)
      } catch {
        try? fileManager.removeItem(at: finalDatabaseURL)
        throw error
      }
      return BackupDescriptor(
        databaseURL: finalDatabaseURL,
        manifestURL: finalManifestURL,
        manifest: manifest
      )
    } catch {
      try? fileManager.removeItem(at: temporaryDatabaseURL)
      try? fileManager.removeItem(at: temporaryManifestURL)
      throw error
    }
  }

  func pruneBackups(policy: BackupPolicy, now: Date) throws {
    let backups = try availableBackups()
    for (index, backup) in backups.enumerated() {
      let isOverCount = index >= policy.retainedCopies
      let isOverAge = now.timeIntervalSince(backup.manifest.createdAt) > policy.maximumAge
      if isOverCount || isOverAge {
        try? FileManager.default.removeItem(at: backup.manifestURL)
        try? FileManager.default.removeItem(at: backup.databaseURL)
      }
    }
  }

  static func loadAndValidateManifest(
    at manifestURL: URL,
    validateDatabase: Bool
  ) throws -> BackupDescriptor {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard
      let manifest = try? decoder.decode(
        BackupManifest.self,
        from: Data(contentsOf: manifestURL)
      ),
      manifest.formatVersion == 1,
      !manifest.databaseFileName.contains("/"),
      !manifest.databaseFileName.contains(":")
    else {
      throw PersistenceStoreError.invalidBackupManifest
    }
    guard (1...PersistenceSchema.currentVersion).contains(manifest.schemaVersion) else {
      throw PersistenceStoreError.unsupportedBackupSchema(manifest.schemaVersion)
    }
    let databaseURL = manifestURL.deletingLastPathComponent()
      .appendingPathComponent(manifest.databaseFileName)
    guard FileManager.default.fileExists(atPath: databaseURL.path) else {
      throw PersistenceStoreError.invalidBackupManifest
    }
    let descriptor = BackupDescriptor(
      databaseURL: databaseURL,
      manifestURL: manifestURL,
      manifest: manifest
    )
    guard validateDatabase else { return descriptor }

    guard try sha256(ofFileAt: databaseURL) == manifest.databaseSHA256 else {
      throw PersistenceStoreError.backupChecksumMismatch
    }
    let identity = try validateDatabaseFile(at: databaseURL)
    guard identity.schemaVersion == manifest.schemaVersion else {
      throw PersistenceStoreError.unsupportedBackupSchema(identity.schemaVersion)
    }
    guard identity.noteCount == manifest.noteCount,
      identity.notesSHA256 == manifest.notesSHA256
    else {
      throw PersistenceStoreError.backupNotesChecksumMismatch
    }
    return descriptor
  }

  static func validateDatabaseFile(at url: URL) throws -> DatabaseIdentity {
    var configuration = Configuration()
    configuration.readonly = true
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(path: url.path, configuration: configuration)
    defer { try? queue.close() }
    try verifyDatabase(queue)
    return try databaseIdentity(queue)
  }

  static func databaseIdentity(_ reader: any DatabaseReader) throws -> DatabaseIdentity {
    try reader.read { db in
      let rows = try NoteRow.fetchAll(in: db, orderBy: "id ASC")
      let digest = notesDigest(rows)
      return DatabaseIdentity(
        schemaVersion: try PersistenceSchema.version(in: db),
        noteCount: rows.count,
        notesSHA256: digest
      )
    }
  }

  static func notesDigest(_ rows: [NoteRow]) -> String {
    var data = Data()
    for row in rows {
      append(row.id, to: &data)
      append(row.body, to: &data)
      append(String(row.createdAt.bitPattern), to: &data)
      append(String(row.modifiedAt.bitPattern), to: &data)
      append(String(row.orderKey), to: &data)
      append(row.expiresAt.map { String($0.bitPattern) } ?? "nil", to: &data)
      append(row.slotIndex.map(String.init) ?? "nil", to: &data)
      append(row.selectionStart.map(String.init) ?? "nil", to: &data)
      append(row.selectionLength.map(String.init) ?? "nil", to: &data)
      append(row.scrollOffset.map(String.init) ?? "nil", to: &data)
      append(String(row.sourceRevision), to: &data)
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func append(_ value: String, to data: inout Data) {
    let bytes = Data(value.utf8)
    var length = UInt64(bytes.count).bigEndian
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    data.append(bytes)
  }

  static func sha256(ofFileAt url: URL) throws -> String {
    let digest = SHA256.hash(data: try Data(contentsOf: url))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  static func replaceClosedDatabase(at destination: URL, with source: URL) throws {
    let fileManager = FileManager.default
    let stagingURL = destination.deletingLastPathComponent()
      .appendingPathComponent(".rollback-\(UUID().uuidString).sqlite")
    try? fileManager.removeItem(at: stagingURL)
    try fileManager.copyItem(at: source, to: stagingURL)
    removeSQLiteSidecars(for: destination)
    _ = try fileManager.replaceItemAt(destination, withItemAt: stagingURL)
  }

  static func removeSQLiteSidecars(for databaseURL: URL) {
    let fileManager = FileManager.default
    for suffix in ["-wal", "-shm"] {
      try? fileManager.removeItem(atPath: databaseURL.path + suffix)
    }
  }

  static func removeStaleBackupTemporaryFiles(in directoryURL: URL) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: directoryURL.path) else { return }
    for url in try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: []
    ) where url.lastPathComponent.hasPrefix(".") && url.lastPathComponent.hasSuffix(".tmp") {
      try fileManager.removeItem(at: url)
    }
  }
}

struct DatabaseIdentity: Equatable, Sendable {
  let schemaVersion: Int
  let noteCount: Int
  let notesSHA256: String
}
