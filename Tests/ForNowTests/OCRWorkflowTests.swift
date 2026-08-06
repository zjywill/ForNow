import AppKit
import ForNowCore
import ForNowEditor
import ForNowIntegrations
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import ForNow

final class OCRWorkflowTests: XCTestCase {
  @MainActor
  func test_UT_OCR_001_ValidatorEnforcesBytesPixelsFormatAndWellFormedData() throws {
    let png = try imageData(text: "A", format: .png, width: 2, height: 2)
    let strictBytes = OCRImageValidator(
      limits: OCRImageLimits(maximumEncodedByteCount: png.count - 1, maximumPixelCount: 100)
    )
    let strictPixels = OCRImageValidator(
      limits: OCRImageLimits(maximumEncodedByteCount: png.count, maximumPixelCount: 3)
    )

    XCTAssertThrowsError(try strictBytes.validate(png)) { error in
      XCTAssertEqual(
        error as? OCRImageValidationError,
        .encodedDataTooLarge(maximumByteCount: png.count - 1)
      )
    }
    XCTAssertThrowsError(try strictPixels.validate(png)) { error in
      XCTAssertEqual(error as? OCRImageValidationError, .pixelCountTooLarge(maximumPixelCount: 3))
    }
    XCTAssertThrowsError(try OCRImageValidator().validate(Data())) { error in
      XCTAssertEqual(error as? OCRImageValidationError, .emptyData)
    }
    XCTAssertThrowsError(try OCRImageValidator().validate(Data("not an image".utf8))) { error in
      XCTAssertEqual(error as? OCRImageValidationError, .malformedImage)
    }
  }

  @MainActor
  func test_IT_OCR_001A_PNGValidationPreservesDimensions() throws {
    let data = try imageData(text: "PNG", format: .png, width: 320, height: 180)
    let image = try OCRImageValidator().validate(data)

    XCTAssertEqual(image.format, .png)
    XCTAssertEqual(image.pixelWidth, 320)
    XCTAssertEqual(image.pixelHeight, 180)
  }

  @MainActor
  func test_IT_OCR_001B_JPEGValidationPreservesDimensions() throws {
    let data = try imageData(text: "JPEG", format: .jpeg, width: 300, height: 200)
    let image = try OCRImageValidator().validate(data)

    XCTAssertEqual(image.format, .jpeg)
    XCTAssertEqual(image.pixelWidth, 300)
    XCTAssertEqual(image.pixelHeight, 200)
  }

  @MainActor
  func test_IT_OCR_001C_StaticGIFIsAccepted() throws {
    let data = try imageData(text: "GIF", format: .gif, width: 240, height: 120)
    XCTAssertEqual(try OCRImageValidator().validate(data).format, .gif)
  }

  @MainActor
  func test_IT_OCR_001D_AnimatedGIFAndTIFFAreRejected() throws {
    let animated = try animatedGIFData()
    let tiff = try imageData(text: "TIFF", format: .tiff, width: 200, height: 100)

    XCTAssertThrowsError(try OCRImageValidator().validate(animated)) { error in
      XCTAssertEqual(error as? OCRImageValidationError, .animatedGIF)
    }
    XCTAssertThrowsError(try OCRImageValidator().validate(tiff)) { error in
      XCTAssertEqual(error as? OCRImageValidationError, .unsupportedFormat)
    }
  }

  @MainActor
  func test_IT_OCR_002_VisionRecognizesEnglishCJKMixedAndLowContrastFixtures() async throws {
    let service = VisionOCRService()
    let fixtures = [
      ("FORNOW ENGLISH", OCRSettings(languagePreference: .english)),
      ("你好世界", OCRSettings(languagePreference: .simplifiedChinese)),
      ("FORNOW 你好", OCRSettings(languagePreference: .automatic)),
      ("SYSTEM PREFERRED", OCRSettings(languagePreference: .systemPreferred)),
      ("LOW CONTRAST", OCRSettings(languagePreference: .english)),
    ]

    for (index, fixture) in fixtures.enumerated() {
      let data = try imageData(
        text: fixture.0,
        format: .png,
        width: 1_200,
        height: 300,
        foreground: index == 4 ? NSColor(calibratedWhite: 0.55, alpha: 1) : .black
      )
      let result = try await service.recognizeText(in: data, settings: fixture.1)
      XCTAssertTrue(result.plainText.contains(where: { !$0.isWhitespace }))
    }
  }

