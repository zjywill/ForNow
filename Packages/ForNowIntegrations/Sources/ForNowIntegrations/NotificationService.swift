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

public enum TimerNotificationKind: String, Codable, Equatable, Sendable {
  case countdownCompleted
  case pomodoroBreakBegan
}

public struct TimerNotificationRequest: Equatable, Sendable {
  public let timerID: UUID
  public let kind: TimerNotificationKind
  public let fireDate: Date
  public let title: String
  public let body: String
  public let playsSound: Bool

  public init(
    timerID: UUID,
    kind: TimerNotificationKind,
    fireDate: Date,
    title: String,
    body: String,
    playsSound: Bool
  ) {
    self.timerID = timerID
    self.kind = kind
    self.fireDate = fireDate
    self.title = title
    self.body = body
    self.playsSound = playsSound
  }

  public var identifier: String {
    "app.fornow.timer.\(timerID.uuidString).\(kind.rawValue)"
  }
}

public protocol NotificationService: Sendable {
  func start() async
  func stop() async
  func authorizationState() async -> NotificationAuthorizationState
  func requestAuthorization() async throws -> Bool
  func scheduleTimerNotification(_ request: TimerNotificationRequest) async throws
  func cancelTimerNotifications(timerID: UUID?) async
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

  public func scheduleTimerNotification(_ request: TimerNotificationRequest) async throws {
    let content = UNMutableNotificationContent()
    content.title = request.title
    content.body = request.body
    if request.playsSound {
      content.sound = .default
    }
    let interval = max(1, request.fireDate.timeIntervalSinceNow)
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    try await center.add(
      UNNotificationRequest(
        identifier: request.identifier,
        content: content,
        trigger: trigger
      )
    )
  }

  public func cancelTimerNotifications(timerID: UUID?) async {
    let prefix = timerID.map { "app.fornow.timer.\($0.uuidString)." } ?? "app.fornow.timer."
    let requests = await center.pendingNotificationRequests()
    let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
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

  public func scheduleTimerNotification(_ request: TimerNotificationRequest) async throws {}

  public func cancelTimerNotifications(timerID: UUID?) async {}
}

public actor RecordingNotificationService: NotificationService {
  private var state: NotificationAuthorizationState
  private var requests: [TimerNotificationRequest] = []
  private var authorizationRequestCount = 0

  public init(state: NotificationAuthorizationState = .authorized) {
    self.state = state
  }

  public func start() async {}
  public func stop() async {}

  public func authorizationState() async -> NotificationAuthorizationState {
    state
  }

  public func requestAuthorization() async throws -> Bool {
    authorizationRequestCount += 1
    return state == .authorized || state == .provisional || state == .ephemeral
  }

  public func scheduleTimerNotification(_ request: TimerNotificationRequest) async throws {
    requests.removeAll { $0.identifier == request.identifier }
    requests.append(request)
  }

  public func cancelTimerNotifications(timerID: UUID?) async {
    if let timerID {
      requests.removeAll { $0.timerID == timerID }
    } else {
      requests.removeAll()
    }
  }

  public func scheduledTimerNotifications() -> [TimerNotificationRequest] {
    requests
  }

  public func requestedAuthorizationCount() -> Int {
    authorizationRequestCount
  }

  public func setAuthorizationState(_ state: NotificationAuthorizationState) {
    self.state = state
  }
}
