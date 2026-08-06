import Foundation

public enum QuickExportDestination: String, CaseIterable, Codable, Identifiable, Sendable {
  case plainText
  case markdown
  case obsidian
  case bear
  case appleNotes
  case customURL

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .plainText: "Plain Text"
    case .markdown: "Markdown"
    case .obsidian: "Obsidian"
    case .bear: "Bear"
    case .appleNotes: "Apple Notes"
    case .customURL: "Custom URL"
    }
  }
}

public struct ExportSettings: Codable, Equatable, Sendable {
  public static let currentVersion = 1
  public static let defaultAppleShortcutName = "ForNow Export to Apple Notes"

  public var version: Int
  public var quickDestination: QuickExportDestination
  public var omitsKeywords: Bool
  public var usesFirstLineAsTitle: Bool
  public var obsidianVault: String
  public var appleShortcutName: String
  public var customURLTemplate: String

  public init(
    version: Int = currentVersion,
    quickDestination: QuickExportDestination = .plainText,
    omitsKeywords: Bool = true,
    usesFirstLineAsTitle: Bool = true,
    obsidianVault: String = "",
    appleShortcutName: String = defaultAppleShortcutName,
    customURLTemplate: String = ""
  ) {
    self.version = version
    self.quickDestination = quickDestination
    self.omitsKeywords = omitsKeywords
    self.usesFirstLineAsTitle = usesFirstLineAsTitle
    self.obsidianVault = obsidianVault
    self.appleShortcutName = appleShortcutName
    self.customURLTemplate = customURLTemplate
    normalize()
  }

  public mutating func normalize() {
    obsidianVault = obsidianVault.trimmingCharacters(in: .whitespacesAndNewlines)
    appleShortcutName = appleShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
    if appleShortcutName.isEmpty {
      appleShortcutName = Self.defaultAppleShortcutName
    }
    customURLTemplate = customURLTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct ExportDocument: Equatable, Sendable, Identifiable {
  public let id: UUID
  public let sourceRevision: Int64
  public let title: String?
  public let content: String
  public let text: String
  public let createdAt: Date
  public let modifiedAt: Date
  public let exportedAt: Date

  public init(
    id: UUID,
    sourceRevision: Int64,
    title: String?,
    content: String,
    text: String,
    createdAt: Date,
    modifiedAt: Date,
    exportedAt: Date
  ) {
    self.id = id
    self.sourceRevision = sourceRevision
    self.title = title
    self.content = content
    self.text = text
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.exportedAt = exportedAt
  }
}

public enum ExportFileFormat: String, CaseIterable, Sendable {
  case plainText = "txt"
  case markdown = "md"

  public var filenameExtension: String { rawValue }
}

public enum ExportOverwritePolicy: Sendable {
  case failIfExists
  case replaceExisting
}

public enum ExportResource: Equatable, Sendable {
  case file(URL)
  case externalURL(URL)
}

public enum ExportDestinationIdentifier: Equatable, Sendable {
  case plainText
  case markdown
  case zip
  case obsidian
  case bear
  case appleNotes
  case customURL
}

public struct ExportReceipt: Equatable, Sendable {
  public let destination: ExportDestinationIdentifier
  public let resource: ExportResource
  public let exportedAt: Date
  public let documentCount: Int

  public init(
    destination: ExportDestinationIdentifier,
    resource: ExportResource,
    exportedAt: Date,
    documentCount: Int = 1
  ) {
    self.destination = destination
    self.resource = resource
    self.exportedAt = exportedAt
    self.documentCount = documentCount
  }
}

public protocol ExportDestination: Sendable {
  func export(_ document: ExportDocument) async throws -> ExportReceipt
}

public enum ExportError: Error, Equatable, Sendable {
  case emptyDocument
  case destinationExists(String)
  case destinationUnavailable(name: String, guidance: String)
  case invalidTemplate(String)
  case oversizedTemplate(maximumBytes: Int)
  case oversizedURL(maximumBytes: Int)
  case writeFailed(String)
  case openFailed(String)
}

extension ExportError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .emptyDocument:
      "There is no note content to export."
    case .destinationExists(let path):
      "A file already exists at \(path)."
    case .destinationUnavailable(let name, let guidance):
      "\(name) is unavailable. \(guidance)"
    case .invalidTemplate(let reason):
      "The custom URL template is invalid. \(reason)"
    case .oversizedTemplate(let maximumBytes):
      "The custom URL template exceeds \(maximumBytes) UTF-8 bytes."
    case .oversizedURL(let maximumBytes):
      "The rendered export URL exceeds \(maximumBytes) UTF-8 bytes."
    case .writeFailed(let reason):
      "The export could not be written. \(reason)"
    case .openFailed(let name):
      "\(name) could not be opened."
    }
  }
}

public enum ExportAvailabilityStatus: Equatable, Sendable {
  case available
  case requiresConfiguration
  case unavailable
}

public struct ExportDestinationDiagnostic: Equatable, Sendable {
  public let status: ExportAvailabilityStatus
  public let message: String

  public init(status: ExportAvailabilityStatus, message: String) {
    self.status = status
    self.message = message
  }
}
