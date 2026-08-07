import AppKit
import ForNowPersistence
import Foundation

enum BackupSettingsError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedVersion(Int)
  case retainedCopiesOutOfRange(Int)
  case maximumAgeDaysOutOfRange(Int)

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion:
      "The backup settings version is not supported."
    case .retainedCopiesOutOfRange:
      "Retained backups must be between 1 and 100."
    case .maximumAgeDaysOutOfRange:
      "Backup age must be between 1 and 3,650 days."
    }
  }
}

struct BackupSettings: Codable, Equatable, Sendable {
  static let currentVersion = 1

  var version: Int
  var frequency: BackupFrequency
  var retainedCopies: Int
  var maximumAgeDays: Int

  init(
    version: Int = currentVersion,
    frequency: BackupFrequency = .hours3,
    retainedCopies: Int = 12,
    maximumAgeDays: Int = 30
  ) {
    self.version = version
    self.frequency = frequency
    self.retainedCopies = retainedCopies
    self.maximumAgeDays = maximumAgeDays
  }

  func validated() throws -> BackupSettings {
    guard version == Self.currentVersion else {
      throw BackupSettingsError.unsupportedVersion(version)
    }
    guard (1...100).contains(retainedCopies) else {
      throw BackupSettingsError.retainedCopiesOutOfRange(retainedCopies)
    }
    guard (1...3_650).contains(maximumAgeDays) else {
      throw BackupSettingsError.maximumAgeDaysOutOfRange(maximumAgeDays)
    }
    return self
  }

  var policy: BackupPolicy {
    BackupPolicy(
      frequency: frequency,
      retainedCopies: retainedCopies,
      maximumAge: TimeInterval(maximumAgeDays) * 24 * 60 * 60
    )
  }
}

protocol BackupSettingsStoring: Sendable {
  func load() async -> BackupSettings
  func save(_ settings: BackupSettings) async throws
}

actor UserDefaultsBackupSettingsStore: BackupSettingsStoring {
  private enum Key {
    static let settings = "app.fornow.backup.settings.v1"
  }

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(suiteName: String? = nil) {
    if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
      self.defaults = defaults
    } else {
      defaults = .standard
    }
  }

  func load() -> BackupSettings {
    guard
      let data = defaults.data(forKey: Key.settings),
      let settings = try? decoder.decode(BackupSettings.self, from: data),
      (try? settings.validated()) != nil
    else {
      return BackupSettings()
    }
    return settings
  }

  func save(_ settings: BackupSettings) throws {
    let settings = try settings.validated()
    defaults.set(try encoder.encode(settings), forKey: Key.settings)
  }
}

actor InMemoryBackupSettingsStore: BackupSettingsStoring {
  private var settings: BackupSettings
  private var saveError: BackupSettingsError?

  init(
    settings: BackupSettings = BackupSettings(),
    saveError: BackupSettingsError? = nil
  ) {
    self.settings = settings
    self.saveError = saveError
  }

  func load() -> BackupSettings {
    settings
  }

  func save(_ settings: BackupSettings) throws {
    if let saveError { throw saveError }
    self.settings = try settings.validated()
  }

  func setSaveError(_ error: BackupSettingsError?) {
    saveError = error
  }
}

struct ManagedBackup: Identifiable, Equatable, Sendable {
  var id: URL { manifestURL }

  let databaseURL: URL
  let manifestURL: URL
  let createdAt: Date
  let byteCount: Int64
  let schemaVersion: Int
  let noteCount: Int
}

struct ManagedRestoreReceipt: Equatable, Sendable {
  let restoredBackup: ManagedBackup
  let emergencyBackup: ManagedBackup
  let recoveryReport: BackupRecoveryReport
  let recoveryReportURL: URL
}

protocol BackupManaging: Sendable {
  var notesDirectoryURL: URL { get }
  var backupDirectoryURL: URL { get }

