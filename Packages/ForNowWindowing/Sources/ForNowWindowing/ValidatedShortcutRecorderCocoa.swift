import AppKit
@preconcurrency import KeyboardShortcuts

@MainActor
public final class ValidatedShortcutRecorderCocoa: NSButton {
  public var candidateHandler: ((GlobalShortcutCandidate) -> ShortcutRegistrationResult)?
  public var resultHandler: ((ShortcutRegistrationResult) -> Void)?
  public var currentCandidate: GlobalShortcutCandidate {
    didSet {
      guard !isRecording else { return }
      title = currentCandidate.displayName
    }
  }

  private var eventMonitor: Any?
  private var isRecording = false

  public init(currentCandidate: GlobalShortcutCandidate) {
    self.currentCandidate = currentCandidate
    super.init(frame: .zero)
    title = currentCandidate.displayName
    bezelStyle = .rounded
    target = self
    action = #selector(beginRecording)
    setAccessibilityLabel("Global shortcut")
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    nil
  }

  public override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil, isRecording {
      finishRecording()
    }
    super.viewWillMove(toWindow: newWindow)
  }

  @objc private func beginRecording() {
    guard !isRecording else { return }
    isRecording = true
    title = "Press shortcut"
    KeyboardShortcuts.isEnabled = false
    window?.makeFirstResponder(self)
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      MainActor.assumeIsolated {
        self?.handle(event)
      }
      return nil
    }
  }

  private func handle(_ event: NSEvent) {
    if event.keyCode == 53 {
      finishRecording()
      return
    }
    guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
      NSSound.beep()
      return
    }
    let candidate = GlobalShortcutCandidate(shortcut)
    guard candidate.isEligibleForGlobalRegistration else {
      let result = ShortcutRegistrationResult.invalid
      resultHandler?(result)
      toolTip = result.message
      NSSound.beep()
      finishRecording()
      return
    }
    let result = candidateHandler?(candidate) ?? .failed(status: -1)
    resultHandler?(result)
    if result.isAccepted {
      currentCandidate = candidate
    } else {
      NSSound.beep()
    }
    toolTip = result.message
    finishRecording()
  }

  private func finishRecording() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
    KeyboardShortcuts.isEnabled = true
    isRecording = false
    title = currentCandidate.displayName
  }
}
