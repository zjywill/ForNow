import ForNowCore
import Foundation

public struct ExportFilenameSanitizer: Sendable {
  public static let maximumUTF8ByteCount = 180

  public init() {}

  public func filenameBase(for document: ExportDocument) -> String {
    sanitize(document.title ?? "")
  }

  public func sanitize(_ proposed: String) -> String {
    let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:\\"))
    let replaced = String(
      proposed.unicodeScalars.map { scalar in
        forbidden.contains(scalar) ? "-" : String(scalar)
      }.joined()
    )
    var result = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    while result.last == "." {
      result.removeLast()
      result = result.trimmingCharacters(in: .whitespaces)
    }
    var bounded = ""
    for character in result {
      let candidate = bounded + String(character)
      guard candidate.utf8.count <= Self.maximumUTF8ByteCount else { break }
      bounded = candidate
    }
    result = bounded
    while result.last == "." {
      result.removeLast()
    }
    return result.isEmpty ? "Untitled" : result
  }

  public func deduplicatedFilenames(
    for documents: [ExportDocument],
    extension filenameExtension: String
  ) -> [String] {
    var used: Set<String> = []
    return documents.map { document in
      let base = filenameBase(for: document)
      var candidate = base
      var suffix = 2
      while used.contains(collisionKey(candidate)) {
        candidate = "\(base) \(suffix)"
        suffix += 1
      }
      used.insert(collisionKey(candidate))
      return "\(candidate).\(filenameExtension)"
    }
  }

  private func collisionKey(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping.lowercased()
  }
}
