import Combine
import ForNowEditor
import ForNowIntegrations
import Foundation

enum OCRWorkflowPhase: Equatable, Sendable {
  case idle
  case recognizing(EditorOCRInputSource)
  case awaitingInsertionConfirmation
  case failed(String)
}

@MainActor
final class OCRWorkflowModel: ObservableObject {
  @Published private(set) var phase = OCRWorkflowPhase.idle
  @Published private(set) var settings = OCRSettings()
  @Published private(set) var hasSettingsPersistenceFailure = false

  let editorTarget = EditorOCRTarget()

  private let service: any OCRService
  private let settingsStore: any OCRSettingsStoring
  private var recognitionTask: Task<Void, Never>?
  private var requestGeneration: UInt64 = 0
  private var pendingRecognizedText: String?

  init(service: any OCRService, settingsStore: any OCRSettingsStoring) {
    self.service = service
    self.settingsStore = settingsStore
    editorTarget.requestHandler = { [weak self] request in
      self?.recognize(request)
    }
    editorTarget.captureErrorHandler = { [weak self] error in
      self?.fail(error.localizedDescription)
    }
  }

  deinit {
    recognitionTask?.cancel()
  }

  var isRecognizing: Bool {
    if case .recognizing = phase {
      return true
    }
    return false
  }

  var requiresInsertionConfirmation: Bool {
    phase == .awaitingInsertionConfirmation
  }

  var errorMessage: String? {
    guard case .failed(let message) = phase else { return nil }
    return message
  }

  func start() async {
    settings = await settingsStore.load()
  }

  func updateSettings(_ settings: OCRSettings) async throws {
    let previous = self.settings
    self.settings = settings
    do {
      try await settingsStore.save(settings)
      hasSettingsPersistenceFailure = false
    } catch {
      if self.settings == settings {
        self.settings = previous
      }
      hasSettingsPersistenceFailure = true
      throw error
    }
  }

  func recognize(_ request: EditorOCRRequest) {
    cancelActiveRecognition(resetsPhase: false)
    requestGeneration &+= 1
    let generation = requestGeneration
    let service = self.service
    let settings = self.settings
    phase = .recognizing(request.source)
    pendingRecognizedText = nil
    recognitionTask = Task { [weak self] in
      do {
        let data = try await Self.encodedData(for: request.image)
        try Task.checkCancellation()
        let result = try await service.recognizeText(in: data, settings: settings)
        try Task.checkCancellation()
        guard result.plainText.contains(where: { !$0.isWhitespace }) else {
          throw OCRWorkflowError.noTextRecognized
        }
        self?.complete(
          recognizedText: result.plainText,
          anchor: request.anchor,
          generation: generation
        )
      } catch is CancellationError {
        self?.completeCancellation(generation: generation)
      } catch {
        self?.completeFailure(error, generation: generation)
      }
    }
  }

  func cancel() {
    cancelActiveRecognition(resetsPhase: true)
  }

  func confirmInsertionAtCurrentSelection() {
    guard let pendingRecognizedText, requiresInsertionConfirmation else { return }
    self.pendingRecognizedText = nil
    if editorTarget.insertRecognizedTextAtCurrentSelection(pendingRecognizedText) {
      phase = .idle
    } else {
      fail(OCRWorkflowError.editorUnavailable.localizedDescription)
    }
  }

  func declineStaleInsertion() {
    guard requiresInsertionConfirmation else { return }
    pendingRecognizedText = nil
    phase = .idle
  }

  func dismissError() {
    guard errorMessage != nil else { return }
    phase = .idle
  }

  private func complete(
    recognizedText: String,
    anchor: EditorOCRInsertionAnchor,
    generation: UInt64
  ) {
    guard generation == requestGeneration else { return }
    recognitionTask = nil
    switch editorTarget.insertRecognizedText(recognizedText, at: anchor) {
    case .inserted:
      phase = .idle
    case .sourceChanged:
      pendingRecognizedText = recognizedText
      phase = .awaitingInsertionConfirmation
    case .editorUnavailable:
      fail(OCRWorkflowError.editorUnavailable.localizedDescription)
    }
  }

  private func completeCancellation(generation: UInt64) {
    guard generation == requestGeneration else { return }
    recognitionTask = nil
    pendingRecognizedText = nil
    phase = .idle
  }

  private func completeFailure(_ error: any Error, generation: UInt64) {
    guard generation == requestGeneration else { return }
    recognitionTask = nil
    let message =
      (error as? LocalizedError)?.errorDescription
      ?? OCRWorkflowError.recognitionFailed.localizedDescription
    fail(message)
  }

  private func fail(_ message: String) {
    pendingRecognizedText = nil
    phase = .failed(message)
  }

  private func cancelActiveRecognition(resetsPhase: Bool) {
    requestGeneration &+= 1
    recognitionTask?.cancel()
    recognitionTask = nil
    pendingRecognizedText = nil
    if resetsPhase {
      phase = .idle
    }
  }

  private nonisolated static func encodedData(for input: EditorOCRImageInput) async throws -> Data {
    switch input {
    case .encodedData(let data, _):
      return data
    case .file(let url, _):
      return try await Task.detached(priority: .userInitiated) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
          if didAccess {
            url.stopAccessingSecurityScopedResource()
          }
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
          throw OCRImageValidationError.malformedImage
        }
        if let fileSize = values.fileSize,
          fileSize > OCRImageLimits.standard.maximumEncodedByteCount
        {
          throw OCRImageValidationError.encodedDataTooLarge(
            maximumByteCount: OCRImageLimits.standard.maximumEncodedByteCount
          )
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
      }.value
    }
  }
}

private enum OCRWorkflowError: Error, LocalizedError {
  case noTextRecognized
  case editorUnavailable
  case recognitionFailed

  var errorDescription: String? {
    switch self {
    case .noTextRecognized:
      "No text was found in the image."
    case .editorUnavailable:
      "The recognized text could not be inserted. Finish editing and try again."
    case .recognitionFailed:
      "Text recognition failed. Try another image."
    }
  }
}
