import AppKit
import Foundation
import OSLog

public struct WindowCoordinatorCallbacks {
  public let makeContentViewController: @MainActor () -> NSViewController
  public let flushPendingSource: @MainActor (String?, Bool) async throws -> Void
  public let windowDidReopen: @MainActor () async throws -> Void
  public let windowDidClose: @MainActor () async -> Void

  public init(
    makeContentViewController: @escaping @MainActor () -> NSViewController,
    flushPendingSource: @escaping @MainActor (String?, Bool) async throws -> Void,
    windowDidReopen: @escaping @MainActor () async throws -> Void,
    windowDidClose: @escaping @MainActor () async -> Void
  ) {
    self.makeContentViewController = makeContentViewController
    self.flushPendingSource = flushPendingSource
    self.windowDidReopen = windowDidReopen
    self.windowDidClose = windowDidClose
  }
}

@MainActor
public protocol WindowCoordinating: AnyObject {
  var configuration: WindowConfiguration { get }
  var currentShortcut: GlobalShortcutCandidate { get }
  var lastShortcutRegistration: ShortcutRegistrationResult { get }
  var isWindowVisible: Bool { get }
  var windowCreationCount: Int { get }
  var timerStatusPresentation: TimerStatusPresentation? { get }
  var timerTakeoverPresentation: TimerTakeoverPresentation? { get }

  func configure(_ callbacks: WindowCoordinatorCallbacks)
  func start()
  func stop()
  func applyConfiguration(_ configuration: WindowConfiguration)
  func applyShortcut(_ candidate: GlobalShortcutCandidate) -> ShortcutRegistrationResult
  func showWindow(source: WindowInvocationSource)
  func toggleWindow(source: WindowInvocationSource)
  func closeWindow()
  func updateTimerStatus(_ presentation: TimerStatusPresentation?)
  func presentTimerTakeover(_ presentation: TimerTakeoverPresentation)
  func dismissTimerTakeover()
  func applicationDidBecomeActive()
  func applicationDidResignActive()
  func beginOwnedPanel(_ kind: OwnedPanelKind) -> AutoHideSuspension
  func endOwnedPanel(_ suspension: AutoHideSuspension)
  func flushPendingSourceForCommand() async throws
  func waitForPendingTransitions() async
}

@MainActor
public final class SwiftUIWindowCoordinator: NSObject, WindowCoordinating, NSWindowDelegate {
  public private(set) var configuration = WindowConfiguration()
  public var currentShortcut: GlobalShortcutCandidate { shortcut.current }
  public private(set) var lastShortcutRegistration: ShortcutRegistrationResult = .accepted
  public var isWindowVisible: Bool { window?.isVisible == true }
  public private(set) var windowCreationCount = 0
  public private(set) var timerStatusPresentation: TimerStatusPresentation?
  public private(set) var timerTakeoverPresentation: TimerTakeoverPresentation?
  public private(set) var hotkeyToCaretSamplesMilliseconds: [Double] = []
  public private(set) var isRunning = false

  private var callbacks: WindowCoordinatorCallbacks?
  private var visibility = WindowVisibilityStateMachine()
  private let shortcut: ValidatedGlobalShortcut
  private var window: NSWindow?
  private var statusItem: NSStatusItem?
  private var timerTakeoverPanel: NSPanel?
  private var transitionTask: Task<Void, Never>?
  private var isExecutingClose = false
  private var reopensAfterClose = false
  private var globalShowRequestedAt: UInt64?
  private let logger = Logger(subsystem: "app.fornow.ForNow", category: "window")

  public init(shortcut: ValidatedGlobalShortcut = ValidatedGlobalShortcut()) {
    self.shortcut = shortcut
    super.init()
  }

  public func configure(_ callbacks: WindowCoordinatorCallbacks) {
    self.callbacks = callbacks
  }

  public func start() {
    guard !isRunning else { return }
    isRunning = true
    visibility = WindowVisibilityStateMachine(
      state: WindowVisibilityState(
        isVisible: false,
        isApplicationActive: NSApp.isActive,
        isPinned: configuration.isPinned,
        autoHideEnabled: configuration.autoHideEnabled
      )
    )
    updatePresence()
    lastShortcutRegistration = shortcut.install { [weak self] in
      self?.toggleWindow(source: .globalShortcut)
    }
    showWindow(source: .localCommand)
  }

