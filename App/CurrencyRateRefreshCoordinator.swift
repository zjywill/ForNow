import ForNowCore
import ForNowIntegrations
import Foundation

enum CurrencyRateRefreshOutcome: Equatable, Sendable {
  case skipped(RateSnapshot?)
  case updated(RateSnapshot)
  case failed(RateSnapshot?)
}

actor CurrencyRateRefreshCoordinator {
  static let automaticRefreshInterval: TimeInterval = 86_400

  private let provider: any CurrencyRateProvider
  private let cache: any CurrencyRateCaching
  private let clock: any WallClock

  init(
    provider: any CurrencyRateProvider,
    cache: any CurrencyRateCaching,
    clock: any WallClock
  ) {
    self.provider = provider
    self.cache = cache
    self.clock = clock
  }

  func cachedSnapshot(base: CurrencyCode) async -> RateSnapshot? {
    await cache.snapshot(base: base)
  }

  func refresh(base: CurrencyCode, automatic: Bool) async throws -> CurrencyRateRefreshOutcome {
    let now = clock.now()
    if automatic, let previousAttempt = await cache.lastAutomaticAttempt() {
      let elapsed = now.timeIntervalSince(previousAttempt)
      guard elapsed >= Self.automaticRefreshInterval else {
        return .skipped(await cache.snapshot(base: base))
      }
    }

    if automatic {
      do {
        try await cache.recordAutomaticAttempt(at: now)
      } catch {
        return .failed(await cache.snapshot(base: base))
      }
    }

    do {
      let snapshot = try await provider.rates(base: base).validated()
      try await cache.save(snapshot)
      return .updated(snapshot)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      if Task.isCancelled {
        throw CancellationError()
      }
      return .failed(await cache.snapshot(base: base))
    }
  }
}

enum CurrencyRateRefreshState: Equatable, Sendable {
  case idle
  case refreshing
  case current
  case failed
}
