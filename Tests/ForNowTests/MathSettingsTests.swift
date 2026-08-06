import ForNowModes
import XCTest

@testable import ForNow

final class MathSettingsTests: XCTestCase {
  @MainActor
  func testMathSettingsRoundTripAndEnvironmentLoadsThem() async throws {
    let suiteName = "ForNowMathSettingsTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let settings = MathSettings(significantDigits: 6, separatesThousands: false)
    let store = UserDefaultsMathSettingsStore(suiteName: suiteName)

    try await store.save(settings)
    let initiallyLoaded = await store.load()
    XCTAssertEqual(initiallyLoaded, settings)

    let environment = AppEnvironment.test(mathSettings: store)
    try await environment.start()
    XCTAssertEqual(environment.mathSettings, settings)

    let updated = MathSettings(significantDigits: 1, separatesThousands: true)
    try await environment.updateMathSettings(updated)
    XCTAssertEqual(environment.mathSettings, updated)
    let updatedLoaded = await store.load()
    XCTAssertEqual(updatedLoaded, updated)
    try await environment.shutdown()
  }

  func testMathSettingsInvalidPayloadFallsBackAndInvalidSaveIsRejected() async throws {
    let suiteName = "ForNowMathSettingsFallbackTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.set(Data("not-json".utf8), forKey: "app.fornow.math.settings.v1")
    let store = UserDefaultsMathSettingsStore(suiteName: suiteName)

    let fallback = await store.load()
    XCTAssertEqual(fallback, MathSettings())

    var invalid = MathSettings()
    invalid.significantDigits = 8
    do {
      try await store.save(invalid)
      XCTFail("An out-of-range result digit setting must be rejected")
    } catch {
      XCTAssertEqual(
        error as? MathSettingsValidationError,
        .invalidSignificantDigits(8)
      )
    }
    let afterRejectedSave = await store.load()
    XCTAssertEqual(afterRejectedSave, MathSettings())
  }

  @MainActor
  func testMathSettingsSaveFailureRollsBackPublishedState() async throws {
    let original = MathSettings(significantDigits: 3, separatesThousands: true)
    let store = FailingMathSettingsStore(settings: original)
    let environment = AppEnvironment.test(mathSettings: store)
    try await environment.start()

    do {
      try await environment.updateMathSettings(
        MathSettings(significantDigits: 7, separatesThousands: false)
      )
      XCTFail("A math settings write failure must be surfaced")
    } catch {
      XCTAssertEqual(error as? FailingMathSettingsStore.Failure, .save)
    }

    XCTAssertEqual(environment.mathSettings, original)
    try await environment.shutdown()
  }
}

private actor FailingMathSettingsStore: MathSettingsStoring {
  enum Failure: Error {
    case save
  }

  let settings: MathSettings

  init(settings: MathSettings) {
    self.settings = settings
  }

  func load() -> MathSettings {
    settings
  }

  func save(_ settings: MathSettings) throws {
    throw Failure.save
  }
}