  public func stop() {
    guard isRunning else { return }
    isRunning = false
    transitionTask?.cancel()
    transitionTask = nil
    shortcut.uninstall()
    removeStatusItem()
    dismissTimerTakeover()
    window?.delegate = nil
    window?.orderOut(nil)
    window?.close()
    window = nil
    visibility = WindowVisibilityStateMachine()
  }

  public func applyConfiguration(_ configuration: WindowConfiguration) {
    guard isRunning else {
      self.configuration = configuration
      return
    }
    enqueue { coordinator in
      await coordinator.applyConfigurationNow(configuration)
    }
  }

  public func applyShortcut(
    _ candidate: GlobalShortcutCandidate
  ) -> ShortcutRegistrationResult {
    let result = shortcut.apply(candidate)
    lastShortcutRegistration = result
    return result
  }

  public func showWindow(source: WindowInvocationSource) {
    if source == .globalShortcut {
      globalShowRequestedAt = DispatchTime.now().uptimeNanoseconds
    }
    enqueueTransition(.show(source))
  }

  public func toggleWindow(source: WindowInvocationSource) {
    if source == .globalShortcut, !visibility.state.isVisible {
      globalShowRequestedAt = DispatchTime.now().uptimeNanoseconds
    }
    enqueueTransition(.toggle(source))
  }

  public func closeWindow() {
    enqueueTransition(.close)
  }

  public func updateTimerStatus(_ presentation: TimerStatusPresentation?) {
    guard timerStatusPresentation != presentation else { return }
    timerStatusPresentation = presentation
    if isRunning {
      updatePresence()
    }
  }

  public func presentTimerTakeover(_ presentation: TimerTakeoverPresentation) {
    timerTakeoverPresentation = presentation
    timerTakeoverPanel?.orderOut(nil)
    timerTakeoverPanel?.close()

    let screen =
      NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
      ?? NSScreen.main
      ?? NSScreen.screens.first
    guard let screen else { return }
    let panel = NSPanel(
      contentRect: screen.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false,
      screen: screen
    )
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.backgroundColor = .black
    panel.isOpaque = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.contentView = TimerTakeoverContentView(presentation: presentation) { [weak self] in
      self?.dismissTimerTakeover()
    }
    timerTakeoverPanel = panel
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(panel.contentView)
  }

  public func dismissTimerTakeover() {
    timerTakeoverPanel?.orderOut(nil)
    timerTakeoverPanel?.close()
    timerTakeoverPanel = nil
    timerTakeoverPresentation = nil
  }

  public func applicationDidBecomeActive() {
    enqueueTransition(.applicationFocusChanged(true))
  }

  public func applicationDidResignActive() {
    enqueueTransition(.applicationFocusChanged(false))
  }

  public func beginOwnedPanel(_ kind: OwnedPanelKind) -> AutoHideSuspension {
    let suspension = AutoHideSuspension(kind: kind)
    enqueueTransition(.beginOwnedPanel(suspension))
    return suspension
  }

  public func endOwnedPanel(_ suspension: AutoHideSuspension) {
    enqueueTransition(.endOwnedPanel(suspension))
  }

  public func flushPendingSourceForCommand() async throws {
    await transitionTask?.value
    guard let callbacks else { return }
    let textView = findTextView(in: window?.contentView)
    if textView?.hasMarkedText() == true {
      textView?.unmarkText()
    }
    try await callbacks.flushPendingSource(textView?.string, false)
  }

  public func waitForPendingTransitions() async {
    let task = transitionTask
    await task?.value
  }

