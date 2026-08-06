import Foundation

public struct CurrencyCode: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue.uppercased()
  }
}

public struct RateSnapshot: Codable, Equatable, Sendable {
  public let base: CurrencyCode
  public let rates: [CurrencyCode: Decimal]
  public let fetchedAt: Date

  public init(base: CurrencyCode, rates: [CurrencyCode: Decimal], fetchedAt: Date) {
    self.base = base
    self.rates = rates
    self.fetchedAt = fetchedAt
  }
}

public protocol CurrencyRateProvider: Sendable {
  func rates(base: CurrencyCode) async throws -> RateSnapshot
}

public enum CurrencyRateProviderError: Error, Equatable, Sendable {
  case disabled
}

public struct DisabledCurrencyRateProvider: CurrencyRateProvider {
  public init() {}

  public func rates(base: CurrencyCode) async throws -> RateSnapshot {
    throw CurrencyRateProviderError.disabled
  }
}
