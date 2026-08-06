import ForNowCore
@preconcurrency import Foundation

public protocol CurrencyRateProvider: Sendable {
  func rates(base: CurrencyCode) async throws -> RateSnapshot
}

public enum CurrencyRateProviderError: Error, Equatable, Sendable {
  case disabled
  case unavailable
  case invalidResponse
  case missingBase(CurrencyCode)
}

public struct DisabledCurrencyRateProvider: CurrencyRateProvider {
  public init() {}

  public func rates(base: CurrencyCode) async throws -> RateSnapshot {
    throw CurrencyRateProviderError.disabled
  }
}

public protocol CurrencyRateCaching: Sendable {
  func snapshot(base: CurrencyCode) async -> RateSnapshot?
  func save(_ snapshot: RateSnapshot) async throws
  func lastAutomaticAttempt() async -> Date?
  func recordAutomaticAttempt(at date: Date) async throws
}

public actor InMemoryCurrencyRateCache: CurrencyRateCaching {
  private var snapshots: [CurrencyCode: RateSnapshot]
  private var automaticAttempt: Date?

  public init(snapshots: [RateSnapshot] = [], lastAutomaticAttempt: Date? = nil) {
    self.snapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.base, $0) })
    automaticAttempt = lastAutomaticAttempt
  }

  public func snapshot(base: CurrencyCode) -> RateSnapshot? {
    snapshots[base]?.withSource(.cached)
  }

  public func save(_ snapshot: RateSnapshot) throws {
    let snapshot = try snapshot.validated()
    snapshots[snapshot.base] = snapshot
  }

  public func lastAutomaticAttempt() -> Date? {
    automaticAttempt
  }

  public func recordAutomaticAttempt(at date: Date) {
    automaticAttempt = date
  }
}

public actor UserDefaultsCurrencyRateCache: CurrencyRateCaching {
  private struct StoredCache: Codable {
    static let currentVersion = 1

    let version: Int
    var snapshots: [String: RateSnapshot]
    var lastAutomaticAttempt: Date?
  }

  private enum Key {
    static let cache = "app.fornow.currency.cache.v1"
  }

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(suiteName: String? = nil) {
    if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
      self.defaults = defaults
    } else {
      defaults = .standard
    }
  }

  public func snapshot(base: CurrencyCode) -> RateSnapshot? {
    load()?.snapshots[base.rawValue]?.withSource(.cached)
  }

  public func save(_ snapshot: RateSnapshot) throws {
    let snapshot = try snapshot.validated()
    var cache = load() ?? emptyCache()
    cache.snapshots[snapshot.base.rawValue] = snapshot
    try persist(cache)
  }

  public func lastAutomaticAttempt() -> Date? {
    load()?.lastAutomaticAttempt
  }

  public func recordAutomaticAttempt(at date: Date) throws {
    var cache = load() ?? emptyCache()
    cache.lastAutomaticAttempt = date
    try persist(cache)
  }

  private func load() -> StoredCache? {
    guard
      let data = defaults.data(forKey: Key.cache),
      let cache = try? decoder.decode(StoredCache.self, from: data),
      cache.version == StoredCache.currentVersion,
      cache.snapshots.values.allSatisfy({ (try? $0.validated()) != nil })
    else { return nil }
    return cache
  }

  private func emptyCache() -> StoredCache {
    StoredCache(
      version: StoredCache.currentVersion,
      snapshots: [:],
      lastAutomaticAttempt: nil
    )
  }

  private func persist(_ cache: StoredCache) throws {
    defaults.set(try encoder.encode(cache), forKey: Key.cache)
  }
}

public actor CachedCurrencyRateProvider: CurrencyRateProvider {
  private let upstream: any CurrencyRateProvider
  private let cache: any CurrencyRateCaching

  public init(upstream: any CurrencyRateProvider, cache: any CurrencyRateCaching) {
    self.upstream = upstream
    self.cache = cache
  }

  public func rates(base: CurrencyCode) async throws -> RateSnapshot {
    do {
      let snapshot = try await upstream.rates(base: base).validated()
      try await cache.save(snapshot)
      return snapshot
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      if Task.isCancelled {
        throw CancellationError()
      }
      if let cached = await cache.snapshot(base: base) {
        return cached
      }
      throw error
    }
  }
}

public actor FixtureCurrencyRateProvider: CurrencyRateProvider {
  private let snapshots: [CurrencyCode: RateSnapshot]
  private let failure: CurrencyRateProviderError?
  private var requestedBases: [CurrencyCode] = []

  public init(
    snapshots: [RateSnapshot] = [],
    failure: CurrencyRateProviderError? = nil
  ) {
    self.snapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.base, $0) })
    self.failure = failure
  }

  public func rates(base: CurrencyCode) async throws -> RateSnapshot {
    requestedBases.append(base)
    if let failure { throw failure }
    guard let snapshot = snapshots[base] else {
      throw CurrencyRateProviderError.missingBase(base)
    }
    return snapshot
  }

  public func requests() -> [CurrencyCode] {
    requestedBases
  }
}