  public func windowDidBecomeKey(_ notification: Notification) {
    applicationDidBecomeActive()
  }

  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard sender === window, !isExecutingClose else { return true }
    closeWindow()
    return false
  }

  private func enqueueTransition(_ event: WindowVisibilityEvent) {
    enqueue { coordinator in
      await coordinator.process(coordinator.visibility.transition(event))
    }
  }

  private func enqueue(
    _ operation: @escaping @MainActor (SwiftUIWindowCoordinator) async -> Void
  ) {
    guard isRunning else { return }
    let previousTask = transitionTask
    transitionTask = Task { [weak self] in
      await previousTask?.value
      guard !Task.isCancelled, let self, self.isRunning else { return }
      await operation(self)
    }
  }

  private func process(_ transition: WindowVisibilityTransition) async {
    for effect in transition.effects {
      guard !Task.isCancelled else { return }
      switch effect {
      case .showWindow:
        await showAndFocusWindow()
      case .focusEditor:
        focusEditor()
      case .flushPendingSource:
        guard await flushPendingSource() else {
          let recovery = visibility.transition(.show(.localCommand))
          await process(recovery)
          return
        }
      case .orderOut:
        window?.orderOut(nil)
      case .closeWindow:
        isExecutingClose = true
        window?.close()
        isExecutingClose = false
        reopensAfterClose = true
        await callbacks?.windowDidClose()
      case .applyWindowPolicy:
        applyWindowPolicy()
      }
    }
  }

  private func applyConfigurationNow(_ updated: WindowConfiguration) async {
    let previous = configuration
    guard previous != updated else { return }
    configuration = updated

    if previous.isPinned != updated.isPinned {
      await process(visibility.transition(.setPinned(updated.isPinned)))
    }
    if previous.autoHideEnabled != updated.autoHideEnabled {
      await process(visibility.transition(.setAutoHide(updated.autoHideEnabled)))
    }
    if previous.presence != updated.presence {
      updatePresence()
    }
    if previous.mode != updated.mode {
      guard await flushPendingSource() else {
        configuration = previous
        return
      }
      let wasVisible = visibility.state.isVisible
      rebuildWindow()
      if wasVisible {
        await showAndFocusWindow()
      }
    } else {
      applyWindowPolicy()
      if previous.dropdownDimensions != updated.dropdownDimensions,
        updated.mode == .dropdownPanel
      {
        placeWindow()
      }
    }
  }

  private func showAndFocusWindow() async {
    if window == nil {
      createWindow()
    }
    if reopensAfterClose {
      do {
        try await callbacks?.windowDidReopen()
      } catch {
        NSSound.beep()
        return
      }
      reopensAfterClose = false
    }
    placeWindow()
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    let policy = WindowPresentationPolicy.resolve(
      mode: configuration.mode,
      isPinned: configuration.isPinned
    )
    if policy.usesPanel {
      window?.orderFrontRegardless()
    }
    focusEditor()
  }

  private func focusEditor() {
    guard let window, window.isVisible else { return }
    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, let window,
        let textView = self.findTextView(in: window.contentView)
      else { return }
      guard window.makeFirstResponder(textView) else { return }
      self.recordHotkeyToCaretLatencyIfNeeded()
    }
  }

  private func recordHotkeyToCaretLatencyIfNeeded() {
    guard let globalShowRequestedAt else { return }
    self.globalShowRequestedAt = nil
    let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - globalShowRequestedAt
    let milliseconds = Double(elapsedNanoseconds) / 1_000_000
    hotkeyToCaretSamplesMilliseconds.append(milliseconds)
    if hotkeyToCaretSamplesMilliseconds.count > 200 {
      hotkeyToCaretSamplesMilliseconds.removeFirst(
        hotkeyToCaretSamplesMilliseconds.count - 200
      )
    }
    logger.notice("hotkey_to_caret_ms=\(milliseconds, privacy: .public)")
  }

  private func flushPendingSource() async -> Bool {
    guard let callbacks else { return true }
    let textView = findTextView(in: window?.contentView)
    if textView?.hasMarkedText() == true {
      textView?.unmarkText()
    }
    do {
      try await callbacks.flushPendingSource(textView?.string, false)
      return true
    } catch {
      NSSound.beep()
      return false
    }
  }

  private func findTextView(in view: NSView?) -> NSTextView? {
    guard let view else { return nil }
    if let textView = view as? NSTextView {
      return textView
    }
    for subview in view.subviews {
      if let textView = findTextView(in: subview) {
        return textView
      }
    }
    return nil
  }

  private func rebuildWindow() {
    if let window {
      window.delegate = nil
      window.orderOut(nil)
      window.close()
      self.window = nil
    }
    createWindow()
  }

  private func createWindow() {
    guard let callbacks else { return }
    let policy = WindowPresentationPolicy.resolve(
      mode: configuration.mode,
      isPinned: configuration.isPinned
    )
    var styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
    let createdWindow: NSWindow
    if policy.usesPanel {
      if policy.usesNonactivatingPanel {
        styleMask.insert(.nonactivatingPanel)
      }
      let panel = ForNowPanel(
        contentRect: .zero,
        styleMask: styleMask,
        backing: .buffered,
        defer: false
      )
      panel.isFloatingPanel = true
      panel.hidesOnDeactivate = false
      createdWindow = panel
    } else {
      createdWindow = NSWindow(
        contentRect: .zero,
        styleMask: styleMask,
        backing: .buffered,
        defer: false
      )
    }
    createdWindow.title = "ForNow"
    createdWindow.isReleasedWhenClosed = false
    createdWindow.minSize =
      configuration.mode == .dropdownPanel
      ? DropdownDimensions.minimum
      : NSSize(width: 420, height: 320)
    createdWindow.delegate = self
    createdWindow.contentViewController = callbacks.makeContentViewController()
    createdWindow.setAccessibilityLabel("ForNow")
    window = createdWindow
    windowCreationCount += 1
    applyWindowPolicy()
  }

  private func applyWindowPolicy() {
    guard let window else { return }
    let policy = WindowPresentationPolicy.resolve(
      mode: configuration.mode,
      isPinned: configuration.isPinned
    )
    switch policy.level {
    case .normal:
      window.level = .normal
    case .floating:
      window.level = .floating
    case .statusBar:
      window.level = .statusBar
    }
    var behavior: NSWindow.CollectionBehavior = []
    for capability in policy.collectionCapabilities {
      switch capability {
      case .managed: behavior.insert(.managed)
      case .moveToActiveSpace: behavior.insert(.moveToActiveSpace)
      case .canJoinAllSpaces: behavior.insert(.canJoinAllSpaces)
      case .fullScreenAuxiliary: behavior.insert(.fullScreenAuxiliary)
      case .transient: behavior.insert(.transient)
      case .ignoresCycle: behavior.insert(.ignoresCycle)
      }
    }
    window.collectionBehavior = behavior
  }

  private func placeWindow() {
    guard let window, let screen = currentScreenGeometry() else { return }
    let requestedSize: CGSize
    let style: WindowPlacementStyle
    switch configuration.mode {
    case .standard:
      requestedSize = CGSize(width: 620, height: 540)
      style = .centered
    case .menuBarPanel:
      requestedSize = CGSize(width: 620, height: 540)
      style = .centered
    case .dropdownPanel:
      requestedSize = CGSize(
        width: configuration.dropdownDimensions.width,
        height: configuration.dropdownDimensions.height
      )
      style = .dropdown(anchorX: statusItemAnchorX(on: screen))
    }
    let frame = WindowPlacement.frame(requestedSize: requestedSize, on: screen, style: style)
    window.setFrame(frame, display: true)
  }

  private func currentScreenGeometry() -> ScreenGeometry? {
    let screens = NSScreen.screens.map { screen in
      ScreenGeometry(
        identifier: screen.localizedName,
        frame: screen.frame,
        visibleFrame: screen.visibleFrame
      )
    }
    return WindowPlacement.targetScreen(containing: NSEvent.mouseLocation, screens: screens)
  }

  private func statusItemAnchorX(on screen: ScreenGeometry) -> CGFloat? {
    guard let buttonWindow = statusItem?.button?.window else { return nil }
    let midpoint = CGPoint(x: buttonWindow.frame.midX, y: buttonWindow.frame.midY)
    guard screen.frame.contains(midpoint) else { return nil }
    return midpoint.x
  }

  private func updatePresence() {
    let presence = configuration.presence
    NSApp.setActivationPolicy(presence.showsDockIcon ? .regular : .accessory)
    if presence.showsStatusItem || timerStatusPresentation != nil {
      if statusItem == nil {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemInvoked)
        statusItem = item
      }
      updateStatusItemContent()
    } else {
      removeStatusItem()
    }
  }

  private func updateStatusItemContent() {
    guard let statusItem, let button = statusItem.button else { return }
    if let timerStatusPresentation {
      statusItem.length = NSStatusItem.variableLength
      button.image = NSImage(
        systemSymbolName: "timer",
        accessibilityDescription: timerStatusPresentation.accessibilityLabel
      )
      button.imagePosition = .imageLeading
      button.title = " \(timerStatusPresentation.text)"
      button.toolTip = timerStatusPresentation.accessibilityLabel
      button.setAccessibilityLabel(timerStatusPresentation.accessibilityLabel)
    } else {
      statusItem.length = NSStatusItem.squareLength
      button.image = NSImage(
        systemSymbolName: "note.text",
        accessibilityDescription: "Toggle ForNow"
      )
      button.imagePosition = .imageOnly
      button.title = ""
      button.toolTip = "Toggle ForNow"
      button.setAccessibilityLabel("Toggle ForNow")
    }
  }

  private func removeStatusItem() {
    guard let statusItem else { return }
    NSStatusBar.system.removeStatusItem(statusItem)
    self.statusItem = nil
  }

  @objc private func statusItemInvoked() {
    toggleWindow(source: .statusItem)
  }
}

