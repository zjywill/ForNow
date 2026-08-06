import Foundation

public struct TransientNote: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var body: String
  public let createdAt: Date

  public init(id: UUID, body: String = "", createdAt: Date) {
    self.id = id
    self.body = body
    self.createdAt = createdAt
  }
}

public enum MeaningfulContentState: Equatable, Sendable {
  case blank
  case provisionalMarkedText
  case meaningful
}

public struct MeaningfulContentPolicy: Equatable, Sendable {
  public static let standardModeAliases: Set<String> = [
    "average",
    "code",
    "count",
    "list",
    "math",
    "plain",
    "sum",
    "timer",
  ]

  public let modeAliases: Set<String>

  public init(modeAliases: Set<String> = standardModeAliases) {
    self.modeAliases = Set(modeAliases.map(Self.normalizeAlias))
  }

  public func classify(_ source: String, hasMarkedText: Bool) -> MeaningfulContentState {
    if hasMarkedText {
      return .provisionalMarkedText
    }

    let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSource.isEmpty else { return .blank }

    let lines = source.components(separatedBy: .newlines)
    guard let firstLine = lines.first else { return .blank }
    let header = modeHeader(in: firstLine)
    guard let header else { return .meaningful }

    if let title = header.title,
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return .meaningful
    }

    let remainingSource = lines.dropFirst().joined(separator: "\n")
    return remainingSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? .blank : .meaningful
  }

  private func modeHeader(in firstLine: String) -> (alias: String, title: String?)? {
    let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
    let components = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let alias = Self.normalizeAlias(String(components[0]))
    guard modeAliases.contains(alias) else { return nil }
    let title = components.count == 2 ? String(components[1]) : nil
    return (alias, title)
  }

  private static func normalizeAlias(_ alias: String) -> String {
    alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
