import Foundation
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import Vision

public enum OCRImageFormat: String, Codable, CaseIterable, Sendable {
  case jpeg
  case png
  case gif
}

public struct OCRImageLimits: Codable, Equatable, Sendable {
  public static let standard = OCRImageLimits(
    maximumEncodedByteCount: 20 * 1_024 * 1_024,
    maximumPixelCount: 40_000_000
  )

  public let maximumEncodedByteCount: Int
  public let maximumPixelCount: Int

  public init(maximumEncodedByteCount: Int, maximumPixelCount: Int) {
    self.maximumEncodedByteCount = max(1, maximumEncodedByteCount)
    self.maximumPixelCount = max(1, maximumPixelCount)
  }
}

public struct ValidatedOCRImage: Equatable, Sendable {
  public let data: Data
  public let format: OCRImageFormat
  public let pixelWidth: Int
  public let pixelHeight: Int

  public init(
    data: Data,
    format: OCRImageFormat,
    pixelWidth: Int,
    pixelHeight: Int
  ) {
    self.data = data
    self.format = format
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }
}

public enum OCRImageValidationError: Error, Equatable, LocalizedError, Sendable {
  case emptyData
  case encodedDataTooLarge(maximumByteCount: Int)
  case malformedImage
  case unsupportedFormat
  case animatedGIF
  case invalidDimensions
  case pixelCountTooLarge(maximumPixelCount: Int)

  public var errorDescription: String? {
    switch self {
    case .emptyData, .malformedImage:
      "The image could not be read."
    case .encodedDataTooLarge(let maximumByteCount):
      "The image is larger than \(maximumByteCount / 1_024 / 1_024) MB."
    case .unsupportedFormat:
      "Use a PNG, JPEG, or static GIF image."
    case .animatedGIF:
      "Animated GIF images are not supported."
    case .invalidDimensions:
      "The image has invalid dimensions."
    case .pixelCountTooLarge(let maximumPixelCount):
      "The image exceeds the \(maximumPixelCount / 1_000_000) megapixel limit."
    }
  }
}

public struct OCRImageValidator: Sendable {
  public let limits: OCRImageLimits

  public init(limits: OCRImageLimits = .standard) {
    self.limits = limits
  }

  public func validate(_ data: Data) throws -> ValidatedOCRImage {
    guard !data.isEmpty else { throw OCRImageValidationError.emptyData }
    guard data.count <= limits.maximumEncodedByteCount else {
      throw OCRImageValidationError.encodedDataTooLarge(
        maximumByteCount: limits.maximumEncodedByteCount
      )
    }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0,
      let typeIdentifier = CGImageSourceGetType(source) as String?
    else {
      throw OCRImageValidationError.malformedImage
    }

    let format = try format(for: typeIdentifier)
    if format == .gif, CGImageSourceGetCount(source) != 1 {
      throw OCRImageValidationError.animatedGIF
    }
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
      width > 0,
      height > 0
    else {
      throw OCRImageValidationError.invalidDimensions
    }
    guard width <= limits.maximumPixelCount / height else {
      throw OCRImageValidationError.pixelCountTooLarge(
        maximumPixelCount: limits.maximumPixelCount
      )
    }

    return ValidatedOCRImage(
      data: data,
      format: format,
      pixelWidth: width,
      pixelHeight: height
    )
  }

  private func format(for typeIdentifier: String) throws -> OCRImageFormat {
    guard let type = UTType(typeIdentifier) else {
      throw OCRImageValidationError.unsupportedFormat
    }
    if type.conforms(to: .png) {
      return .png
    }
    if type.conforms(to: .jpeg) {
      return .jpeg
    }
    if type.conforms(to: .gif) {
      return .gif
    }
    throw OCRImageValidationError.unsupportedFormat
  }
}

public enum OCRLanguagePreference: String, Codable, CaseIterable, Sendable {
  case automatic
  case systemPreferred
  case english
  case simplifiedChinese
  case traditionalChinese
  case japanese
  case korean
  case french
  case german
  case spanish