  @MainActor
  func test_MT_OCR_002_RotatedFixtureAndExplicitLanguageUseLocalVision() async throws {
    let service = VisionOCRService()
    let data = try rotatedImageData(text: "ROTATED TEXT")
    let result = try await service.recognizeText(
      in: data,
      settings: OCRSettings(languagePreference: .english)
    )

    XCTAssertTrue(result.plainText.localizedCaseInsensitiveContains("ROTATED"))
  }

  @MainActor
  func test_ST_OCR_002_EmptyImageReturnsNoTextWithoutCreatingExternalState() async throws {
    let service = VisionOCRService()
    let data = try imageData(text: "", format: .png, width: 300, height: 200)
    let result = try await service.recognizeText(in: data)

    XCTAssertEqual(result.lines, [])
  }

  @MainActor
  func test_ET_OCR_003B_StaleResultWaitsForConfirmationThenUsesCurrentCursor() async throws {
    let service = StubOCRService(
      result: OCRResult(lines: [RecognizedTextLine(text: "Recognized", confidence: 1)]),
      delay: .milliseconds(80)
    )
    let model = OCRWorkflowModel(service: service, settingsStore: InMemoryOCRSettingsStore())
    let container = ProjectionEditorContainer(initialText: "Alpha")
    model.editorTarget.attach(to: container)
    model.recognize(request(anchorVersion: 0, location: 5))
    container.textView.insertText(" Beta", replacementRange: NSRange(location: 5, length: 0))
    container.textView.setSelectedRange(NSRange(location: 0, length: 0))

    await waitUntil { model.requiresInsertionConfirmation }
    XCTAssertEqual(container.textView.string, "Alpha Beta")
    model.confirmInsertionAtCurrentSelection()
    XCTAssertEqual(container.textView.string, "RecognizedAlpha Beta")
    XCTAssertEqual(model.phase, .idle)
  }

  @MainActor
  func test_ET_OCR_003C_FAULT_OCR_001_CancelPreventsLateInsertion() async throws {
    let service = StubOCRService(
      result: OCRResult(lines: [RecognizedTextLine(text: "Too late", confidence: 1)]),
      delay: .seconds(10)
    )
    let model = OCRWorkflowModel(service: service, settingsStore: InMemoryOCRSettingsStore())
    let container = ProjectionEditorContainer(initialText: "Keep")
    model.editorTarget.attach(to: container)
    model.recognize(request(anchorVersion: 0, location: 4))
    await waitUntil { model.isRecognizing }
    let didBegin = await waitForServiceToBegin(service)
    XCTAssertTrue(didBegin)

    model.cancel()
    await waitUntil { model.phase == .idle }
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(container.textView.string, "Keep")
    let observedCancellation = await service.observedCancellation
    XCTAssertTrue(observedCancellation)
  }

  @MainActor
  func test_ET_OCR_003E_EmptyRecognitionIsRecoverableAndDoesNotEditSource() async {
    let service = StubOCRService(result: OCRResult(lines: []))
    let model = OCRWorkflowModel(service: service, settingsStore: InMemoryOCRSettingsStore())
    let container = ProjectionEditorContainer(initialText: "Keep")
    model.editorTarget.attach(to: container)
    model.recognize(request(anchorVersion: 0, location: 4))

    await waitUntil { model.errorMessage != nil }
    XCTAssertEqual(model.errorMessage, "No text was found in the image.")
    XCTAssertEqual(container.textView.string, "Keep")
    model.dismissError()
    XCTAssertEqual(model.phase, .idle)
  }

