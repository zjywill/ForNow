import Foundation

public struct SourceOffset: Sendable, Hashable, Comparable {
  public let utf16Offset: Int

  public init(utf16Offset: Int) {
    self.utf16Offset = max(0, utf16Offset)
  }

  public static func < (lhs: SourceOffset, rhs: SourceOffset) -> Bool {
    lhs.utf16Offset < rhs.utf16Offset
  }
}

public struct SourceRange: Sendable, Hashable {
  public let location: SourceOffset
  public let length: Int

  public init(location: SourceOffset, length: Int) {
    self.location = location
    self.length = max(0, length)
  }

  public init(_ range: NSRange) {
    self.init(location: SourceOffset(utf16Offset: range.location), length: range.length)
  }

  public var nsRange: NSRange {
    NSRange(location: location.utf16Offset, length: length)
  }

  public var upperBound: Int {
    location.utf16Offset + length
  }

  public func contains(_ offset: SourceOffset) -> Bool {
    location.utf16Offset <= offset.utf16Offset && offset.utf16Offset < upperBound
  }
}

public struct SourceSelection: Sendable, Hashable {
  public let range: SourceRange

  public init(range: SourceRange) {
    self.range = range
  }
}

public struct SourceEdit: Sendable, Equatable {
  public let range: SourceRange
  public let replacement: String

  public init(range: SourceRange, replacement: String) {
    self.range = range
    self.replacement = replacement
  }
}

public enum SourceEditError: Error, Equatable {
  case invalidRange(SourceRange)
}

public struct SourceSnapshot: Sendable, Equatable {
  public let version: UInt64
  public let text: String
  public let changedRange: SourceRange?

  public init(version: UInt64, text: String, changedRange: SourceRange? = nil) {
    self.version = version
    self.text = text
    self.changedRange = changedRange
  }

  public var utf16Count: Int {
    text.utf16.count
  }

  public func contains(_ range: SourceRange) -> Bool {
    range.location.utf16Offset >= 0 && range.upperBound <= utf16Count
  }

  public func substring(in range: SourceRange) -> String? {
    guard contains(range), let swiftRange = Range(range.nsRange, in: text) else {
      return nil
    }
    return String(text[swiftRange])
  }

  public func applying(_ edit: SourceEdit) throws -> SourceSnapshot {
    guard contains(edit.range), Range(edit.range.nsRange, in: text) != nil else {
      throw SourceEditError.invalidRange(edit.range)
    }
    let updated = (text as NSString).replacingCharacters(
      in: edit.range.nsRange,
      with: edit.replacement
    )
    let changedRange = SourceRange(
      location: edit.range.location,
      length: edit.replacement.utf16.count
    )
    return SourceSnapshot(version: version + 1, text: updated, changedRange: changedRange)
  }

  public func clamped(_ selection: SourceSelection) -> SourceSelection {
    let location = min(selection.range.location.utf16Offset, utf16Count)
    let length = min(selection.range.length, utf16Count - location)
    return SourceSelection(
      range: SourceRange(location: SourceOffset(utf16Offset: location), length: length)
    )
  }
}
