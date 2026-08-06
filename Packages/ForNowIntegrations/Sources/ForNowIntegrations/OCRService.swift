import Foundation
@preconcurrency import Vision

public struct RecognizedTextLine: Codable, Equatable, Sendable {
  public let text: String
  public let confidence: Float

  public init(text: String, confidence: Float) {
    self.text = text
    self.confidence = confidence
  }
}

public struct OCRResult: Codable, Equatable, Sendable {
  public let lines: [RecognizedTextLine]

  public init(lines: [RecognizedTextLine]) {
    self.lines = lines
  }
}

public protocol OCRService: Sendable {
  func recognizeText(in imageData: Data) async throws -> OCRResult
}

public actor VisionOCRService: OCRService {
  public init() {}

  public func recognizeText(in imageData: Data) async throws -> OCRResult {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(data: imageData)
    try handler.perform([request])
    let lines = (request.results ?? []).compactMap { observation in
      observation.topCandidates(1).first.map { candidate in
        RecognizedTextLine(text: candidate.string, confidence: candidate.confidence)
      }
    }
    return OCRResult(lines: lines)
  }
}

public enum UnavailableOCRError: Error, Equatable, Sendable {
  case unavailable
}

public struct UnavailableOCRService: OCRService {
  public init() {}

  public func recognizeText(in imageData: Data) async throws -> OCRResult {
    throw UnavailableOCRError.unavailable
  }
}