@MainActor
public final class DisabledWindowCoordinator: WindowCoordinating {
  public private(set) var configuration = WindowConfiguration()
  public private(set) var currentShortcut = GlobalShortcutCandidate.optionA
  public private(set) var lastShortcutRegistration: ShortcutRegistrationResult = .accepted
  public private(set) var isWindowVisible = false
  public private(set) var windowCreationCount = 0
  public private(set) var timerStatusPresentation: TimerStatusPresentation?
  public private(set) var timerTakeoverPresentation: TimerTakeoverPresentation?

  public init() {}

  public func configure(_ callbacks: WindowCoordinatorCallbacks) {}
  public func start() {}
  public func stop() {}

  public func applyConfiguration(_ configuration: WindowConfiguration) {
    self.configuration = configuration
  }

  public func applyShortcut(
    _ candidate: GlobalShortcutCandidate
  ) -> ShortcutRegistrationResult {
    currentShortcut = candidate
    lastShortcutRegistration = .accepted
    return .accepted
  }

  public func showWindow(source: WindowInvocationSource) {}
  public func toggleWindow(source: WindowInvocationSource) {}
  public func closeWindow() {}
  public func updateTimerStatus(_ presentation: TimerStatusPresentation?) {
    timerStatusPresentation = presentation
  }
  public func presentTimerTakeover(_ presentation: TimerTakeoverPresentation) {
    timerTakeoverPresentation = presentation
  }
  public func dismissTimerTakeover() {
    timerTakeoverPresentation = nil
  }
  public func applicationDidBecomeActive() {}
  public func applicationDidResignActive() {}

