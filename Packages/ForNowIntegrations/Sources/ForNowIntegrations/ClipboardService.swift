import AppKit

@MainActor
public protocol ClipboardService: AnyObject {
  func start()
  func stop()
  func currentText() -> String?
}

@MainActor
public final class SystemClipboardService: ClipboardService {
  private var isActive = false

  public init() {}

  public func start() {
    isActive = true
  }

  public func stop() {
    isActive = false
  }

  public func currentText() -> String? {
    guard isActive else { return nil }
    return NSPasteboard.general.string(forType: .string)
  }
}

@MainActor
public final class DisabledClipboardService: ClipboardService {
  public init() {}

  public func start() {}
  public func stop() {}

  public func currentText() -> String? {
    nil
  }
}
