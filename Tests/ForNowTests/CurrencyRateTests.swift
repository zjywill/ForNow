import ForNowCore
import ForNowIntegrations
import ForNowModes
import Foundation
import XCTest

@testable import ForNow

final class CurrencyRateTests: XCTestCase {
  func test_UT_MATH_004N_ECBRequestIsFixedBoundedAndContainsNoNoteText() async throws {
    let noteText = "private note text must never leave the parser"
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Envelope><Cube><Cube time="2026-08-05"><Cube currency="USD" rate="1.2"/><Cube currency="JPY" rate="180"/></Cube></Cube></Envelope>
      """
    RecordingURLProtocol.install(
      statusCode: 200,
      body: Data(xml.utf8)
    )
    defer { RecordingURLProtocol.reset() }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    let snapshot = try await ECBCurrencyRateProvider(
      session: session,
      maximumResponseBytes: 10_000
    ).rates(base: CurrencyCode(rawValue: "USD"))
    let request = try XCTUnwrap(RecordingURLProtocol.recordedRequest())

    XCTAssertEqual(request.url, ECBCurrencyRateProvider.dailyRatesURL)
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertNil(request.url?.query)
    XCTAssertNil(request.httpBody)
    XCTAssertNil(request.httpBodyStream)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/xml")
    XCTAssertFalse(String(describing: request).contains(noteText))
    XCTAssertEqual(snapshot.base, CurrencyCode(rawValue: "USD"))
    XCTAssertEqual(snapshot.rates[CurrencyCode(rawValue: "USD")], 1)
    XCTAssertEqual(snapshot.rates[CurrencyCode(rawValue: "JPY")], 150)
    XCTAssertEqual(snapshot.source, .remote)
  }

  @MainActor
  func test_IT_MATH_004_AutomaticRefreshIsThrottledManualRefreshRemainsExplicit() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let clock = MutableWallClock(now)
    let snapshot = RateSnapshot(
      base: CurrencyCode(rawValue: "USD"),
      rates: [
        CurrencyCode(rawValue: "USD"): 1,
        CurrencyCode(rawValue: "EUR"): 0.8,
      ],
      fetchedAt: now,
      source: .remote
    )
    let provider = FixtureCurrencyRateProvider(snapshots: [snapshot])
    let cache = InMemoryCurrencyRateCache()
    let settings = MathSettings(automaticCurrencyRefreshEnabled: true)
    let environment = AppEnvironment.test(
      clock: clock,
      rateProvider: provider,
      rateCache: cache,
      mathSettings: InMemoryMathSettingsStore(settings: settings)
    )

    try await environment.start()
    await environment.waitForPendingCurrencyRefresh()
    let requestsAfterStart = await provider.requests()
    XCTAssertEqual(requestsAfterStart, [CurrencyCode(rawValue: "USD")])
    XCTAssertEqual(environment.rateSnapshot, snapshot)
    XCTAssertEqual(environment.currencyRateRefreshState, .current)

    let coordinator = CurrencyRateRefreshCoordinator(
      provider: provider,
      cache: cache,
      clock: clock
    )
    _ = try await coordinator.refresh(base: CurrencyCode(rawValue: "USD"), automatic: true)
    clock.set(now.addingTimeInterval(-1))
    _ = try await coordinator.refresh(base: CurrencyCode(rawValue: "USD"), automatic: true)
    let requestsBeforeInterval = await provider.requests()
    XCTAssertEqual(requestsBeforeInterval.count, 1)

    clock.set(now.addingTimeInterval(86_400))
    _ = try await coordinator.refresh(base: CurrencyCode(rawValue: "USD"), automatic: true)
    let requestsAfterInterval = await provider.requests()
    XCTAssertEqual(requestsAfterInterval.count, 2)

    await environment.refreshCurrencyRatesManually()
    let requestsAfterManualRefresh = await provider.requests()
    XCTAssertEqual(requestsAfterManualRefresh.count, 3)
    try await environment.shutdown()
  }

  @MainActor
  func testNetworkFailureKeepsCompatibleCachedSnapshotOffline() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let cached = RateSnapshot(
      base: CurrencyCode(rawValue: "USD"),
      rates: [
        CurrencyCode(rawValue: "USD"): 1,
        CurrencyCode(rawValue: "EUR"): 0.8,
      ],
      fetchedAt: now.addingTimeInterval(-90_000),
      source: .remote
    )
    let cache = InMemoryCurrencyRateCache(snapshots: [cached])
    let provider = FixtureCurrencyRateProvider(failure: .unavailable)
    let environment = AppEnvironment.test(
      clock: FixedWallClock(now),
      rateProvider: provider,
      rateCache: cache,
      mathSettings: InMemoryMathSettingsStore(
        settings: MathSettings(automaticCurrencyRefreshEnabled: true)
      )
    )

    try await environment.start()
    await environment.waitForPendingCurrencyRefresh()

    XCTAssertEqual(environment.rateSnapshot?.source, .cached)
    XCTAssertEqual(environment.currencyRateRefreshState, .failed)
    let requests = await provider.requests()
    XCTAssertEqual(requests, [CurrencyCode(rawValue: "USD")])
    try await environment.shutdown()
  }

  @MainActor
  func test_ST_MATH_004_SettingsMigrationAndCachedRatesSurviveRestart() async throws {
    let suiteName = "ForNowCurrencyStateTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.set(
      Data(
        #"{"version":1,"settings":{"significantDigits":6,"separatesThousands":false}}"#.utf8
      ),
      forKey: "app.fornow.math.settings.v1"
    )
    let settingsStore = UserDefaultsMathSettingsStore(suiteName: suiteName)
    let migrated = await settingsStore.load()

    XCTAssertEqual(migrated.significantDigits, 6)
    XCTAssertFalse(migrated.separatesThousands)
    XCTAssertEqual(migrated.primaryCurrency, CurrencyCode(rawValue: "USD"))
    XCTAssertEqual(migrated.secondaryCurrency, CurrencyCode(rawValue: "EUR"))
    let migratedData = try XCTUnwrap(
      defaults.data(forKey: "app.fornow.math.settings.v1")
    )
    let migratedJSON = try XCTUnwrap(
      JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
    )
    XCTAssertEqual(migratedJSON["version"] as? Int, 2)

    let snapshot = RateSnapshot(
      base: CurrencyCode(rawValue: "USD"),
      rates: [
        CurrencyCode(rawValue: "USD"): 1,
        CurrencyCode(rawValue: "EUR"): 0.8,
      ],
      fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
      source: .remote
    )
    let firstCache = UserDefaultsCurrencyRateCache(suiteName: suiteName)
    try await firstCache.save(snapshot)
    try await firstCache.recordAutomaticAttempt(at: Date(timeIntervalSince1970: 1_700_000_100))
    let restartedCache = UserDefaultsCurrencyRateCache(suiteName: suiteName)

    let restartedSnapshot = await restartedCache.snapshot(base: snapshot.base)
    let restartedAttempt = await restartedCache.lastAutomaticAttempt()
    XCTAssertEqual(restartedSnapshot?.source, .cached)
    XCTAssertEqual(
      restartedAttempt,
      Date(timeIntervalSince1970: 1_700_000_100)
    )

    let environment = AppEnvironment.test(
      rateCache: restartedCache,
      mathSettings: settingsStore
    )
    try await environment.start()
    XCTAssertEqual(environment.mathSettings, migrated)
    XCTAssertEqual(environment.rateSnapshot?.source, .cached)
    try await environment.shutdown()
  }

  func testMalformedCacheAndSnapshotRatesAreRejected() async throws {
    let invalid = RateSnapshot(
      base: CurrencyCode(rawValue: "USD"),
      rates: [CurrencyCode(rawValue: "EUR"): 0],
      fetchedAt: Date(timeIntervalSince1970: 0)
    )
    XCTAssertThrowsError(try invalid.validated()) { error in
      XCTAssertEqual(
        error as? RateSnapshotValidationError,
        .invalidRate(CurrencyCode(rawValue: "EUR"))
      )
    }

    let suiteName = "ForNowMalformedCurrencyCacheTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.set(Data("not-json".utf8), forKey: "app.fornow.currency.cache.v1")
    let cache = UserDefaultsCurrencyRateCache(suiteName: suiteName)

    let cachedSnapshot = await cache.snapshot(base: CurrencyCode(rawValue: "USD"))
    let automaticAttempt = await cache.lastAutomaticAttempt()
    XCTAssertNil(cachedSnapshot)
    XCTAssertNil(automaticAttempt)
  }

  func testECBProviderRejectsOversizedAndStructurallyInvalidXML() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer {
      session.invalidateAndCancel()
      RecordingURLProtocol.reset()
    }
    let validXML = """
      <Envelope><Cube><Cube time="2026-08-05"><Cube currency="USD" rate="1.2"/></Cube></Cube></Envelope>
      """
    RecordingURLProtocol.install(statusCode: 200, body: Data(validXML.utf8))

    do {
      _ = try await ECBCurrencyRateProvider(session: session, maximumResponseBytes: 16)
        .rates(base: CurrencyCode(rawValue: "USD"))
      XCTFail("Oversized response must be rejected")
    } catch {
      XCTAssertEqual(error as? CurrencyRateProviderError, .invalidResponse)
    }

    let duplicateDateXML = """
      <Envelope><Cube><Cube time="2026-08-05"><Cube currency="USD" rate="1.2"/></Cube><Cube time="2026-08-06"><Cube currency="JPY" rate="180"/></Cube></Cube></Envelope>
      """
    RecordingURLProtocol.install(statusCode: 200, body: Data(duplicateDateXML.utf8))
    do {
      _ = try await ECBCurrencyRateProvider(session: session, maximumResponseBytes: 10_000)
        .rates(base: CurrencyCode(rawValue: "USD"))
      XCTFail("Multiple dated cubes must be rejected")
    } catch {
      XCTAssertEqual(error as? CurrencyRateProviderError, .invalidResponse)
    }
  }

  func testCachedProviderNeverTurnsCancellationIntoCachedSuccess() async throws {
    let base = CurrencyCode(rawValue: "USD")
    let cache = InMemoryCurrencyRateCache(
      snapshots: [
        RateSnapshot(
          base: base,
          rates: [base: 1],
          fetchedAt: Date(timeIntervalSince1970: 0)
        )
      ]
    )
    let provider = CachedCurrencyRateProvider(
      upstream: URLCancellationRateProvider(),
      cache: cache
    )
    let request = Task { try await provider.rates(base: base) }
    await Task.yield()
    request.cancel()

    do {
      _ = try await request.value
      XCTFail("Cancellation must not fall back to a cached success")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }
}

private struct URLCancellationRateProvider: CurrencyRateProvider {
  func rates(base: CurrencyCode) async throws -> RateSnapshot {
    while !Task.isCancelled {
      await Task.yield()
    }
    throw URLError(.cancelled)
  }
}

private final class MutableWallClock: WallClock, @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(_ date: Date) {
    self.date = date
  }

  func now() -> Date {
    lock.withLock { date }
  }

  func set(_ date: Date) {
    lock.withLock { self.date = date }
  }
}

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
  private struct State {
    var statusCode = 200
    var body = Data()
    var request: URLRequest?
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var state = State()

  static func install(statusCode: Int, body: Data) {
    lock.withLock {
      state = State(statusCode: statusCode, body: body, request: nil)
    }
  }

  static func recordedRequest() -> URLRequest? {
    lock.withLock { state.request }
  }

  static func reset() {
    lock.withLock { state = State() }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let responseState = Self.lock.withLock { () -> State in
      Self.state.request = request
      return Self.state
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: responseState.statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/xml"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: responseState.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
