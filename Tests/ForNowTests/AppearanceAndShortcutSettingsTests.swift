import AppKit
import Carbon.HIToolbox
import ForNowDesign
import ForNowEditor
import ForNowWindowing
import XCTest

@testable import ForNow

final class AppearanceAndShortcutSettingsTests: XCTestCase {
  func test_UIT_UI_002J_AppearanceSettingsRoundTripAndInvalidPayloadFallback() async throws {
    let suiteName = "ForNowAppearanceSettingsTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let settings = AppearanceSettings(
      lightThemeID: .sageLight,
      darkThemeID: .charcoalDark,
      paperStyle: .smallGrid,
      paperOpacity: .bold,
      linedPaperListSpacing: .spacious,
      blankPaperListSpacing: .compact,
      textSize: .large,
      doublesTextSize: true,
      translucentModeEnabled: true,
      backgroundOpacity: 42
    )
    let store = UserDefaultsAppearanceSettingsStore(suiteName: suiteName)
    try await store.save(settings)
    let roundTrippedSettings = await store.load()
    XCTAssertEqual(roundTrippedSettings, settings)

    UserDefaults(suiteName: suiteName)?.set(
      Data("not-json".utf8),
      forKey: "app.fornow.appearance.settings.v1"
    )
    let fallbackSettings = await store.load()
    XCTAssertEqual(fallbackSettings, AppearanceSettings())
  }

  func test_UT_EDIT_007_LegacyEditorSettingsMigrateToNaturalDirection() async {
    let suiteName = "ForNowEditorDirectionMigrationTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let legacyPayload = Data(
      """
      {
        "version": 3,
        "settings": {
          "automaticallyShortensLinks": false,
          "hyperlinkFeaturesEnabled": true,
          "defaultCodeLanguage": "plainText",
          "codeHighlightTheme": "adaptive",
          "omitsChecklistTriggersOnExport": true
        }
      }
      """.utf8
    )
    UserDefaults(suiteName: suiteName)?.set(
      legacyPayload,
      forKey: "app.fornow.editor.settings.v1"
    )

    let settings = await UserDefaultsEditorSettingsStore(suiteName: suiteName).load()

    XCTAssertFalse(settings.automaticallyShortensLinks)
    XCTAssertEqual(settings.layoutDirection, .natural)
  }

  func test_UT_UI_003_QuickActionValidationRejectsEveryUnsafeClass() throws {
    let validator = QuickActionSettingsValidator()
    XCTAssertNoThrow(try validator.validate(QuickActionSettings()))

    var duplicate = QuickActionSettings()
    duplicate[.nextNote] = duplicate[.previousNote]
    XCTAssertThrowsError(try validator.validate(duplicate)) { error in
      XCTAssertEqual(
        error as? QuickActionSettingsError,
        .duplicate(.previousNote, .nextNote)
      )
    }

    var reserved = QuickActionSettings()
    reserved[.newNote] = CommandShortcut("q", modifiers: .command)
    XCTAssertThrowsError(try validator.validate(reserved)) { error in
      XCTAssertEqual(
        error as? QuickActionSettingsError,
        .reserved(.newNote, "⌘Q")
      )
    }

    var modifierless = QuickActionSettings()
    modifierless[.newNote] = CommandShortcut("n", modifiers: [])
    XCTAssertThrowsError(try validator.validate(modifierless)) { error in
      XCTAssertEqual(error as? QuickActionSettingsError, .missingModifier(.newNote))
    }

    var globalConflict = QuickActionSettings()
    globalConflict[.newNote] = CommandShortcut("a", modifiers: .option)
    XCTAssertThrowsError(
      try validator.validate(globalConflict, globalInvocation: .optionA)
    ) { error in
      XCTAssertEqual(
        error as? QuickActionSettingsError,
        .conflictsWithGlobalInvocation(.newNote)
      )
    }
  }

  func test_UT_UI_003_QuickActionSettingsRoundTripAndMissingBindingsUseDefaults() async throws {
    let suiteName = "ForNowQuickActionSettingsTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    var settings = QuickActionSettings()
    settings[.newNote] = CommandShortcut("k", modifiers: [.command, .option])
    let store = UserDefaultsQuickActionSettingsStore(suiteName: suiteName)
    try await store.save(settings)
    let roundTrippedSettings = await store.load()
    XCTAssertEqual(roundTrippedSettings, settings)

    let partial = try JSONEncoder().encode(
      QuickActionSettings(bindings: [
        .newNote: CommandShortcut("k", modifiers: [.command, .option])
      ])
    )
    let decoded = try JSONDecoder().decode(QuickActionSettings.self, from: partial)
    XCTAssertEqual(decoded[.newNote].normalizedKey, "k")
    XCTAssertEqual(decoded[.previousNote], QuickActionSettings.defaults[.previousNote])
  }

  @MainActor
  func test_UT_UI_003_EnvironmentZoomPersistsAndGlobalConflictKeepsInvocation() async throws {
    let appearanceStore = InMemoryAppearanceSettingsStore()
    let environment = AppEnvironment.test(appearanceSettings: appearanceStore)
    try await environment.start()

    try await environment.stepTextSize(by: 1)
    XCTAssertEqual(environment.appearanceSettings.textSize, .large)
    let storedAppearance = await appearanceStore.load()
    XCTAssertEqual(storedAppearance.textSize, .large)

    let previousGlobal = environment.currentGlobalShortcut
    let conflictingGlobal = GlobalShortcutCandidate(
      keyCode: kVK_ANSI_N,
      modifiers: .command
    )
    XCTAssertEqual(environment.applyGlobalShortcut(conflictingGlobal), .conflict)
    XCTAssertEqual(environment.currentGlobalShortcut, previousGlobal)
    try await environment.shutdown()
  }

  @MainActor
  func test_UT_UI_003_StartupRepairsShortcutConflictWithoutChangingInvocation() async throws {
    var conflictingSettings = QuickActionSettings()
    conflictingSettings[.newNote] = CommandShortcut("a", modifiers: .option)
    let quickActionStore = InMemoryQuickActionSettingsStore(settings: conflictingSettings)
    let environment = AppEnvironment.test(quickActionSettings: quickActionStore)

    try await environment.start()

    XCTAssertEqual(environment.currentGlobalShortcut, .optionA)
    XCTAssertNoThrow(
      try QuickActionSettingsValidator().validate(
        environment.quickActionSettings,
        globalInvocation: environment.currentGlobalShortcut
      )
    )
    let storedSettings = await quickActionStore.load()
    XCTAssertEqual(storedSettings, environment.quickActionSettings)
    XCTAssertNotEqual(environment.quickActionSettings[.newNote], conflictingSettings[.newNote])
    try await environment.shutdown()
  }
}
