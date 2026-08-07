import CryptoKit
import ForNowCore
import Foundation
import GRDB
import Testing

@testable import ForNowPersistence

@Suite(.serialized)
struct PersistenceSpikeTests {
  @Test("IT-NOTE-001, IT-NOTE-004A, IT-NOTE-007: identity, ordering, update, and FTS")
  func noteCRUDOrderingAndSearch() async throws {
    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
      let firstID = UUID()
      let secondID = UUID()

      let first = try await store.createNote(
        id: firstID,
        body: "Launch checklist and ASCII search",
        at: timestamp
      )
      let second = try await store.createNote(
        id: secondID,
        body: "购买苹果并记录中文内容",
        at: timestamp
      )
      #expect(first.id == firstID)
      #expect(second.id == secondID)
      #expect(second.orderKey > first.orderKey)

      let updated = try await store.updateNote(
        id: firstID,
        body: "Launch checklist updated",
        at: timestamp.addingTimeInterval(1)
      )
      #expect(updated.id == firstID)
      #expect(updated.orderKey == first.orderKey)
      #expect(updated.sourceRevision == 1)

      let metadataOnly = try await store.saveDraft(
        NoteDraft(
          id: firstID,
          body: updated.body,
          modifiedAt: timestamp.addingTimeInterval(2),
          selection: NoteSelection(location: 3, length: 2),
          scrollOffset: 7
        )
      )
      #expect(metadataOnly.sourceRevision == updated.sourceRevision)
      #expect(metadataOnly.selection == NoteSelection(location: 3, length: 2))
      #expect(metadataOnly.scrollOffset == 7)
      #expect(try await store.search("Launch").map(\.id) == [firstID])
      #expect(try await store.search("苹果").map(\.id) == [secondID])

      let firstPage = try await store.searchPage("", limit: 1, offset: 0)
      #expect(firstPage.notes.map(\.id) == [secondID])
      #expect(firstPage.hasMore)
      let secondPage = try await store.searchPage("", limit: 1, offset: 1)
      #expect(secondPage.notes.map(\.id) == [firstID])
      #expect(!secondPage.hasMore)
      let ftsPage = try await store.searchPage("Launch", limit: 50, offset: 0)
      #expect(ftsPage.notes.map(\.id) == [firstID])
      #expect(!ftsPage.hasMore)

      try await store.deleteNote(id: secondID)
      #expect(try await store.note(id: secondID) == nil)
      #expect(try await store.search("苹果").isEmpty)
      try await store.verifyIntegrity()
      try await store.close()
    }
  }

  @Test("IT-TIME-001: timer round-trip, relaunch, source isolation, and note cascade")
  func timerPersistsWithoutMutatingCanonicalSource() async throws {
    try await withWorkspace { workspace in
      let source = "timer 25 5: Focus block\ncanonical timer source"
      let noteID = UUID()
      let timerID = UUID()
      let startedAt = Date(timeIntervalSince1970: 1_700_000_123)
      let firstStore = try workspace.makeStore()
      let note = try await firstStore.createNote(
        id: noteID,
        body: source,
        at: Date(timeIntervalSince1970: 1_700_000_000)
      )
      let timer = NoteTimer(
        id: timerID,
        noteID: noteID,
        kind: .pomodoro,
        title: "Focus block",
        phase: .rest,
        state: .running,
        startedAt: startedAt,
        accumulated: .seconds(17),
        workDuration: .seconds(1_500),
        restDuration: .seconds(300)
      )

      try await firstStore.saveCurrentTimer(timer)
      #expect(try await firstStore.currentTimer() == timer)
      #expect(try await firstStore.note(id: noteID)?.body == source)
      #expect(try await firstStore.note(id: noteID)?.sourceRevision == note.sourceRevision)
      #expect(try await firstStore.search("canonical timer source").map(\.id) == [noteID])

      let missingNoteTimer = NoteTimer(
        id: UUID(),
        noteID: UUID(),
        kind: .countdown,
        phase: .primary,
        state: .running,
        startedAt: startedAt,
        workDuration: .seconds(60)
      )
      do {
        try await firstStore.saveCurrentTimer(missingNoteTimer)
        Issue.record("Replacing the current timer with an unknown note must fail")
      } catch {
        #expect(try await firstStore.currentTimer() == timer)
      }

      try await firstStore.checkpoint()
      try await firstStore.close()

      let relaunchedStore = try workspace.makeStore()
      #expect(try await relaunchedStore.currentTimer() == timer)
      #expect(try await relaunchedStore.note(id: noteID)?.body == source)
      #expect(try await relaunchedStore.search("Focus block").map(\.id) == [noteID])
      try await relaunchedStore.deleteNote(id: noteID)
      #expect(try await relaunchedStore.currentTimer() == nil)
      #expect(try await relaunchedStore.search("canonical timer source").isEmpty)
      try await relaunchedStore.verifyIntegrity()
      try await relaunchedStore.close()
    }
  }

  @Test("PT-SEARCH-001: 10,000-note warm FTS first page stays under 50 ms p95")
  func warmSearchFirstPagePerformance() async throws {
    try await withWorkspace { workspace in
      let queue = try DatabaseQueue(path: workspace.databaseURL.path)
      try PersistenceSchema.migrate(queue)
      try await queue.write { db in
        for index in 0..<10_000 {
          let id = String(format: "00000000-0000-0000-0001-%012d", index)
          let body = "warmneedle indexed note \(index) with distinct context"
          try db.execute(
            sql: """
              INSERT INTO note (
                  id, body, created_at, modified_at, order_key, expires_at,
                  slot_index, selection_start, selection_length, scroll_offset,
                  source_revision
              ) VALUES (?, ?, ?, ?, ?, NULL, NULL, 0, 0, 0, 0)
              """,
            arguments: [id, body, Double(index), Double(index), index]
          )
          try db.execute(
            sql: "INSERT INTO note_fts (note_id, body) VALUES (?, ?)",
            arguments: [id, body]
          )
        }
        try db.execute(
          sql: "UPDATE metadata SET value = ? WHERE key = 'order_sequence'",
          arguments: [Data("10000".utf8)]
        )
      }

      let store = try workspace.makeStore()
      let warmPage = try await store.searchPage("warmneedle", limit: 50, offset: 0)
      #expect(warmPage.notes.count == 50)
      #expect(warmPage.hasMore)

      let clock = ContinuousClock()
      var samples: [Double] = []
      for _ in 0..<20 {
        let start = clock.now
        let page = try await store.searchPage("warmneedle", limit: 50, offset: 0)
        let duration = start.duration(to: clock.now)
        let components = duration.components
        let milliseconds =
          Double(components.seconds) * 1_000
          + Double(components.attoseconds) / 1_000_000_000_000_000
        samples.append(milliseconds)
        #expect(page.notes.count == 50)
      }
      samples.sort()
      let p95 = samples[18]
      print("PT-SEARCH-001 p95_ms=\(p95)")
      #expect(p95 < 50, "warm search p95 was \(p95) ms")
      try await store.close()
    }
  }

  @Test("IT-NOTE-004A: promoted order survives a clean relaunch")
  func promotedOrderSurvivesRelaunch() async throws {
    try await withWorkspace { workspace in
      let firstStore = try workspace.makeStore()
      let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
      let firstID = UUID()
      let secondID = UUID()
      let thirdID = UUID()

      _ = try await firstStore.createNote(id: firstID, body: "first", at: timestamp)
      _ = try await firstStore.createNote(id: secondID, body: "second", at: timestamp)
      _ = try await firstStore.createNote(id: thirdID, body: "third", at: timestamp)
      _ = try await firstStore.promoteNote(id: firstID, at: timestamp)
      let expected = try await firstStore.allNotes()
      #expect(expected.map(\.id) == [firstID, thirdID, secondID])
      try await firstStore.checkpoint()
      try await firstStore.close()

      let relaunchedStore = try workspace.makeStore()
      let relaunched = try await relaunchedStore.allNotes()
      #expect(relaunched.map(\.id) == expected.map(\.id))
      #expect(relaunched.map(\.orderKey) == expected.map(\.orderKey))
      #expect(Set(relaunched.map(\.orderKey)).count == relaunched.count)
      try await relaunchedStore.verifyIntegrity()
      try await relaunchedStore.close()
    }
  }

  @Test("IT-NOTE-004B: concurrent promotions remain unique and monotonic")
  func concurrentPromotionsRemainMonotonic() async throws {
    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      let ids = (0..<12).map { _ in UUID() }
      for (index, id) in ids.enumerated() {
        _ = try await store.createNote(id: id, body: "note-\(index)")
      }
      let initialMaximum = try await store.allNotes().map(\.orderKey).max() ?? 0

      try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<120 {
          group.addTask {
            _ = try await store.promoteNote(id: ids[index % ids.count])
          }
        }
        try await group.waitForAll()
      }

      let notes = try await store.allNotes()
      #expect(Set(notes.map(\.id)) == Set(ids))
      #expect(Set(notes.map(\.orderKey)).count == ids.count)
      #expect((notes.map(\.orderKey).max() ?? 0) >= initialMaximum + 120)
      try await store.verifyIntegrity()
      try await store.close()
    }
  }

  @Test("FAULT-DB-001: a flushed WAL edit is visible after an unclean-style reopen")
  func flushedEditSurvivesWALReopen() async throws {
    try await withWorkspace { workspace in
      let firstStore = try workspace.makeStore()
      let id = UUID()
      _ = try await firstStore.createNote(id: id, body: "last flushed edit")

      let reopenedStore = try workspace.makeStore()
      #expect(try await reopenedStore.note(id: id)?.body == "last flushed edit")
      try await reopenedStore.verifyIntegrity()
      try await reopenedStore.close()
      try await firstStore.close()
    }
  }

  @Test("FAULT-DB-003: failed save stays exportable in memory")
  func diskFullFailureRetainsDraft() async throws {
    enum Injected: Error { case diskFull }

    try await withWorkspace { workspace in
      let store = try workspace.makeStore(
        injector: PersistenceFaultInjector { point in
          if point == .beforeDatabaseWrite { throw Injected.diskFull }
        }
      )
      let saver = DebouncedNoteSaver(store: store, debounce: .milliseconds(10))
      let draft = NoteDraft(body: "export me after disk full")
      await saver.schedule(draft)
      try await Task.sleep(for: .milliseconds(80))

      #expect(await saver.lastFailure(noteID: draft.id) != nil)
      #expect(await saver.exportableDraft(noteID: draft.id) == draft)
      #expect(try await store.note(id: draft.id) == nil)
      await #expect(throws: Injected.self) {
        try await saver.flush(noteID: draft.id)
      }
      #expect(await saver.exportableDraft(noteID: draft.id)?.body == draft.body)
      try await store.close()
    }
  }

  @Test("Debounced save commits only the latest generation")
  func debounceCommitsLatestDraft() async throws {
    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      let saver = DebouncedNoteSaver(store: store, debounce: .milliseconds(20))
      let id = UUID()
      await saver.schedule(NoteDraft(id: id, body: "first"))
      await saver.schedule(NoteDraft(id: id, body: "second"))
      await saver.schedule(NoteDraft(id: id, body: "final"))
      try await Task.sleep(for: .milliseconds(120))

      #expect(try await store.note(id: id)?.body == "final")
      #expect(await saver.exportableDraft(noteID: id) == nil)
      try await store.close()
    }
  }

  @Test("IT-BACK-001A, IT-BACK-001H, IT-BACK-001I: online backup is valid and checksummed")
  func onlineBackupIsValid() async throws {
    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      _ = try await store.createNote(body: "backup identity")
      let backup = try await store.createBackup(at: Date(timeIntervalSince1970: 10))
      let validated = try await store.validateBackup(manifestURL: backup.manifestURL)

      #expect(validated.manifest.noteCount == 1)
      #expect(validated.manifest.schemaVersion == 2)
      #expect(validated.manifest.databaseSHA256.count == 64)
      #expect(validated.manifest.notesSHA256.count == 64)
      #expect(FileManager.default.fileExists(atPath: validated.databaseURL.path))
      #expect(!FileManager.default.fileExists(atPath: validated.databaseURL.path + "-wal"))
      #expect(!FileManager.default.fileExists(atPath: validated.databaseURL.path + "-shm"))
      var configuration = Configuration()
      configuration.readonly = true
      let backupQueue = try DatabaseQueue(
        path: validated.databaseURL.path,
        configuration: configuration
      )
      let journalMode = try await backupQueue.read { db in
        try String.fetchOne(db, sql: "PRAGMA journal_mode")
      }
      #expect(journalMode?.lowercased() == "delete")
      try backupQueue.close()
      try await store.close()
    }
  }

  @Test("IT-BACK-001B: every documented frequency and eligibility boundary")
  func backupFrequencyEligibility() async throws {
    #expect(BackupFrequency.allCases.count == 10)
    #expect(BackupFrequency.minutes10.interval == 600)
    #expect(BackupFrequency.minutes30.interval == 1_800)
    #expect(BackupFrequency.hour1.interval == 3_600)
    #expect(BackupFrequency.hours3.interval == 10_800)
    #expect(BackupFrequency.hours12.interval == 43_200)
    #expect(BackupFrequency.day1.interval == 86_400)
    #expect(BackupFrequency.days3.interval == 259_200)
    #expect(BackupFrequency.week1.interval == 604_800)
    #expect(BackupFrequency.month1.interval == 2_592_000)
    #expect(BackupFrequency.never.interval == nil)

    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      _ = try await store.createNote(body: "eligible")
      let start = Date(timeIntervalSince1970: 1_000)
      let policy = BackupPolicy(frequency: .minutes10)
      #expect(
        try await store.createBackupIfEligible(
          afterSuccessfulWriteAt: start,
          now: start,
          policy: policy
        ) != nil
      )
      #expect(
        try await store.createBackupIfEligible(
          afterSuccessfulWriteAt: start,
          now: start.addingTimeInterval(599),
          policy: policy
        ) == nil
      )
      #expect(
        try await store.createBackupIfEligible(
          afterSuccessfulWriteAt: start,
          now: start.addingTimeInterval(600),
          policy: policy
        ) != nil
      )
      #expect(
        try await store.createBackupIfEligible(
          afterSuccessfulWriteAt: start,
          now: start.addingTimeInterval(1_000),
          policy: BackupPolicy(frequency: .never)
        ) == nil
      )
      try await store.close()
    }
  }

  @Test("IT-BACK-001C, IT-BACK-001D: retention is bounded by count and age")
  func retentionCountAndAge() async throws {
    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      _ = try await store.createNote(body: "retention")
      let policy = BackupPolicy(
        frequency: .minutes10,
        retainedCopies: 2,
        maximumAge: 150
      )
      _ = try await store.createBackup(at: Date(timeIntervalSince1970: 100), policy: policy)
      _ = try await store.createBackup(at: Date(timeIntervalSince1970: 200), policy: policy)
      _ = try await store.createBackup(at: Date(timeIntervalSince1970: 300), policy: policy)

      let backups = try await store.availableBackups()
      #expect(
        backups.map(\.manifest.createdAt) == [
          Date(timeIntervalSince1970: 300),
          Date(timeIntervalSince1970: 200),
        ])
      try await store.close()
    }
  }

  @Test("SOAK-BACK-001: repeated backups remain valid across retention rollover")
  func backupRetentionRolloverSoak() async throws {
    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      _ = try await store.createNote(body: "soak source stays private")
      let policy = BackupPolicy(
        frequency: .minutes10,
        retainedCopies: 12,
        maximumAge: 60 * 60
      )

      for index in 0..<40 {
        _ = try await store.createBackup(
          at: Date(timeIntervalSince1970: TimeInterval(index * 600)),
          policy: policy
        )
      }

      let backups = try await store.availableBackups()
      #expect(backups.count == 7)
      #expect(backups.map(\.manifest.createdAt) == backups.map(\.manifest.createdAt).sorted(by: >))
      for backup in backups {
        _ = try await store.validateBackup(manifestURL: backup.manifestURL)
      }
      let files = try FileManager.default.contentsOfDirectory(
        at: workspace.backupDirectoryURL,
        includingPropertiesForKeys: nil
      )
      #expect(files.filter { $0.pathExtension == "json" }.count == 7)
      #expect(files.filter { $0.pathExtension == "sqlite" }.count == 7)
      try await store.close()
    }
  }

  @Test("FAULT-DB-002, IT-BACK-001E: interrupted temp backup is never published")
  func interruptedBackupCleansTemporaryFiles() async throws {
    enum Injected: Error { case interrupted }

    try await withWorkspace { workspace in
      let store = try workspace.makeStore(
        injector: PersistenceFaultInjector { point in
          if point == .afterBackupCopyBeforeFinalize { throw Injected.interrupted }
        }
      )
      _ = try await store.createNote(body: "source")
      await #expect(throws: Injected.self) {
        try await store.createBackup()
      }
      let files = try FileManager.default.contentsOfDirectory(
        at: workspace.backupDirectoryURL,
        includingPropertiesForKeys: nil
      )
      #expect(files.allSatisfy { !$0.lastPathComponent.hasPrefix("backup-") })
      #expect(files.allSatisfy { !$0.lastPathComponent.hasSuffix(".tmp") })
      try await store.close()
    }
  }

  @Test("IT-BACK-001G: backup and promotions serialize without FTS divergence")
  func backupAndWritesSerialize() async throws {
    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      let ids = try await (0..<20).asyncMap { index in
        try await store.createNote(body: "concurrent \(index)").id
      }

      async let backup = store.createBackup()
      async let promotions: Void = withThrowingTaskGroup(of: Void.self) { group in
        for id in ids {
          group.addTask { _ = try await store.promoteNote(id: id) }
        }
        try await group.waitForAll()
      }
      let descriptor = try await backup
      try await promotions
      _ = try await store.validateBackup(manifestURL: descriptor.manifestURL)
      try await store.verifyIntegrity()
      try await store.close()
    }
  }

  @Test("IT-BACK-002A, IT-BACK-002G: corrupt backup cannot replace a healthy store")
  func corruptBackupIsRejectedBeforeReplacement() async throws {
    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      let id = UUID()
      _ = try await store.createNote(id: id, body: "healthy before backup")
      let backup = try await store.createBackup()
      _ = try await store.updateNote(id: id, body: "healthy current store")

      let handle = try FileHandle(forWritingTo: backup.databaseURL)
      try handle.seekToEnd()
      try handle.write(contentsOf: Data([0xFF]))
      try handle.close()

      await #expect(throws: PersistenceStoreError.backupChecksumMismatch) {
        try await store.restoreBackup(
          manifestURL: backup.manifestURL,
          at: Date(timeIntervalSince1970: 500)
        )
      }
      #expect(try await store.note(id: id)?.body == "healthy current store")
      let reports = try recoveryReports(in: workspace.backupDirectoryURL)
      let report = try #require(reports.first)
      #expect(report.outcome == .rejected)
      #expect(report.failureCode == "backup_checksum_mismatch")
      #expect(report.emergencyManifestFileName.hasPrefix("emergency-"))
      #expect(report.requestedSchemaVersion == nil)
      let emergencyManifests = try FileManager.default.contentsOfDirectory(
        at: workspace.backupDirectoryURL,
        includingPropertiesForKeys: nil
      ).filter {
        $0.lastPathComponent.hasPrefix("emergency-") && $0.pathExtension == "json"
      }
      #expect(emergencyManifests.count == 1)
      try await store.verifyIntegrity()
      try await store.close()
    }
  }

  @Test("IT-NOTE-005, IT-BACK-002B, IT-BACK-002C, IT-BACK-002F: 100-note restore rehearsal")
  func hundredNoteRestoreRehearsal() async throws {
    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      var expected: [UUID: Note] = [:]
      for index in 0..<100 {
        let note = try await store.createNote(
          body: "known-\(index)-中文-\(String(repeating: "x", count: index % 11))"
        )
        expected[note.id] = note
      }
      let backup = try await store.createBackup()

      for (index, note) in expected.values.enumerated() {
        if index.isMultiple(of: 3) {
          try await store.deleteNote(id: note.id)
        } else if index.isMultiple(of: 2) {
          _ = try await store.updateNote(id: note.id, body: "mutated-\(index)")
        } else {
          _ = try await store.promoteNote(id: note.id)
        }
      }

      let restore = try await store.restoreBackup(manifestURL: backup.manifestURL)
      let restored = try await store.allNotes()
      #expect(Set(restored.map(\.id)) == Set(expected.keys))
      #expect(
        Dictionary(uniqueKeysWithValues: restored.map { ($0.id, $0.body) })
          == expected.mapValues(\.body))
      #expect(
        Dictionary(uniqueKeysWithValues: restored.map { ($0.id, $0.orderKey) })
          == expected.mapValues(\.orderKey))
      #expect(try await store.search("known").count == 100)
      #expect(restore.emergencyBackup.manifest.noteCount < 100)
      #expect(restore.recoveryReport.outcome == .restored)
      #expect(restore.recoveryReport.failureCode == nil)
      #expect(FileManager.default.fileExists(atPath: restore.recoveryReportURL.path))
      let reportBytes = try Data(contentsOf: restore.recoveryReportURL)
      let reportText = String(decoding: reportBytes, as: UTF8.self)
      #expect(!reportText.contains("known-"))
      #expect(!reportText.contains("mutated-"))
      try await store.verifyIntegrity()
      try await store.close()
    }
  }

  @Test("IT-BACK-002E: replacement failure rolls back to the pre-restore store")
  func failedRestoreRollsBack() async throws {
    enum Injected: Error { case afterReplacement }

    try await withWorkspace { workspace in
      let store = try workspace.makeStore(
        injector: PersistenceFaultInjector { point in
          if point == .afterStoreReplacement { throw Injected.afterReplacement }
        }
      )
      let id = UUID()
      _ = try await store.createNote(id: id, body: "backup version")
      let backup = try await store.createBackup()
      _ = try await store.updateNote(id: id, body: "pre-restore current version")

      do {
        _ = try await store.restoreBackup(manifestURL: backup.manifestURL)
        Issue.record("Restore should have injected a post-replacement failure")
      } catch let error as PersistenceStoreError {
        guard case .restoreRolledBack = error else {
          Issue.record("Unexpected restore error: \(error)")
          return
        }
      }

      #expect(try await store.note(id: id)?.body == "pre-restore current version")
      let report = try #require(try recoveryReports(in: workspace.backupDirectoryURL).first)
      #expect(report.outcome == .rolledBack)
      #expect(report.failureCode == "storage_operation_failed")
      #expect(report.emergencyManifestFileName.hasPrefix("emergency-"))
      try await store.verifyIntegrity()
      try await store.close()
    }
  }

  @Test("IT-BACK-002D, IT-BACK-002H: restore an old schema and migrate with FTS intact")
  func restoresAndMigratesInitialSchema() async throws {
    try await withWorkspace { workspace in
      let currentStore = try workspace.makeStore()
      _ = try await currentStore.createNote(body: "current store")

      let oldDatabaseURL = workspace.backupDirectoryURL.appendingPathComponent("backup-old.sqlite")
      let oldManifestURL = workspace.backupDirectoryURL.appendingPathComponent("backup-old.json")
      let oldQueue = try DatabaseQueue(path: oldDatabaseURL.path)
      try PersistenceSchema.migrateToInitialSchema(oldQueue)
      let oldID = UUID()
      try await oldQueue.write { db in
        try db.execute(
          sql: """
            INSERT INTO note (
                id, body, created_at, modified_at, order_key, selection_start,
                selection_length, scroll_offset
            ) VALUES (?, ?, 1, 1, 1, 0, 0, 0)
            """,
          arguments: [oldID.uuidString, "old schema 中文 search"]
        )
        try db.execute(
          sql: "INSERT INTO note_fts (note_id, body) VALUES (?, ?)",
          arguments: [oldID.uuidString, "old schema 中文 search"]
        )
        try db.execute(
          sql: "UPDATE metadata SET value = ? WHERE key = 'order_sequence'",
          arguments: [Data("1".utf8)]
        )
      }
      try oldQueue.close()

      let identity = try PersistenceStore.validateDatabaseFile(at: oldDatabaseURL)
      let manifest = BackupManifest(
        schemaVersion: identity.schemaVersion,
        createdAt: Date(timeIntervalSince1970: 1),
        databaseFileName: oldDatabaseURL.lastPathComponent,
        databaseSHA256: try PersistenceStore.sha256(ofFileAt: oldDatabaseURL),
        notesSHA256: identity.notesSHA256,
        noteCount: identity.noteCount
      )
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(manifest).write(to: oldManifestURL, options: .atomic)

      _ = try await currentStore.restoreBackup(manifestURL: oldManifestURL)
      #expect(try await currentStore.schemaVersion() == 2)
      #expect(try await currentStore.note(id: oldID)?.sourceRevision == 0)
      #expect(try await currentStore.search("中文").map(\.id) == [oldID])
      try await currentStore.verifyIntegrity()
      try await currentStore.close()
    }
  }

  @Test("IT-BACK-001L: explicit FTS divergence is detected")
  func detectsFTSDivergence() async throws {
    try await withWorkspace { workspace in
      let store = try workspace.makeStore()
      _ = try await store.createNote(body: "indexed")
      let queue = try DatabaseQueue(path: workspace.databaseURL.path)
      try await queue.write { db in
        try db.execute(sql: "DELETE FROM note_fts")
      }
      try queue.close()

      await #expect(throws: PersistenceStoreError.ftsIndexDiverged) {
        try await store.verifyIntegrity()
      }
      try await store.close()
    }
  }
}