  public var displayName: String {
    switch self {
    case .automatic:
      "Automatic"
    case .systemPreferred:
      "System Preferred"
    case .english:
      "English"
    case .simplifiedChinese:
      "Simplified Chinese"
    case .traditionalChinese:
      "Traditional Chinese"
    case .japanese:
      "Japanese"
    case .korean:
      "Korean"
    case .french:
      "French"
    case .german:
      "German"
    case .spanish:
      "Spanish"
    }
  }

  fileprivate var explicitLanguageIdentifier: String? {
    switch self {
    case .automatic, .systemPreferred:
      nil
    case .english:
      "en-US"
    case .simplifiedChinese:
      "zh-Hans"
    case .traditionalChinese:
      "zh-Hant"
    case .japanese:
      "ja-JP"
    case .korean:
      "ko-KR"
    case .french:
      "fr-FR"
    case .german:
      "de-DE"
    case .spanish:
      "es-ES"
    }
  }
}

public struct OCRSettings: Codable, Equatable, Sendable {
  public var languagePreference: OCRLanguagePreference

  public init(languagePreference: OCRLanguagePreference = .automatic) {
    self.languagePreference = languagePreference
  }
}

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

  public var plainText: String {
    lines.map(\.text).joined(separator: "\n")
  }
}

public enum OCRServiceError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedLanguage(String)
  case recognitionFailed

  public var errorDescription: String? {
    switch self {
    case .unsupportedLanguage:
      "The selected recognition language is unavailable on this Mac."
    case .recognitionFailed:
      "Text recognition failed. Try another image."
    }
  }
}

public protocol OCRService: Sendable {
  func recognizeText(in imageData: Data, settings: OCRSettings) async throws -> OCRResult
}

extension OCRService {
  public func recognizeText(in imageData: Data) async throws -> OCRResult {
    try await recognizeText(in: imageData, settings: OCRSettings())
  }
}

public actor VisionOCRService: OCRService {
  private let validator: OCRImageValidator

  public init(validator: OCRImageValidator = OCRImageValidator()) {
    self.validator = validator
  }

  public func recognizeText(in imageData: Data, settings: OCRSettings) async throws -> OCRResult {
    let image = try validator.validate(imageData)
    try Task.checkCancellation()
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    try configure(request, preference: settings.languagePreference)
    let handler = VNImageRequestHandler(data: image.data)

    return try await withTaskCancellationHandler {
      do {
        try handler.perform([request])
        try Task.checkCancellation()
      } catch {
        if Task.isCancelled
          || (error as NSError).code == VNErrorCode.requestCancelled.rawValue
        {
          throw CancellationError()
        }
        throw OCRServiceError.recognitionFailed
      }
      let lines = (request.results ?? []).compactMap { observation in
        observation.topCandidates(1).first.map { candidate in
          RecognizedTextLine(text: candidate.string, confidence: candidate.confidence)
        }
      }
      return OCRResult(lines: lines)
    } onCancel: {
      request.cancel()
    }
  }

  private func configure(
    _ request: VNRecognizeTextRequest,
    preference: OCRLanguagePreference
  ) throws {
    let supported = try request.supportedRecognitionLanguages()
    switch preference {
    case .automatic:
      request.automaticallyDetectsLanguage = true
    case .systemPreferred:
      let preferred = Locale.preferredLanguages.filter { language in
        supported.contains { supportedLanguage in
          Locale(identifier: supportedLanguage).language.languageCode
            == Locale(identifier: language).language.languageCode
        }
      }
      request.recognitionLanguages = preferred.isEmpty ? supported : preferred
      request.automaticallyDetectsLanguage = true
    default:
      guard let identifier = preference.explicitLanguageIdentifier,
        supported.contains(identifier)
      else {
        throw OCRServiceError.unsupportedLanguage(
          preference.explicitLanguageIdentifier ?? preference.rawValue
        )
      }
      request.recognitionLanguages = [identifier]
      request.automaticallyDetectsLanguage = false
    }
  }
}

public enum UnavailableOCRError: Error, Equatable, Sendable {
  case unavailable
}

public struct UnavailableOCRService: OCRService {
  public init() {}

  public func recognizeText(in imageData: Data, settings: OCRSettings) async throws -> OCRResult {
    throw UnavailableOCRError.unavailable
  }
}