  func createBackup(at date: Date, policy: BackupPolicy) async throws -> ManagedBackup
  func createBackupIfEligible(
    afterSuccessfulWriteAt writeDate: Date,
    now: Date,
    policy: BackupPolicy
  ) async throws -> ManagedBackup?
  func availableBackups() async throws -> [ManagedBackup]
  func pruneBackups(policy: BackupPolicy, now: Date) async throws
  func restoreBackup(manifestURL: URL, at date: Date) async throws -> ManagedRestoreReceipt
}

actor PersistenceBackupManager: BackupManaging {
  nonisolated let notesDirectoryURL: URL
  nonisolated let backupDirectoryURL: URL

  private let repository: PersistenceNoteRepository

  init(repository: PersistenceNoteRepository) {
    self.repository = repository
    notesDirectoryURL = repository.databaseURL.deletingLastPathComponent()
    backupDirectoryURL = repository.backupDirectoryURL
  }

  func createBackup(at date: Date, policy: BackupPolicy) async throws -> ManagedBackup {
    try managedBackup(from: await repository.createBackup(at: date, policy: policy))
  }

  func createBackupIfEligible(
    afterSuccessfulWriteAt writeDate: Date,
    now: Date,
    policy: BackupPolicy
  ) async throws -> ManagedBackup? {
    guard
      let descriptor = try await repository.createBackupIfEligible(
        afterSuccessfulWriteAt: writeDate,
        now: now,
        policy: policy
      )
    else { return nil }
    return try managedBackup(from: descriptor)
  }

  func availableBackups() async throws -> [ManagedBackup] {
    try await repository.availableBackups().map(managedBackup)
  }

  func pruneBackups(policy: BackupPolicy, now: Date) async throws {
    try await repository.pruneBackups(policy: policy, now: now)
  }

  func restoreBackup(manifestURL: URL, at date: Date) async throws -> ManagedRestoreReceipt {
    let receipt = try await repository.restoreBackup(manifestURL: manifestURL, at: date)
    return try ManagedRestoreReceipt(
      restoredBackup: managedBackup(from: receipt.restoredBackup),
      emergencyBackup: managedBackup(from: receipt.emergencyBackup),
      recoveryReport: receipt.recoveryReport,
      recoveryReportURL: receipt.recoveryReportURL
    )
  }

  private func managedBackup(from descriptor: BackupDescriptor) throws -> ManagedBackup {
    let databaseSize = try fileSize(at: descriptor.databaseURL)
    let manifestSize = try fileSize(at: descriptor.manifestURL)
    return ManagedBackup(
      databaseURL: descriptor.databaseURL,
      manifestURL: descriptor.manifestURL,
      createdAt: descriptor.manifest.createdAt,
      byteCount: databaseSize + manifestSize,
      schemaVersion: descriptor.manifest.schemaVersion,
      noteCount: descriptor.manifest.noteCount
    )
  }

  private func fileSize(at url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }
}

