import AppKit

public struct ClipboardTextChange: Sendable, Equatable {
  public let changeCount: Int
  public let text: String

  public init(changeCount: Int, text: String) {
    self.changeCount = changeCount
    self.text = text
  }
}

@MainActor
public protocol ClipboardService: AnyObject {
  var isMonitoring: Bool { get }
  var pollingActivityCount: UInt64 { get }

  func startMonitoring(
    changeHandler: @escaping @MainActor (ClipboardTextChange) -> Void
  )
  func stopMonitoring()
  func markCurrentChangeAsOwn()
}

@MainActor
public final class SystemClipboardService: NSObject, ClipboardService {
  public private(set) var pollingActivityCount: UInt64 = 0

  public var isMonitoring: Bool {
    timer != nil
  }

  private let pasteboard: NSPasteboard
  private let pollingInterval: TimeInterval
  private var timer: Timer?
  private var lastObservedChangeCount: Int?
  private var ownChangeCounts: [Int] = []
  private var changeHandler: (@MainActor (ClipboardTextChange) -> Void)?

  public init(
    pasteboard: NSPasteboard = .general,
    pollingInterval: TimeInterval = 0.25
  ) {
    self.pasteboard = pasteboard
    self.pollingInterval = max(0.05, pollingInterval)
    super.init()
  }

  public func startMonitoring(
    changeHandler: @escaping @MainActor (ClipboardTextChange) -> Void
  ) {
    stopMonitoring()
    self.changeHandler = changeHandler
    lastObservedChangeCount = pasteboard.changeCount
    let timer = Timer(
      timeInterval: pollingInterval,
      target: self,
      selector: #selector(pollPasteboard(_:)),
      userInfo: nil,
      repeats: true
    )
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  public func stopMonitoring() {
    timer?.invalidate()
    timer = nil
    changeHandler = nil
    lastObservedChangeCount = nil
    ownChangeCounts.removeAll(keepingCapacity: true)
  }

  public func markCurrentChangeAsOwn() {
    let changeCount = pasteboard.changeCount
    guard ownChangeCounts.last != changeCount else { return }
    ownChangeCounts.append(changeCount)
    if ownChangeCounts.count > 32 {
      ownChangeCounts.removeFirst(ownChangeCounts.count - 32)
    }
  }

  @objc private func pollPasteboard(_ timer: Timer) {
    guard timer === self.timer else { return }
    pollingActivityCount &+= 1
    let changeCount = pasteboard.changeCount
    guard changeCount != lastObservedChangeCount else { return }
    lastObservedChangeCount = changeCount
    if let ownIndex = ownChangeCounts.firstIndex(of: changeCount) {
      ownChangeCounts.remove(at: ownIndex)
      return
    }
    guard let text = pasteboard.string(forType: .string) else { return }
    changeHandler?(ClipboardTextChange(changeCount: changeCount, text: text))
  }
}

@MainActor
public final class DisabledClipboardService: ClipboardService {
  public private(set) var isMonitoring = false
  public let pollingActivityCount: UInt64 = 0

  public init() {}

  public func startMonitoring(
    changeHandler: @escaping @MainActor (ClipboardTextChange) -> Void
  ) {
    isMonitoring = true
  }

  public func stopMonitoring() {
    isMonitoring = false
  }

  public func markCurrentChangeAsOwn() {}
}
