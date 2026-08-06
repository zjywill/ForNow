import Foundation
@preconcurrency import UserNotifications

public enum NotificationAuthorizationState: String, Codable, Equatable, Sendable {
  case notDetermined
  case denied
  case authorized
  case provisional
  case ephemeral
  case unknown
}

public protocol NotificationService: Sendable {
  func start() async
  func stop() async
  func authorizationState() async -> NotificationAuthorizationState
  func requestAuthorization() async throws -> Bool
}

public actor UserNotificationService: NotificationService {
  private let center: UNUserNotificationCenter

  public init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  public func start() async {}
  public func stop() async {}

  public func authorizationState() async -> NotificationAuthorizationState {
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .notDetermined:
      return .notDetermined
    case .denied:
      return .denied
    case .authorized:
      return .authorized
    case .provisional:
      return .provisional
    case .ephemeral:
      return .ephemeral
    @unknown default:
      return .unknown
    }
  }

  public func requestAuthorization() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .sound])
  }
}

public actor DisabledNotificationService: NotificationService {
  public init() {}

  public func start() async {}
  public func stop() async {}

  public func authorizationState() async -> NotificationAuthorizationState {
    .denied
  }

  public func requestAuthorization() async throws -> Bool {
    false
  }
}
