import Foundation

public enum NoteNavigationDirection: String, Codable, Equatable, Sendable {
  case previous
  case next
}

public enum DeleteRequestOutcome: Equatable, Sendable {
  case confirmationRequired
  case deleted
  case noNote
}

public struct DeleteConfirmationPolicy: Sendable {
  public init() {}

  public func requiresConfirmation(
    contentState: MeaningfulContentState,
    suppressesWarning: Bool
  ) -> Bool {
    contentState != .blank && !suppressesWarning
  }
}
