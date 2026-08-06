import Foundation
import GRDB

enum PersistenceSchema {
  static let initialMigration = "v1_initial"
  static let sourceRevisionMigration = "v2_source_revision"
  static let currentVersion = 2

  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()

    migrator.registerMigration(initialMigration) { db in
      try db.execute(
        sql: """
          CREATE TABLE note (
              id TEXT PRIMARY KEY NOT NULL,
              body TEXT NOT NULL,
              created_at REAL NOT NULL,
              modified_at REAL NOT NULL,
              order_key INTEGER NOT NULL UNIQUE,
              expires_at REAL,
              slot_index INTEGER UNIQUE,
              selection_start INTEGER,
              selection_length INTEGER,
              scroll_offset INTEGER
          )
          """
      )
      try db.execute(sql: "CREATE INDEX note_modified_at_idx ON note(modified_at)")
      try db.execute(sql: "CREATE INDEX note_expires_at_idx ON note(expires_at)")
      try db.execute(
        sql: """
          CREATE VIRTUAL TABLE note_fts USING fts5(
              note_id UNINDEXED,
              body,
              tokenize = 'unicode61'
          )
          """
      )
      try db.execute(
        sql: """
          CREATE TABLE timer (
              id TEXT PRIMARY KEY NOT NULL,
              note_id TEXT NOT NULL REFERENCES note(id) ON DELETE CASCADE,
              kind TEXT NOT NULL,
              title TEXT,
              phase TEXT NOT NULL,
              state TEXT NOT NULL,
              started_at REAL,
              accumulated_seconds REAL NOT NULL,
              work_seconds REAL,
              rest_seconds REAL
          )
          """
      )
      try db.execute(
        sql: """
          CREATE TABLE metadata (
              key TEXT PRIMARY KEY NOT NULL,
              value BLOB NOT NULL
          )
          """
      )
      try db.execute(
        sql: "INSERT INTO metadata (key, value) VALUES ('order_sequence', ?)",
        arguments: [Data("0".utf8)]
      )
    }

    migrator.registerMigration(sourceRevisionMigration) { db in
      try db.execute(
        sql: "ALTER TABLE note ADD COLUMN source_revision INTEGER NOT NULL DEFAULT 0"
      )
    }

    return migrator
  }

  static func migrate(_ writer: any DatabaseWriter) throws {
    try migrator.migrate(writer)
  }

  static func migrateToInitialSchema(_ writer: any DatabaseWriter) throws {
    try migrator.migrate(writer, upTo: initialMigration)
  }

  static func version(in db: Database) throws -> Int {
    try migrator.appliedMigrations(db).count
  }
}