public struct ECBCurrencyRateProvider: CurrencyRateProvider {
  public static let dailyRatesURL = URL(
    string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
  )!

  private let session: URLSession
  private let maximumResponseBytes: Int

  public init(
    session: URLSession = .shared,
    maximumResponseBytes: Int = 1_000_000
  ) {
    self.session = session
    self.maximumResponseBytes = maximumResponseBytes
  }

  public func rates(base: CurrencyCode) async throws -> RateSnapshot {
    guard base.isISOFormatted else {
      throw CurrencyRateProviderError.missingBase(base)
    }
    var request = URLRequest(url: Self.dailyRatesURL)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 15
    request.setValue("application/xml", forHTTPHeaderField: "Accept")

    let (bytes, response) = try await session.bytes(for: request)
    guard
      let response = response as? HTTPURLResponse,
      (200..<300).contains(response.statusCode)
    else {
      throw CurrencyRateProviderError.invalidResponse
    }
    var data = Data()
    data.reserveCapacity(min(maximumResponseBytes, 64_000))
    for try await byte in bytes {
      guard data.count < maximumResponseBytes else {
        throw CurrencyRateProviderError.invalidResponse
      }
      data.append(byte)
      if data.count.isMultiple(of: 4_096) {
        try Task.checkCancellation()
      }
    }

    let parsed = try ECBXMLRateParser().parse(data)
    let euro = CurrencyCode(rawValue: "EUR")
    guard parsed.rates[euro] == nil else {
      throw CurrencyRateProviderError.invalidResponse
    }
    var euroRates = parsed.rates
    euroRates[euro] = 1
    guard let baseRate = euroRates[base] else {
      throw CurrencyRateProviderError.missingBase(base)
    }
    var rates: [CurrencyCode: Decimal] = [:]
    for (code, rate) in euroRates {
      rates[code] = try Self.divide(rate, by: baseRate)
    }
    return try RateSnapshot(
      base: base,
      rates: rates,
      fetchedAt: parsed.date,
      source: .remote
    ).validated()
  }

  private static func divide(_ numerator: Decimal, by denominator: Decimal) throws -> Decimal {
    var numerator = numerator
    var denominator = denominator
    var result = Decimal()
    let status = NSDecimalDivide(&result, &numerator, &denominator, .bankers)
    guard status == .noError else {
      throw CurrencyRateProviderError.invalidResponse
    }
    return result
  }
}

private final class ECBXMLRateParser: NSObject, XMLParserDelegate {
  private(set) var rates: [CurrencyCode: Decimal] = [:]
  private(set) var date: Date?
  private var failure: CurrencyRateProviderError?
  private var depth = 0
  private var datedCubeDepth: Int?

  func parse(_ data: Data) throws -> (rates: [CurrencyCode: Decimal], date: Date) {
    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.shouldResolveExternalEntities = false
    guard parser.parse(), failure == nil, let date, !rates.isEmpty else {
      throw failure ?? CurrencyRateProviderError.invalidResponse
    }
    return (rates, date)
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    depth += 1
    guard elementName == "Cube" else { return }
    if let time = attributeDict["time"] {
      guard date == nil, datedCubeDepth == nil,
        attributeDict["currency"] == nil,
        attributeDict["rate"] == nil
      else {
        fail(parser)
        return
      }
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd"
      date = formatter.date(from: time)
      guard date != nil else {
        fail(parser)
        return
      }
      datedCubeDepth = depth
      return
    }
    let currency = attributeDict["currency"]
    let rateSource = attributeDict["rate"]
    guard currency != nil || rateSource != nil else {
      return
    }
    guard
      let currency,
      let rateSource,
      let datedCubeDepth,
      depth == datedCubeDepth + 1
    else {
      fail(parser)
      return
    }
    let code = CurrencyCode(rawValue: currency)
    guard
      code.isISOFormatted,
      rates[code] == nil,
      let rate = Decimal(string: rateSource, locale: Locale(identifier: "en_US_POSIX")),
      NSDecimalNumber(decimal: rate).compare(NSDecimalNumber.zero) == .orderedDescending
    else {
      fail(parser)
      return
    }
    rates[code] = rate
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    if elementName == "Cube", depth == datedCubeDepth {
      datedCubeDepth = nil
    }
    depth = max(0, depth - 1)
  }

  private func fail(_ parser: XMLParser) {
    failure = .invalidResponse
    parser.abortParsing()
  }
}