  @MainActor
  func test_MT_OCR_002_LanguageSettingPersistsAndReachesService() async throws {
    let suiteName = "ForNowOCRSettingsTests.\(UUID().uuidString)"
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsOCRSettingsStore(suiteName: suiteName)
    let service = StubOCRService(
      result: OCRResult(lines: [RecognizedTextLine(text: "Text", confidence: 1)])
    )
    let model = OCRWorkflowModel(service: service, settingsStore: store)
    try await model.updateSettings(OCRSettings(languagePreference: .traditionalChinese))
    let reloaded = OCRWorkflowModel(service: service, settingsStore: store)
    await reloaded.start()
    XCTAssertEqual(reloaded.settings.languagePreference, .traditionalChinese)
    let container = ProjectionEditorContainer(initialText: "")
    reloaded.editorTarget.attach(to: container)

    reloaded.recognize(request(anchorVersion: 0, location: 0))
    await waitUntil { reloaded.phase == .idle && container.textView.string == "Text" }
    let lastLanguagePreference = await service.lastSettings?.languagePreference
    XCTAssertEqual(lastLanguagePreference, .traditionalChinese)
  }

  @MainActor
  private func request(anchorVersion: UInt64, location: Int) -> EditorOCRRequest {
    EditorOCRRequest(
      image: .encodedData(Data([1]), contentTypeIdentifier: UTType.png.identifier),
      source: .paste,
      anchor: EditorOCRInsertionAnchor(
        sourceVersion: anchorVersion,
        replacementRange: SourceRange(
          location: SourceOffset(utf16Offset: location),
          length: 0
        )
      )
    )
  }

  @MainActor
  private func waitUntil(
    timeout: Duration = .seconds(3),
    _ predicate: @escaping @MainActor () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
      if predicate() {
        return
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for OCR state")
  }

  @MainActor
  private func waitForServiceToBegin(_ service: StubOCRService) async -> Bool {
    for _ in 0..<100 {
      if await service.didBegin {
        return true
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return false
  }

  @MainActor
  private func imageData(
    text: String,
    format: NSBitmapImageRep.FileType,
    width: Int,
    height: Int,
    foreground: NSColor = .black
  ) throws -> Data {
    let representation = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: representation))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    if !text.isEmpty {
      text.draw(
        in: NSRect(x: 40, y: 40, width: width - 80, height: height - 80),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: min(110, CGFloat(height) * 0.45), weight: .medium),
          .foregroundColor: foreground,
        ]
      )
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return try XCTUnwrap(
      representation.representation(
        using: format,
        properties: format == .jpeg ? [.compressionFactor: 0.92] : [:]
      )
    )
  }

  @MainActor
  private func rotatedImageData(text: String) throws -> Data {
    let width = 420
    let height = 1_200
    let representation = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: representation))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    context.cgContext.translateBy(x: CGFloat(width), y: 0)
    context.cgContext.rotate(by: .pi / 2)
    text.draw(
      in: NSRect(x: 60, y: 100, width: height - 120, height: width - 160),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 96, weight: .medium),
        .foregroundColor: NSColor.black,
      ]
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
  }

  @MainActor
  private func animatedGIFData() throws -> Data {
    let first = try imageData(text: "A", format: .png, width: 80, height: 80)
    let second = try imageData(text: "B", format: .png, width: 80, height: 80)
    let firstSource = try XCTUnwrap(CGImageSourceCreateWithData(first as CFData, nil))
    let secondSource = try XCTUnwrap(CGImageSourceCreateWithData(second as CFData, nil))
    let firstImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(firstSource, 0, nil))
    let secondImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(secondSource, 0, nil))
    let data = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil)
    )
    CGImageDestinationAddImage(destination, firstImage, nil)
    CGImageDestinationAddImage(destination, secondImage, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }
}

private actor StubOCRService: OCRService {
  let result: OCRResult
  let delay: Duration
  private(set) var observedCancellation = false
  private(set) var lastSettings: OCRSettings?
  private(set) var didBegin = false

  init(result: OCRResult, delay: Duration = .zero) {
    self.result = result
    self.delay = delay
  }

  func recognizeText(in imageData: Data, settings: OCRSettings) async throws -> OCRResult {
    didBegin = true
    lastSettings = settings
    do {
      if delay > .zero {
        try await Task.sleep(for: delay)
      }
      try Task.checkCancellation()
      return result
    } catch is CancellationError {
      observedCancellation = true
      throw CancellationError()
    }
  }
}
