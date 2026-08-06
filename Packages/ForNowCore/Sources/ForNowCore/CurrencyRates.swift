import Foundation

public struct CurrencyCode: RawRepresentable, Codable, Hashable, Sendable, Comparable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue.uppercased(with: Locale(identifier: "en_US_POSIX"))
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(rawValue: try container.decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var isISOFormatted: Bool {
    rawValue.utf8.count == 3 && rawValue.utf8.allSatisfy { (65...90).contains($0) }
  }

  public static func < (left: CurrencyCode, right: CurrencyCode) -> Bool {
    left.rawValue < right.rawValue
  }
}

public enum RateSnapshotSource: String, Codable, Sendable, Equatable {
  case remote
  case cached
  case fixture
}

public struct RateSnapshot: Codable, Equatable, Sendable {
  public let base: CurrencyCode
  public let rates: [CurrencyCode: Decimal]
  public let fetchedAt: Date
  public let source: RateSnapshotSource

  public init(
    base: CurrencyCode,
    rates: [CurrencyCode: Decimal],
    fetchedAt: Date,
    source: RateSnapshotSource = .fixture
  ) {
    self.base = base
    self.rates = rates
    self.fetchedAt = fetchedAt
    self.source = source
  }

  public func withSource(_ source: RateSnapshotSource) -> RateSnapshot {
    RateSnapshot(base: base, rates: rates, fetchedAt: fetchedAt, source: source)
  }

  public func validated() throws -> RateSnapshot {
    guard base.isISOFormatted else {
      throw RateSnapshotValidationError.invalidBase(base)
    }
    guard !rates.isEmpty else {
      throw RateSnapshotValidationError.emptyRates
    }
    for (code, rate) in rates {
      guard code.isISOFormatted else {
        throw RateSnapshotValidationError.invalidCurrency(code)
      }
      guard Self.isPositiveFinite(rate) else {
        throw RateSnapshotValidationError.invalidRate(code)
      }
    }
    return self
  }

  private static func isPositiveFinite(_ value: Decimal) -> Bool {
    let number = NSDecimalNumber(decimal: value)
    return number != .notANumber
      && number.compare(NSDecimalNumber.zero) == .orderedDescending
  }
}

public enum RateSnapshotValidationError: Error, Equatable, Sendable {
  case invalidBase(CurrencyCode)
  case emptyRates
  case invalidCurrency(CurrencyCode)
  case invalidRate(CurrencyCode)
}
