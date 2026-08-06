import AppKit
import ForNowCore
import ForNowIntegrations
import Foundation
import UniformTypeIdentifiers

struct ExportFileSelection: Equatable {
  let url: URL
  let overwritePolicy: ExportOverwritePolicy
}

@MainActor
protocol ExportFileChoosing {
  func chooseFile(
    suggestedFilenameBase: String,
    format: ExportFileFormat
  ) async -> ExportFileSelection?
  func chooseArchive(suggestedFilenameBase: String) async -> ExportFileSelection?
}

@MainActor
struct SystemExportFileChooser: ExportFileChoosing {
  func chooseFile(
    suggestedFilenameBase: String,
    format: ExportFileFormat
  ) async -> ExportFileSelection? {
    let contentType: UTType =
      format == .plainText ? .plainText : UTType(filenameExtension: "md") ?? .plainText
    return await choose(
      suggestedFilename: "\(suggestedFilenameBase).\(format.filenameExtension)",
      contentType: contentType
    )
  }

  func chooseArchive(suggestedFilenameBase: String) async -> ExportFileSelection? {
    await choose(
      suggestedFilename: "\(suggestedFilenameBase).zip",
      contentType: .zip
    )
  }

  private func choose(
    suggestedFilename: String,
    contentType: UTType
  ) async -> ExportFileSelection? {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.allowsOtherFileTypes = false
    panel.allowedContentTypes = [contentType]
    panel.nameFieldStringValue = suggestedFilename
    let response = await withCheckedContinuation { continuation in
      panel.begin { response in
        continuation.resume(returning: response)
      }
    }
    guard response == .OK, let url = panel.url else { return nil }
    let overwritePolicy: ExportOverwritePolicy =
      FileManager.default.fileExists(atPath: url.path) ? .replaceExisting : .failIfExists
    return ExportFileSelection(url: url, overwritePolicy: overwritePolicy)
  }
}

@MainActor
struct CancelledExportFileChooser: ExportFileChoosing {
  func chooseFile(
    suggestedFilenameBase: String,
    format: ExportFileFormat
  ) async -> ExportFileSelection? {
    nil
  }

  func chooseArchive(suggestedFilenameBase: String) async -> ExportFileSelection? {
    nil
  }
}

struct UnavailableExternalURLOpener: ExternalURLOpening {
  func isAvailable(for url: URL) async -> Bool { false }
  func open(_ url: URL) async -> Bool { false }
}
