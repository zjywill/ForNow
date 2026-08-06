import ForNowModes
import Foundation

public struct ProjectionEditingSession: Sendable {
  public private(set) var snapshot: SourceSnapshot
  public private(set) var projection: EditorProjection

  private let parser: SpikeProjectionParser
  private let modeSettings: ModeSettings
  private var undoSnapshots: [SourceSnapshot] = []
  private var redoSnapshots: [SourceSnapshot] = []

  public init(
    text: String,
    modeSettings: ModeSettings = ModeSettings(),
    mathSettings: MathSettings = MathSettings()
  ) {
    let parser = SpikeProjectionParser(
      modeSettings: modeSettings,
      mathSettings: mathSettings
    )
    let snapshot = SourceSnapshot(version: 0, text: text)
    self.snapshot = snapshot
    projection = parser.parse(snapshot)
    self.parser = parser
    self.modeSettings = modeSettings
  }

  public mutating func replace(_ edit: SourceEdit) throws {
    let previous = snapshot
    snapshot = try snapshot.applying(edit)
    undoSnapshots.append(previous)
    redoSnapshots.removeAll(keepingCapacity: true)
    projection = parser.parse(snapshot)
  }

  public mutating func toggleCheckbox(at offset: SourceOffset) throws {
    guard
      let checkbox = projection.decorations.first(where: { decoration in
        guard case .checkbox(let range, _, _) = decoration else { return false }
        return range.contains(offset)
      }),
      case .checkbox(let range, _, _) = checkbox,
      let plan = ListModeTogglePlanner().plan(
        in: snapshot.text,
        itemRange: range.nsRange,
        selection: NSRange(location: offset.utf16Offset, length: 0),
        settings: modeSettings
      )
    else { return }
    try replace(
      SourceEdit(
        range: SourceRange(plan.replacementRange),
        replacement: plan.replacement
      )
    )
  }

  @discardableResult
  public mutating func undo() -> Bool {
    guard let previous = undoSnapshots.popLast() else { return false }
    redoSnapshots.append(snapshot)
    snapshot = SourceSnapshot(version: snapshot.version + 1, text: previous.text)
    projection = parser.parse(snapshot)
    return true
  }

  @discardableResult
  public mutating func redo() -> Bool {
    guard let next = redoSnapshots.popLast() else { return false }
    undoSnapshots.append(snapshot)
    snapshot = SourceSnapshot(version: snapshot.version + 1, text: next.text)
    projection = parser.parse(snapshot)
    return true
  }
}