  public func beginOwnedPanel(_ kind: OwnedPanelKind) -> AutoHideSuspension {
    AutoHideSuspension(kind: kind)
  }

  public func endOwnedPanel(_ suspension: AutoHideSuspension) {}
  public func flushPendingSourceForCommand() async throws {}
  public func waitForPendingTransitions() async {}
}

@MainActor
final class TimerTakeoverContentView: NSView {
  private let dismiss: @MainActor () -> Void

  override var acceptsFirstResponder: Bool { true }

  init(
    presentation: TimerTakeoverPresentation,
    dismiss: @escaping @MainActor () -> Void
  ) {
    self.dismiss = dismiss
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor

    let symbol = NSImageView(
      image: NSImage(
        systemSymbolName: "timer",
        accessibilityDescription: presentation.title
      ) ?? NSImage()
    )
    symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 54, weight: .regular)
    symbol.contentTintColor = .white

    let title = NSTextField(labelWithString: presentation.title)
    title.font = .systemFont(ofSize: 42, weight: .semibold)
    title.textColor = .white
    title.alignment = .center
    title.maximumNumberOfLines = 2

    let detail = NSTextField(labelWithString: presentation.detail)
    detail.font = .monospacedDigitSystemFont(ofSize: 22, weight: .regular)
    detail.textColor = .secondaryLabelColor
    detail.alignment = .center
    detail.maximumNumberOfLines = 2

    let stack = NSStackView(views: [symbol, title, detail])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("\(presentation.title). \(presentation.detail)")
    setAccessibilityHelp("Press Escape or click to dismiss")
    setAccessibilityIdentifier("Timer takeover")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func mouseDown(with event: NSEvent) {
    dismiss()
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      dismiss()
    } else {
      super.keyDown(with: event)
    }
  }
}

private final class ForNowPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
