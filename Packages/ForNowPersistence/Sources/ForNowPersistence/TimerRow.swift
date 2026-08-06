import ForNowCore
import Foundation
import GRDB

struct TimerRow: Sendable {
  let id: String
  let noteID: String
  let kind: String
  let title: String?
  let phase: String
  let state: String
  let startedAt: Double?
  let accumulatedSeconds: Double
  let workSeconds: Double?
  let restSeconds: Double?

  init(row: Row) {
    id = row["id"]
    noteID = row["note_id"]
    kind = row["kind"]
    title = row["title"]
    phase = row["phase"]
    state = row["state"]
    startedAt = row["started_at"]
    accumulatedSeconds = row["accumulated_seconds"]
    workSeconds = row["work_seconds"]
    restSeconds = row["rest_seconds"]
  }

  func timer() throws -> NoteTimer {
    guard let id = UUID(uuidString: id), let noteID = UUID(uuidString: noteID),
      let kind = TimerKind(rawValue: kind),
      let phase = TimerPhase(rawValue: phase),
      let state = TimerState(rawValue: state),
      accumulatedSeconds.isFinite,
      accumulatedSeconds >= 0,
      workSeconds.map({ $0.isFinite && $0 > 0 }) != false,
      restSeconds.map({ $0.isFinite && $0 > 0 }) != false
    else {
      throw PersistenceStoreError.invalidStoredTimer
    }
    return NoteTimer(
      id: id,
      noteID: noteID,
      kind: kind,
      title: title,
      phase: phase,
      state: state,
      startedAt: startedAt.map(Date.init(timeIntervalSince1970:)),
      accumulated: TimerDuration.duration(seconds: accumulatedSeconds),
      workDuration: workSeconds.map(TimerDuration.duration(seconds:)),
      restDuration: restSeconds.map(TimerDuration.duration(seconds:))
    )
  }
}
