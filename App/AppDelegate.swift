import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let environment: AppEnvironment

  private var startupTask: Task<Void, Never>?
  private var terminationTask: Task<Void, Never>?

  override convenience init() {
    self.init(environment: .production())
  }

  init(environment: AppEnvironment) {
    self.environment = environment
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(systemClockDidChange(_:)),
      name: .NSSystemClockDidChange,
      object: nil
    )
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(systemDidWake(_:)),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    startupTask = Task { [environment] in
      do {
        try await environment.start()
      } catch {
        NSSound.beep()
      }
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    environment.applicationDidBecomeActive()
  }

  func applicationDidResignActive(_ notification: Notification) {
    environment.applicationDidResignActive()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    environment.showWindow()
    return true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard terminationTask == nil else { return .terminateLater }
    guard environment.state != .stopped else { return .terminateNow }
    terminationTask = Task { [environment, startupTask] in
      await startupTask?.value
      do {
        try await environment.windowWillClose()
        try await environment.shutdown()
        sender.reply(toApplicationShouldTerminate: true)
      } catch {
        NSSound.beep()
        sender.reply(toApplicationShouldTerminate: false)
      }
    }
    return .terminateLater
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  @objc private func systemClockDidChange(_ notification: Notification) {
    Task { [environment] in
      await environment.timerModel.synchronizeClock()
    }
  }

  @objc private func systemDidWake(_ notification: Notification) {
    Task { [environment] in
      await environment.timerModel.synchronizeClock()
    }
  }
}
