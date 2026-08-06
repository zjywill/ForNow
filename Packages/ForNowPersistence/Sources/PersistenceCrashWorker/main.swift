import ForNowCore
import ForNowPersistence
import Foundation

@main
struct PersistenceCrashWorker {
  static func main() async {
    do {
      try await run(arguments: Array(CommandLine.arguments.dropFirst()))
    } catch {
      FileHandle.standardError.write(Data("\(error)\n".utf8))
      Foundation.exit(1)
    }
  }

  static func run(arguments: [String]) async throws {
    guard arguments.count >= 5 else {
      throw WorkerError.invalidArguments
    }
    let command = arguments[0]
    let databaseURL = URL(fileURLWithPath: arguments[1])
    let backupDirectoryURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
    guard let noteID = UUID(uuidString: arguments[3]) else {
      throw WorkerError.invalidArguments
    }

    switch command {
    case "write-and-wait":
      guard arguments.count == 6 else {
        throw WorkerError.invalidArguments
      }
      let readyURL = URL(fileURLWithPath: arguments[4])
      let body = arguments[5]
      let store = try PersistenceStore(
        databaseURL: databaseURL,
        backupDirectoryURL: backupDirectoryURL
      )
      _ = try await store.saveDraft(NoteDraft(id: noteID, body: body))
      try Data().write(to: readyURL, options: .atomic)
      waitForTermination()

    case "backup-and-wait":
      guard arguments.count == 5 else {
        throw WorkerError.invalidArguments
      }
      let readyURL = URL(fileURLWithPath: arguments[4])
      let store = try PersistenceStore(
        databaseURL: databaseURL,
        backupDirectoryURL: backupDirectoryURL,
        faultInjector: PersistenceFaultInjector { point in
          guard point == .afterBackupCopyBeforeFinalize else { return }
          try Data().write(to: readyURL, options: .atomic)
          waitForTermination()
        }
      )
      _ = try await store.createBackup()

    case "read":
      guard arguments.count == 5 else {
        throw WorkerError.invalidArguments
      }
      let store = try PersistenceStore(
        databaseURL: databaseURL,
        backupDirectoryURL: backupDirectoryURL
      )
      guard let note = try await store.note(id: noteID) else {
        throw WorkerError.noteMissing
      }
      print(note.body)
      try await store.close()

    default:
      throw WorkerError.invalidArguments
    }
  }

  static func waitForTermination() -> Never {
    while true {
      Thread.sleep(forTimeInterval: 60)
    }
  }
}

private enum WorkerError: Error {
  case invalidArguments
  case noteMissing
}
