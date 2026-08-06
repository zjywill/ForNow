import ForNowCore
import Foundation

public enum EditorDirectionalEntry: Equatable, Sendable {
  case start
  case end
}

public struct HorizontalNavigationGestureInterpreter: Sendable {
  public let threshold: CGFloat
  private var accumulatedDeltaX: CGFloat = 0

  public init(threshold: CGFloat = 60) {
    self.threshold = threshold
  }

  public mutating func update(
    deltaX: CGFloat,
    deltaY: CGFloat,
    isComplete: Bool
  ) -> NoteNavigationDirection? {
    if abs(deltaX) > abs(deltaY) {
      accumulatedDeltaX += deltaX
    }
    guard isComplete else { return nil }
    defer { accumulatedDeltaX = 0 }
    guard abs(accumulatedDeltaX) >= threshold else { return nil }
    return accumulatedDeltaX > 0 ? .previous : .next
  }

  public mutating func reset() {
    accumulatedDeltaX = 0
  }
}