actor InMemoryBackupManager: BackupManaging {
  nonisolated let notesDirectoryURL: URL
  nonisolated let backupDirectoryURL: URL

  private var backups: [ManagedBackup]

  init(
    notesDirectoryURL: URL = URL(fileURLWithPath: "/tmp/ForNow", isDirectory: true),
    backupDirectoryURL: URL = URL(fileURLWithPath: "/tmp/ForNow/Backups", isDirectory: true),
    backups: [ManagedBackup] = []
  ) {
    self.notesDirectoryURL = notesDirectoryURL
    self.backupDirectoryURL = backupDirectoryURL
    self.backups = backups
  }

  func createBackup(at date: Date, policy: BackupPolicy) -> ManagedBackup {
    let backup = makeBackup(prefix: "backup", at: date)
    backups.insert(backup, at: 0)
    prune(policy: policy, now: date)
    return backup
  }

  func createBackupIfEligible(
    afterSuccessfulWriteAt writeDate: Date,
    now: Date,
    policy: BackupPolicy
  ) -> ManagedBackup? {
    guard writeDate <= now, let interval = policy.frequency.interval else { return nil }
    guard backups.first.map({ now.timeIntervalSince($0.createdAt) >= interval }) ?? true else {
      return nil
    }
    return createBackup(at: now, policy: policy)
  }

  func availableBackups() -> [ManagedBackup] {
    backups
  }

  func pruneBackups(policy: BackupPolicy, now: Date) {
    prune(policy: policy, now: now)
  }

  func restoreBackup(manifestURL: URL, at date: Date) throws -> ManagedRestoreReceipt {
    guard let restored = backups.first(where: { $0.manifestURL == manifestURL }) else {
      throw BackupSettingsError.unsupportedVersion(0)
    }
    let emergency = makeBackup(prefix: "emergency", at: date)
    let report = BackupRecoveryReport(
      operationID: UUID(),
      startedAt: date,
      completedAt: date,
      requestedManifestFileName: restored.manifestURL.lastPathComponent,
      requestedSchemaVersion: restored.schemaVersion,
      requestedNoteCount: restored.noteCount,
      emergencyManifestFileName: emergency.manifestURL.lastPathComponent,
      outcome: .restored,
      failureCode: nil
    )
    return ManagedRestoreReceipt(
      restoredBackup: restored,
      emergencyBackup: emergency,
      recoveryReport: report,
      recoveryReportURL: backupDirectoryURL.appendingPathComponent(
        "recovery-\(report.operationID.uuidString.lowercased()).json"
      )
    )
  }

  private func makeBackup(prefix: String, at date: Date) -> ManagedBackup {
    let identifier = "\(prefix)-\(UUID().uuidString.lowercased())"
    return ManagedBackup(
      databaseURL: backupDirectoryURL.appendingPathComponent("\(identifier).sqlite"),
      manifestURL: backupDirectoryURL.appendingPathComponent("\(identifier).json"),
      createdAt: date,
      byteCount: 4_096,
      schemaVersion: 2,
      noteCount: 0
    )
  }

  private func prune(policy: BackupPolicy, now: Date) {
    backups = backups.enumerated().compactMap { index, backup in
      let isOverCount = index >= policy.retainedCopies
      let isOverAge = now.timeIntervalSince(backup.createdAt) > policy.maximumAge
      return isOverCount || isOverAge ? nil : backup
    }
  }
}

@MainActor
protocol FolderRevealing {
  func reveal(_ directoryURL: URL) throws
}

enum FolderRevealError: Error, LocalizedError {
  case unavailable

  var errorDescription: String? {
    "Finder could not reveal the selected folder."
  }
}

@MainActor
struct SystemFolderRevealer: FolderRevealing {
  func reveal(_ directoryURL: URL) throws {
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    guard NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directoryURL.path) else {
      throw FolderRevealError.unavailable
    }
  }
}

@MainActor
final class RecordingFolderRevealer: FolderRevealing {
  private(set) var revealedURLs: [URL] = []

  func reveal(_ directoryURL: URL) {
    revealedURLs.append(directoryURL)
  }
}

enum BackupOperationState: Equatable, Sendable {
  case idle
  case creating
  case restoring

  var isWorking: Bool {
    self != .idle
  }
}

enum BackupOperationError: Error, Equatable, LocalizedError, Sendable {
  case unavailable
  case inProgress

  var errorDescription: String? {
    switch self {
    case .unavailable: "Backup management is unavailable until startup completes."
    case .inProgress: "Another backup or deletion operation is still in progress."
    }
  }
}

extension BackupFrequency {
  var displayName: String {
    switch self {
    case .minutes10: "10 minutes"
    case .minutes30: "30 minutes"
    case .hour1: "1 hour"
    case .hours3: "3 hours"
    case .hours12: "12 hours"
    case .day1: "1 day"
    case .days3: "3 days"
    case .week1: "1 week"
    case .month1: "1 month"
    case .never: "Never"
    }
  }
}
