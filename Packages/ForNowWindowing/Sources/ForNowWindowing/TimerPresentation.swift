import Foundation

public struct TimerStatusPresentation: Equatable, Sendable {
  public let text: String
  public let accessibilityLabel: String

  public init(text: String, accessibilityLabel: String) {
    self.text = text
    self.accessibilityLabel = accessibilityLabel
  }
}

public struct TimerTakeoverPresentation: Equatable, Sendable {
  public let id: UUID
  public let title: String
  public let detail: String

  public init(id: UUID, title: String, detail: String) {
    self.id = id
    self.title = title
    self.detail = detail
  }
}
