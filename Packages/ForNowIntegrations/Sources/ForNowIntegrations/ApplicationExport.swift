import AppKit
import ForNowCore
import Foundation

public protocol ExternalURLOpening: Sendable {
  func isAvailable(for url: URL) async -> Bool
  func open(_ url: URL) async -> Bool
}

public struct SystemExternalURLOpener: ExternalURLOpening, Sendable {
  public init() {}

  public func isAvailable(for url: URL) async -> Bool {
    await MainActor.run {
      NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }
  }

  public func open(_ url: URL) async -> Bool {
    await MainActor.run {
      NSWorkspace.shared.open(url)
    }
  }
}

public enum ApplicationExportURLBuilder {
  public static func obsidian(
    document: ExportDocument,
    vault: String
  ) throws -> URL {
    var components = URLComponents()
    components.scheme = "obsidian"
    components.host = "new"
    var queryItems: [URLQueryItem] = []
    if !vault.isEmpty {
      queryItems.append(URLQueryItem(name: "vault", value: vault))
    }
    if let title = document.title {
      queryItems.append(URLQueryItem(name: "name", value: title))
    }
    queryItems.append(URLQueryItem(name: "content", value: document.content))
    try StrictURLQueryEncoder.apply(queryItems, to: &components)
    return try url(from: components, destination: "Obsidian")
  }

  public static func bear(document: ExportDocument) throws -> URL {
    var components = URLComponents()
    components.scheme = "bear"
    components.host = "x-callback-url"
    components.path = "/create"
    var queryItems: [URLQueryItem] = []
    if let title = document.title {
      queryItems.append(URLQueryItem(name: "title", value: title))
    }
    queryItems.append(URLQueryItem(name: "text", value: document.content))
    try StrictURLQueryEncoder.apply(queryItems, to: &components)
    return try url(from: components, destination: "Bear")
  }

  public static func appleShortcut(
    document: ExportDocument,
    shortcutName: String
  ) throws -> URL {
    var components = URLComponents()
    components.scheme = "shortcuts"
    components.host = "run-shortcut"
    try StrictURLQueryEncoder.apply(
      [
        URLQueryItem(name: "name", value: shortcutName),
        URLQueryItem(name: "input", value: "text"),
        URLQueryItem(name: "text", value: document.text),
      ],
      to: &components
    )
    return try url(from: components, destination: "Apple Shortcuts")
  }

  private static func url(from components: URLComponents, destination: String) throws -> URL {
    guard let url = components.url else {
      throw ExportError.invalidTemplate("A \(destination) URL could not be constructed.")
    }
    return url
  }
}

public struct ObsidianExportDestination: ExportDestination, Sendable {
  private let vault: String
  private let opener: any ExternalURLOpening

  public init(vault: String, opener: any ExternalURLOpening) {
    self.vault = vault
    self.opener = opener
  }

  public func export(_ document: ExportDocument) async throws -> ExportReceipt {
    let url = try ApplicationExportURLBuilder.obsidian(document: document, vault: vault)
    return try await open(
      url,
      name: "Obsidian",
      guidance: "Install Obsidian or choose another Quick Export destination.",
      destination: .obsidian,
      document: document,
      opener: opener
    )
  }
}

public struct BearExportDestination: ExportDestination, Sendable {
  private let opener: any ExternalURLOpening

  public init(opener: any ExternalURLOpening) {
    self.opener = opener
  }

  public func export(_ document: ExportDocument) async throws -> ExportReceipt {
    let url = try ApplicationExportURLBuilder.bear(document: document)
    return try await open(
      url,
      name: "Bear",
      guidance: "Install Bear or choose another Quick Export destination.",
      destination: .bear,
      document: document,
      opener: opener
    )
  }
}

public struct AppleShortcutExportDestination: ExportDestination, Sendable {
  private let shortcutName: String
  private let opener: any ExternalURLOpening

  public init(shortcutName: String, opener: any ExternalURLOpening) {
    self.shortcutName = shortcutName
    self.opener = opener
  }

  public func export(_ document: ExportDocument) async throws -> ExportReceipt {
    let url = try ApplicationExportURLBuilder.appleShortcut(
      document: document,
      shortcutName: shortcutName
    )
    return try await open(
      url,
      name: "Apple Shortcuts",
      guidance: "Create the configured shortcut or choose another Quick Export destination.",
      destination: .appleNotes,
      document: document,
      opener: opener
    )
  }
}

private func open(
  _ url: URL,
  name: String,
  guidance: String,
  destination: ExportDestinationIdentifier,
  document: ExportDocument,
  opener: any ExternalURLOpening
) async throws -> ExportReceipt {
  guard await opener.isAvailable(for: url) else {
    throw ExportError.destinationUnavailable(name: name, guidance: guidance)
  }
  guard await opener.open(url) else { throw ExportError.openFailed(name) }
  return ExportReceipt(
    destination: destination,
    resource: .externalURL(url),
    exportedAt: document.exportedAt
  )
}
