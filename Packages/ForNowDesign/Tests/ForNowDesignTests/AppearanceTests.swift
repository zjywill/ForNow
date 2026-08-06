import ForNowDesign
import XCTest

final class AppearanceTests: XCTestCase {
  func test_UT_UI_001_ThemesUseIndependentSelectionsAndPassContrast() {
    let settings = AppearanceSettings(
      lightThemeID: .sageLight,
      darkThemeID: .charcoalDark
    )

    XCTAssertEqual(settings.theme(for: .light).id, .sageLight)
    XCTAssertEqual(settings.theme(for: .dark).id, .charcoalDark)
    for id in BuiltInThemeID.allCases {
      XCTAssertTrue(
        id.theme.passesContrastChecks,
        "\(id.rawValue) failed semantic text or control contrast"
      )
    }
  }

  func test_UIT_UI_002A_Through_UIT_UI_002J_AppearancePolicyCoversPaperAndMaterial() throws {
    let encoded = try JSONEncoder().encode(
      AppearanceSettings(
        lightThemeID: .sageLight,
        darkThemeID: .inkDark,
        paperStyle: .lined,
        paperOpacity: .bold,
        linedPaperListSpacing: .compact,
        blankPaperListSpacing: .spacious,
        translucentModeEnabled: true,
        backgroundOpacity: 120
      )
    )
    let settings = try JSONDecoder().decode(AppearanceSettings.self, from: encoded)
    XCTAssertEqual(settings.backgroundOpacity, 90)
    XCTAssertEqual(settings.effectiveListSpacing, .compact)
    XCTAssertEqual(PaperStyle.allCases.count, 5)
    XCTAssertEqual(PaperOpacity.allCases.count, 3)

    let macOS14 = AppearancePresentation.resolve(
      settings: settings,
      environment: AppearanceEnvironment(
        operatingSystemMajorVersion: 14,
        interfaceAppearance: .light,
        reducesTransparency: false,
        increasesContrast: false
      )
    )
    XCTAssertFalse(macOS14.translucentModeIsAvailable)
    XCTAssertFalse(macOS14.usesTranslucentMaterial)
    XCTAssertEqual(macOS14.backgroundAlpha, 1)

    let macOS15 = AppearancePresentation.resolve(
      settings: settings,
      environment: AppearanceEnvironment(
        operatingSystemMajorVersion: 15,
        interfaceAppearance: .light,
        reducesTransparency: false,
        increasesContrast: false
      )
    )
    XCTAssertTrue(macOS15.usesTranslucentMaterial)
    XCTAssertEqual(macOS15.backgroundAlpha, 0.9, accuracy: 0.001)

    let reduced = AppearancePresentation.resolve(
      settings: settings,
      environment: AppearanceEnvironment(
        operatingSystemMajorVersion: 15,
        interfaceAppearance: .light,
        reducesTransparency: true,
        increasesContrast: true
      )
    )
    XCTAssertFalse(reduced.usesTranslucentMaterial)
    XCTAssertEqual(reduced.backgroundAlpha, 1)
    XCTAssertTrue(reduced.drawsContrastBorder)

    var mismatched = settings
    mismatched.lightThemeID = .inkDark
    XCTAssertTrue(
      AppearancePresentation.resolve(
        settings: mismatched,
        environment: AppearanceEnvironment(
          operatingSystemMajorVersion: 15,
          interfaceAppearance: .light,
          reducesTransparency: false,
          increasesContrast: false
        )
      ).showsThemeMismatchWarning
    )
  }

  func test_UT_UI_003_TextSizeStepsClampAndDoubleExactly() {
    var settings = AppearanceSettings(textSize: .medium)
    settings.stepTextSize(by: 1)
    XCTAssertEqual(settings.textSize, .large)
    settings.stepTextSize(by: 100)
    XCTAssertEqual(settings.textSize, .extraLarge)
    settings.doublesTextSize = true
    XCTAssertEqual(settings.effectiveTextSize, 48)
    settings.stepTextSize(by: -100)
    XCTAssertEqual(settings.textSize, .extraSmall)
    XCTAssertEqual(settings.effectiveTextSize, 28)
  }
}
