import Foundation

public typealias ParsedMode = ModeID

public struct ParsedSource: Codable, Equatable, Sendable {
  public let version: Int64
  public let utf16Length: Int
  public let mode: ParsedMode

  public init(version: Int64, utf16Length: Int, mode: ParsedMode) {
    self.version = version
    self.utf16Length = utf16Length
    self.mode = mode
  }
}

public protocol SourceParsing: Sendable {
  func parse(source: String, version: Int64) async -> ParsedSource
}

public struct PlainSourceParser: SourceParsing {
  private let modeSettings: ModeSettings

  public init(modeSettings: ModeSettings = ModeSettings()) {
    self.modeSettings = modeSettings
  }

  public func parse(source: String, version: Int64) async -> ParsedSource {
    ParsedSource(
      version: version,
      utf16Length: source.utf16.count,
      mode: ModeHeaderParser(settings: modeSettings).parse(in: source)?.modeID ?? .plain
    )
  }
}
