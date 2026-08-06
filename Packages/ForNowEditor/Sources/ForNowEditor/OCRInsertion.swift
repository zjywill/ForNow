import AppKit
import ForNowCore
import UniformTypeIdentifiers

public enum EditorOCRInputSource: String, Sendable, Equatable {
  case paste
  case dragAndDrop
}

public enum EditorOCRImageInput: Sendable, Equatable {
  case encodedData(Data, contentTypeIdentifier: String?)
  case file(URL, contentTypeIdentifier: String?)
}

public struct EditorOCRInsertionAnchor: Sendable, Equatable {
  public let sourceVersion: UInt64
  public let replacementRange: SourceRange

  public init(sourceVersion: UInt64, replacementRange: SourceRange) {
    self.sourceVersion = sourceVersion
    self.replacementRange = replacementRange
  }
}

public struct EditorOCRRequest: Sendable, Equatable {
  public let image: EditorOCRImageInput
  public let source: EditorOCRInputSource
  public let anchor: EditorOCRInsertionAnchor

  public init(
    image: EditorOCRImageInput,
    source: EditorOCRInputSource,
    anchor: EditorOCRInsertionAnchor
  ) {
    self.image = image
    self.source = source
    self.anchor = anchor
  }
}

public enum EditorOCRCaptureError: Error, Equatable, LocalizedError, Sendable {
  case unreadableImage

  public var errorDescription: String? {
    "The image could not be read from the clipboard or drop."
  }
}

public enum EditorOCRInsertionOutcome: Sendable, Equatable {
  case inserted
  case sourceChanged
  case editorUnavailable
}

@MainActor
public final class EditorOCRTarget: Sendable {
  public var requestHandler: (@MainActor (EditorOCRRequest) -> Void)?
  public var captureErrorHandler: (@MainActor (EditorOCRCaptureError) -> Void)?

  private weak var container: ProjectionEditorContainer?

  public init() {}

  public func attach(to container: ProjectionEditorContainer) {
    guard self.container !== container else { return }
    self.container?.detachOCRTarget(self)
    self.container = container
    container.attachOCRTarget(self)
  }

  public func insertRecognizedText(
    _ text: String,
    at anchor: EditorOCRInsertionAnchor
  ) -> EditorOCRInsertionOutcome {
    container?.performOCRInsertion(text, at: anchor) ?? .editorUnavailable
  }

  public func insertRecognizedTextAtCurrentSelection(_ text: String) -> Bool {
    container?.performOCRInsertionAtCurrentSelection(text) ?? false
  }

  func submit(_ request: EditorOCRRequest) {
    requestHandler?(request)
  }

  func failCapture(with error: EditorOCRCaptureError) {
    captureErrorHandler?(error)
  }
}

@MainActor
struct EditorOCRPasteboardReader {
  private static let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
  private static let gifType = NSPasteboard.PasteboardType(UTType.gif.identifier)

  static let registeredTypes: [NSPasteboard.PasteboardType] = [
    .png,
    jpegType,
    gifType,
    .tiff,
    .fileURL,
  ]

  func hasImageCandidate(in pasteboard: NSPasteboard) -> Bool {
    pasteboard.pasteboardItems?.contains(where: hasImageCandidate(in:)) == true
      || pasteboard.types?.contains(where: isImagePasteboardType) == true
  }

  func imageInput(from pasteboard: NSPasteboard) throws -> EditorOCRImageInput? {
    if let item = pasteboard.pasteboardItems?.first(where: hasImageCandidate(in:)) {
      if let fileURL = fileURL(from: item) {
        let type = UTType(filenameExtension: fileURL.pathExtension)?.identifier
        return .file(fileURL, contentTypeIdentifier: type)
      }
      if let input = try encodedInput(from: item) {
        return input
      }
    }

    for type in pasteboard.types ?? [] where isImagePasteboardType(type) {
      guard let data = pasteboard.data(forType: type) else {
        throw EditorOCRCaptureError.unreadableImage
      }
      return try normalizedInput(data: data, pasteboardType: type)
    }
    return nil
  }

  private func hasImageCandidate(in item: NSPasteboardItem) -> Bool {
    if let url = fileURL(from: item),
      let type = UTType(filenameExtension: url.pathExtension),
      type.conforms(to: .image)
    {
      return true
    }
    return item.types.contains(where: isImagePasteboardType)
  }

  private func encodedInput(from item: NSPasteboardItem) throws -> EditorOCRImageInput? {
    for type in item.types where isImagePasteboardType(type) {
      guard let data = item.data(forType: type) else {
        throw EditorOCRCaptureError.unreadableImage
      }
      return try normalizedInput(data: data, pasteboardType: type)
    }
    return nil
  }

  private func normalizedInput(
    data: Data,
    pasteboardType: NSPasteboard.PasteboardType
  ) throws -> EditorOCRImageInput {
    if pasteboardType == .tiff {
      guard let representation = NSBitmapImageRep(data: data),
        let png = representation.representation(using: .png, properties: [:])
      else {
        throw EditorOCRCaptureError.unreadableImage
      }
      return .encodedData(png, contentTypeIdentifier: UTType.png.identifier)
    }
    return .encodedData(data, contentTypeIdentifier: pasteboardType.rawValue)
  }

  private func fileURL(from item: NSPasteboardItem) -> URL? {
    guard let source = item.string(forType: .fileURL),
      let url = URL(string: source),
      url.isFileURL
    else { return nil }
    return url
  }

  private func isImagePasteboardType(_ type: NSPasteboard.PasteboardType) -> Bool {
    type == .tiff || UTType(type.rawValue)?.conforms(to: .image) == true
  }
}
