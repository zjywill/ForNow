import ForNowCore
import Foundation
import ZIPFoundation

struct AtomicExportCommitter: Sendable {
  func write(
    _ data: Data,
    to destinationURL: URL,
    overwritePolicy: ExportOverwritePolicy
  ) throws {
    let temporaryURL = makeTemporaryURL(beside: destinationURL)
    do {
      try data.write(to: temporaryURL, options: .atomic)
      try commit(
        temporaryURL,
        to: destinationURL,
        overwritePolicy: overwritePolicy
      )
    } catch {
      try? FileManager.default.removeItem(at: temporaryURL)
      throw map(error, destinationURL: destinationURL)
    }
  }

  func commit(
    _ temporaryURL: URL,
    to destinationURL: URL,
    overwritePolicy: ExportOverwritePolicy
  ) throws {
    let fileManager = FileManager.default
    do {
      switch overwritePolicy {
      case .failIfExists:
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
      case .replaceExisting:
        if fileManager.fileExists(atPath: destinationURL.path) {
          _ = try fileManager.replaceItemAt(
            destinationURL,
            withItemAt: temporaryURL,
            backupItemName: nil,
            options: []
          )
        } else {
          try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
      }
    } catch {
      throw map(error, destinationURL: destinationURL)
    }
  }

  func makeTemporaryURL(beside destinationURL: URL) -> URL {
    destinationURL.deletingLastPathComponent().appendingPathComponent(
      ".\(destinationURL.lastPathComponent).fornow-\(UUID().uuidString).tmp",
      isDirectory: false
    )
  }

  private func map(_ error: Error, destinationURL: URL) -> ExportError {
    if let exportError = error as? ExportError {
      return exportError
    }
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain,
      nsError.code == CocoaError.fileWriteFileExists.rawValue
    {
      return .destinationExists(destinationURL.path)
    }
    return .writeFailed(error.localizedDescription)
  }
}

public struct FileExportDestination: ExportDestination, Sendable {
  public let destinationURL: URL
  public let format: ExportFileFormat
  public let overwritePolicy: ExportOverwritePolicy

  public init(
    destinationURL: URL,
    format: ExportFileFormat,
    overwritePolicy: ExportOverwritePolicy = .failIfExists
  ) {
    self.destinationURL = destinationURL
    self.format = format
    self.overwritePolicy = overwritePolicy
  }

  public func export(_ document: ExportDocument) async throws -> ExportReceipt {
    guard !document.text.isEmpty else { throw ExportError.emptyDocument }
    guard let data = document.text.data(using: .utf8) else {
      throw ExportError.writeFailed("The document could not be represented as UTF-8.")
    }
    try AtomicExportCommitter().write(
      data,
      to: destinationURL,
      overwritePolicy: overwritePolicy
    )
    return ExportReceipt(
      destination: format == .plainText ? .plainText : .markdown,
      resource: .file(destinationURL),
      exportedAt: document.exportedAt
    )
  }
}

public struct ZIPExportDestination: Sendable {
  public let destinationURL: URL
  public let overwritePolicy: ExportOverwritePolicy

  public init(
    destinationURL: URL,
    overwritePolicy: ExportOverwritePolicy = .failIfExists
  ) {
    self.destinationURL = destinationURL
    self.overwritePolicy = overwritePolicy
  }

  public func export(_ documents: [ExportDocument]) async throws -> ExportReceipt {
    guard !documents.isEmpty else { throw ExportError.emptyDocument }
    let committer = AtomicExportCommitter()
    let temporaryURL = committer.makeTemporaryURL(beside: destinationURL)
    do {
      try createArchive(at: temporaryURL, documents: documents)
      try committer.commit(
        temporaryURL,
        to: destinationURL,
        overwritePolicy: overwritePolicy
      )
    } catch let error as ExportError {
      try? FileManager.default.removeItem(at: temporaryURL)
      throw error
    } catch {
      try? FileManager.default.removeItem(at: temporaryURL)
      throw ExportError.writeFailed(error.localizedDescription)
    }
    return ExportReceipt(
      destination: .zip,
      resource: .file(destinationURL),
      exportedAt: documents.map(\.exportedAt).max() ?? Date(),
      documentCount: documents.count
    )
  }

  private func createArchive(at url: URL, documents: [ExportDocument]) throws {
    let archive = try Archive(url: url, accessMode: .create)
    let names = ExportFilenameSanitizer().deduplicatedFilenames(
      for: documents,
      extension: ExportFileFormat.plainText.filenameExtension
    )
    for (document, name) in zip(documents, names) {
      let data = Data(document.text.utf8)
      try archive.addEntry(
        with: name,
        type: .file,
        uncompressedSize: Int64(data.count),
        modificationDate: document.modifiedAt,
        compressionMethod: .deflate
      ) { position, size in
        let start = Int(position)
        guard start < data.count else { return Data() }
        let end = min(data.count, start + size)
        return data.subdata(in: start..<end)
      }
    }
  }
}
