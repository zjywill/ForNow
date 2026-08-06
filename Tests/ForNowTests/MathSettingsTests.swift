import ForNowCore
import ForNowModes
import XCTest

@testable import ForNow

final class MathSettingsTests: XCTestCase {
  @MainActor
  func testMathSettingsRoundTripAndEnvironmentLoadsThem() async throws {
    let suiteName = "ForNowMathSettingsTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let settings = MathSettings(
      significantDigits: 6,
      separatesThousands: false,
      primaryCurrency: CurrencyCode(rawValue: "GBP"),
      secondaryCurrency: CurrencyCode(rawValue: "JPY"),
      primaryCurrencySymbol: "GBP",
      automaticCurrencyRefreshEnabled: true,
      customCurrencyRates: [
        CustomCurrencyRate(
          source: CurrencyCode(rawValue: "GBP"),
          target: CurrencyCode(rawValue: "JPY"),
          rate: 192.5,
          updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        CustomCurrencyRate(
          source: CurrencyCode(rawValue: "USD"),
          target: CurrencyCode(rawValue: "EUR"),
          rate: 0.8,
          updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        ),
      ]
    )
    let store = UserDefaultsMathSettingsStore(suiteName: suiteName)

    try await store.save(settings)
    let initiallyLoaded = await store.load()
    XCTAssertEqual(initiallyLoaded, settings)

    let environment = AppEnvironment.test(mathSettings: store)
    try await environment.start()
    XCTAssertEqual(environment.mathSettings, settings)

    let updated = MathSettings(
      significantDigits: 1,
      separatesThousands: true,
      primaryCurrency: CurrencyCode(rawValue: "CAD"),
      secondaryCurrency: CurrencyCode(rawValue: "AUD"),
      primaryCurrencySymbol: "CA$",
      automaticCurrencyRefreshEnabled: false,
      customCurrencyRates: [
        CustomCurrencyRate(
          source: CurrencyCode(rawValue: "CAD"),
          target: CurrencyCode(rawValue: "AUD"),
          rate: 1.1,
          updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
      ]
    )
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

  func testMathSettingsRejectInvalidAndDuplicateCustomRates() async throws {
    let suiteName = "ForNowMathSettingsCustomRateTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsMathSettingsStore(suiteName: suiteName)
    let usd = CurrencyCode(rawValue: "USD")
    let eur = CurrencyCode(rawValue: "EUR")
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    let invalid = MathSettings(
      customCurrencyRates: [
        CustomCurrencyRate(source: usd, target: eur, rate: 0, updatedAt: date)
      ]
    )
    do {
      try await store.save(invalid)
      XCTFail("A nonpositive custom rate must be rejected")
    } catch {
      XCTAssertEqual(
        error as? MathSettingsValidationError,
        .invalidCustomRate(usd, eur)
      )
    }

    let duplicate = MathSettings(
      customCurrencyRates: [
        CustomCurrencyRate(source: usd, target: eur, rate: 0.8, updatedAt: date),
        CustomCurrencyRate(source: usd, target: eur, rate: 0.9, updatedAt: date),
      ]
    )
    do {
      try await store.save(duplicate)
      XCTFail("Duplicate custom currency pairs must be rejected")
    } catch {
      XCTAssertEqual(
        error as? MathSettingsValidationError,
        .duplicateCustomRate(usd, eur)
      )
    }

    let persisted = await store.load()
    XCTAssertEqual(persisted, MathSettings())
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
