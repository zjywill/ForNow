import ForNowCore
import ForNowModes
import Foundation

public struct ExportDocumentBuilder: Sendable {
  private let projection = CleanExportProjection()

  public init() {}

  public func document(
    from note: Note,
    settings: ExportSettings,
    modeSettings: ModeSettings,
    exportedAt: Date
  ) -> ExportDocument {
    let cleanText = projection.text(
      from: note.body,
      policy: ExportProjectionPolicy(
        omitsModeHeader: settings.omitsKeywords,
        omitsChecklistTriggers: true,
        checklistTrigger: modeSettings.checklistTrigger,
        modeSettings: modeSettings
      )
    )
    let titleAndContent = titleAndContent(
      from: cleanText,
      usesFirstLineAsTitle: settings.usesFirstLineAsTitle
    )
    return ExportDocument(
      id: note.id,
      sourceRevision: note.sourceRevision,
      title: titleAndContent.title,
      content: titleAndContent.content,
      text: cleanText,
      createdAt: note.createdAt,
      modifiedAt: note.modifiedAt,
      exportedAt: exportedAt
    )
  }

  private func titleAndContent(
    from text: String,
    usesFirstLineAsTitle: Bool
  ) -> (title: String?, content: String) {
    guard usesFirstLineAsTitle, !text.isEmpty else {
      return (nil, text)
    }
    let source = text as NSString
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    source.getLineStart(
      &lineStart,
      end: &lineEnd,
      contentsEnd: &contentsEnd,
      for: NSRange(location: 0, length: 0)
    )
    let firstLine = source.substring(
      with: NSRange(location: lineStart, length: contentsEnd - lineStart)
    )
    let title = firstLine.trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty else { return (nil, text) }
    return (title, source.substring(from: lineEnd))
  }
}