private func recoveryReports(in directoryURL: URL) throws -> [BackupRecoveryReport] {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  return try FileManager.default.contentsOfDirectory(
    at: directoryURL,
    includingPropertiesForKeys: nil
  )
  .filter { $0.lastPathComponent.hasPrefix("recovery-") && $0.pathExtension == "json" }
  .map { try decoder.decode(BackupRecoveryReport.self, from: Data(contentsOf: $0)) }
}

private struct TestWorkspace {
  let rootURL: URL
  let databaseURL: URL
  let backupDirectoryURL: URL

  init() throws {
    rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("ForNowPersistenceTests-\(UUID().uuidString)")
    databaseURL = rootURL.appendingPathComponent("notes.sqlite")
    backupDirectoryURL = rootURL.appendingPathComponent("Backups", isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
  }

  func makeStore(injector: PersistenceFaultInjector = .none) throws -> PersistenceStore {
    try PersistenceStore(
      databaseURL: databaseURL,
      backupDirectoryURL: backupDirectoryURL,
      faultInjector: injector
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

private func withWorkspace(
  _ body: (TestWorkspace) async throws -> Void
) async throws {
  let workspace = try TestWorkspace()
  do {
    try await body(workspace)
    workspace.remove()
  } catch {
    workspace.remove()
    throw error
  }
}

extension Sequence {
  fileprivate func asyncMap<T: Sendable>(
    _ transform: (Element) async throws -> T
  ) async rethrows -> [T] {
    var result: [T] = []
    for element in self {
      result.append(try await transform(element))
    }
    return result
  }
}
