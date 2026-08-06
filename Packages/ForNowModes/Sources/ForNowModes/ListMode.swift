import Foundation

public struct ListModeItem: Sendable, Equatable {
  public let lineRange: NSRange
  public let markerRange: NSRange?

  public var isChecked: Bool {
    markerRange != nil
  }

  public init(lineRange: NSRange, markerRange: NSRange?) {
    self.lineRange = lineRange
    self.markerRange = markerRange
  }
}

public struct ListModeParser: Sendable {
  private let settings: ModeSettings

  public init(settings: ModeSettings = ModeSettings()) {
    self.settings = settings
  }

  public func parse(in source: String) -> [ListModeItem] {
    guard
      (try? ModeAliasRegistry(settings: settings)) != nil,
      let header = ModeHeaderParser(settings: settings).parse(in: source),
      header.modeID == .list,
      header.bodyRange.length > 0
    else { return [] }

    let nsSource = source as NSString
    var items: [ListModeItem] = []
    var location = header.bodyRange.location
    while location < NSMaxRange(header.bodyRange) {
      var lineStart = 0
      var lineEnd = 0
      var contentsEnd = 0
      nsSource.getLineStart(
        &lineStart,
        end: &lineEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0)
      )
      let contentsRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
      let markerRange = checkedMarkerRange(in: contentsRange, source: source)
      let itemContentEnd = markerRange?.location ?? contentsEnd
      let itemContentRange = NSRange(
        location: lineStart,
        length: max(0, itemContentEnd - lineStart)
      )
      let itemContent = nsSource.substring(with: itemContentRange)
      let trimmed = itemContent.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty, !isComment(trimmed), !isHeading(trimmed) {
        items.append(ListModeItem(lineRange: contentsRange, markerRange: markerRange))
      }
      let nextLocation = min(lineEnd, NSMaxRange(header.bodyRange))
      location = nextLocation > location ? nextLocation : location + 1
    }
    return items
  }

  private func checkedMarkerRange(in lineRange: NSRange, source: String) -> NSRange? {
    let escapedTrigger = NSRegularExpression.escapedPattern(for: settings.checklistTrigger)
    guard
      let expression = try? NSRegularExpression(
        pattern: #"[\t ]+"# + escapedTrigger + #"[\t ]*$"#
      ),
      let match = expression.firstMatch(in: source, range: lineRange),
      NSMaxRange(match.range) == NSMaxRange(lineRange)
    else { return nil }
    return match.range
  }

  private func isComment(_ line: String) -> Bool {
    line.hasPrefix("//")
  }

  private func isHeading(_ line: String) -> Bool {
    let hashes = line.prefix(while: { $0 == "#" })
    guard (1...3).contains(hashes.count) else { return false }
    let remainder = line.dropFirst(hashes.count)
    return remainder.isEmpty || remainder.first?.isWhitespace == true
  }
}

public struct ListModeTogglePlan: Sendable, Equatable {
  public let expectedSource: String
  public let replacementRange: NSRange
  public let replacement: String
  public let selectionAfterEdit: NSRange

  public init(
    expectedSource: String,
    replacementRange: NSRange,
    replacement: String,
    selectionAfterEdit: NSRange
  ) {
    self.expectedSource = expectedSource
    self.replacementRange = replacementRange
    self.replacement = replacement
    self.selectionAfterEdit = selectionAfterEdit
  }
}

public struct ListModeTogglePlanner: Sendable {
  public init() {}

  public func plan(
    in source: String,
    itemRange: NSRange,
    selection: NSRange,
    settings: ModeSettings = ModeSettings()
  ) -> ListModeTogglePlan? {
    let sourceLength = source.utf16.count
    guard itemRange.location >= 0, NSMaxRange(itemRange) <= sourceLength,
      selection.location >= 0, NSMaxRange(selection) <= sourceLength,
      let item = ListModeParser(settings: settings).parse(in: source).first(where: {
        $0.lineRange == itemRange
      })
    else { return nil }

    let replacementRange: NSRange
    let replacement: String
    if let markerRange = item.markerRange {
      replacementRange = markerRange
      replacement = ""
    } else {
      replacementRange = NSRange(location: NSMaxRange(item.lineRange), length: 0)
      replacement = " \(settings.checklistTrigger)"
    }
    return ListModeTogglePlan(
      expectedSource: source,
      replacementRange: replacementRange,
      replacement: replacement,
      selectionAfterEdit: map(selection, across: replacementRange, replacement: replacement)
    )
  }

  private func map(_ selection: NSRange, across edit: NSRange, replacement: String) -> NSRange {
    let start = map(selection.location, across: edit, replacement: replacement)
    let end = map(NSMaxRange(selection), across: edit, replacement: replacement)
    return NSRange(location: start, length: max(0, end - start))
  }

  private func map(_ offset: Int, across edit: NSRange, replacement: String) -> Int {
    if edit.length == 0 {
      return offset <= edit.location ? offset : offset + replacement.utf16.count
    }
    if offset <= edit.location {
      return offset
    }
    if offset >= NSMaxRange(edit) {
      return offset + replacement.utf16.count - edit.length
    }
    return edit.location + replacement.utf16.count
  }
}
