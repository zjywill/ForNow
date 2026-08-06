import AppKit
import ForNowWindowing
import SwiftUI

@MainActor
final class WindowSpikeCoordinator: NSObject, NSWindowDelegate {
  private(set) var window: NSWindow?
  private(set) var visibleWindowCreations = 0
  private(set) var persistedDraft = ""

  let model: WindowSpikeModel
  var currentShortcut: GlobalShortcutCandidate { shortcut.current }

  private var visibility = WindowVisibilityStateMachine()
  private let shortcut = ValidatedGlobalShortcut()
  private var statusItem: NSStatusItem?
  private var ownedSuspensions: [ObjectIdentifier: AutoHideSuspension] = [:]
  private var isExecutingClose = false

  override init() {
    model = WindowSpikeModel()
    super.init()
    model.coordinator = self
  }

  func start() {
    updatePresence()
    let registration = shortcut.install { [weak self] in
      self?.toggle(source: .globalShortcut)
    }
    model.appendLog("shortcut=\(shortcut.current.displayName) result=\(registration.message)")
    execute(visibility.transition(.show(.localCommand)))
  }

  func applicationDidBecomeActive() {
    execute(visibility.transition(.applicationFocusChanged(true)))
  }

  func applicationDidResignActive() {
    execute(visibility.transition(.applicationFocusChanged(false)))
  }

  func presentationModeDidChange() {
    let wasVisible = visibility.state.isVisible
    synchronizeDraftFromEditor()
    rebuildWindow()
    if wasVisible {
      showAndFocusWindow()
    }
    model.appendLog(
      "mode=\(model.configuration.mode.rawValue) draft-utf16=\(model.draft.utf16.count)"
    )
  }

  func presenceDidChange() {
    updatePresence()
    placeWindow()
    model.appendLog("presence=\(model.configuration.presence.rawValue)")
  }

  func pinDidChange() {
    execute(visibility.transition(.setPinned(model.configuration.isPinned)))
  }

  func autoHideDidChange() {
    execute(visibility.transition(.setAutoHide(model.configuration.autoHideEnabled)))
  }

  func dropdownDimensionsDidChange() {
    guard model.configuration.mode == .dropdownPanel else { return }
    placeWindow()
  }

  func applyShortcut(_ candidate: GlobalShortcutCandidate) -> ShortcutRegistrationResult {
    let previous = shortcut.current
    let result = shortcut.apply(candidate)
    model.appendLog(
      "shortcut-candidate=\(candidate.displayName) result=\(result) previous=\(previous.displayName) current=\(shortcut.current.displayName)"
    )
    return result
  }

  @objc func toggleWindowCommand() {
    toggle(source: .localCommand)
  }

  @objc func togglePinCommand() {
    model.setPinned(!model.configuration.isPinned)
  }

  @objc func closeWindowCommand() {
    execute(visibility.transition(.close))
  }

  @objc private func statusItemInvoked() {
    toggle(source: .statusItem)
  }

  func showSettingsPanel() {
    guard let window else { return }
    let suspension = beginOwnedPanel(.settings)
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
      styleMask: [.titled, .closable, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.title = "Window Spike Settings"
    panel.isReleasedWhenClosed = false
    panel.contentViewController = NSHostingController(
      rootView: VStack(alignment: .leading, spacing: 12) {
        Label("Owned settings panel", systemImage: "gearshape")
          .font(.headline)
        Text("Auto-hide remains suspended while this panel is open.")
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(24)
      .frame(width: 420, height: 240)
    )
    panel.delegate = self
    ownedSuspensions[ObjectIdentifier(panel)] = suspension
    window.addChildWindow(panel, ordered: .above)
    panel.center()
    panel.makeKeyAndOrderFront(nil)
  }

  func showSavePanel() {
    guard let window else { return }
    let suspension = beginOwnedPanel(.save)
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "WindowSpike.txt"
    panel.canCreateDirectories = true
    panel.beginSheetModal(for: window) { [weak self] _ in
      self?.endOwnedPanel(suspension)
    }
  }

  func showPermissionPanel() {
    guard let window else { return }
    let suspension = beginOwnedPanel(.permission)
    let alert = NSAlert()
    alert.messageText = "Permission check"
    alert.informativeText = "This spike does not request a protected capability."
    alert.addButton(withTitle: "Done")
    alert.beginSheetModal(for: window) { [weak self] _ in
      self?.endOwnedPanel(suspension)
    }
  }

  func windowDidBecomeKey(_ notification: Notification) {
    execute(visibility.transition(.applicationFocusChanged(true)))
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if sender === window, !isExecutingClose {
      let transition = visibility.transition(.close)
      record(transition)
      flushPendingSource()
    }
    return true
  }

  func windowWillClose(_ notification: Notification) {
    guard let closingWindow = notification.object as? NSWindow,
      closingWindow !== window,
      let suspension = ownedSuspensions.removeValue(forKey: ObjectIdentifier(closingWindow))
    else { return }
    window?.removeChildWindow(closingWindow)
    endOwnedPanel(suspension)
  }

  private func toggle(source: WindowInvocationSource) {
    execute(visibility.transition(.toggle(source)))
  }

  private func execute(_ transition: WindowVisibilityTransition) {
    record(transition)
    for effect in transition.effects {
      switch effect {
      case .showWindow:
        showAndFocusWindow()
      case .focusEditor:
        focusEditor()
      case .flushPendingSource:
        flushPendingSource()
      case .orderOut:
        window?.orderOut(nil)
      case .closeWindow:
        isExecutingClose = true
        window?.close()
        isExecutingClose = false
      case .applyWindowPolicy:
        applyWindowPolicy()
      }
    }
  }

  private func record(_ transition: WindowVisibilityTransition) {
    let effects = transition.effects.map { String(describing: $0) }.joined(separator: ",")
    model.appendLog(
      "event=\(String(describing: transition.event)) visible=\(transition.current.isVisible) active=\(transition.current.isApplicationActive) pinned=\(transition.current.isPinned) suspensions=\(transition.current.suspensions.count) effects=[\(effects)]"
    )
  }

  private func showAndFocusWindow() {
    if window == nil {
      createWindow()
    }
    placeWindow()
    let usesPanel = WindowPresentationPolicy.resolve(
      mode: model.configuration.mode,
      isPinned: model.configuration.isPinned
    ).usesPanel
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    if usesPanel {
      window?.orderFrontRegardless()
    }
    if let window {
      model.appendLog(
        "show-state visible=\(window.isVisible) key=\(window.isKeyWindow) active-space=\(window.isOnActiveSpace)"
      )
    }
    focusEditor()
  }

  private func focusEditor() {
    guard let window, window.isVisible else { return }
    model.requestEditorFocus()
    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, let window,
        let textView = self.findTextView(in: window.contentView)
      else { return }
      window.makeFirstResponder(textView)
      self.model.appendLog("focus-editor=\(window.firstResponder === textView)")
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

  private func flushPendingSource() {
    synchronizeDraftFromEditor()
    persistedDraft = model.draft
    model.recordFlush()
    model.appendLog("flush=utf16:\(persistedDraft.utf16.count)")
  }

  private func synchronizeDraftFromEditor() {
    guard let textView = findTextView(in: window?.contentView) else { return }
    model.draft = textView.string
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
    let policy = WindowPresentationPolicy.resolve(
      mode: model.configuration.mode,
      isPinned: model.configuration.isPinned
    )
    var styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
    let newWindow: NSWindow
    if policy.usesPanel {
      if policy.usesNonactivatingPanel {
        styleMask.insert(.nonactivatingPanel)
      }
      let panel = WindowSpikePanel(
        contentRect: .zero,
        styleMask: styleMask,
        backing: .buffered,
        defer: false
      )
      panel.isFloatingPanel = true
      panel.hidesOnDeactivate = false
      newWindow = panel
    } else {
      newWindow = NSWindow(
        contentRect: .zero,
        styleMask: styleMask,
        backing: .buffered,
        defer: false
      )
    }
    newWindow.title = "Window and Spaces Spike"
    newWindow.isReleasedWhenClosed = false
    newWindow.minSize =
      model.configuration.mode == .dropdownPanel
      ? DropdownDimensions.minimum
      : NSSize(width: 620, height: 440)
    newWindow.delegate = self
    newWindow.contentViewController = NSHostingController(rootView: WindowSpikeView(model: model))
    newWindow.setAccessibilityLabel("Window and Spaces Spike")
    window = newWindow
    visibleWindowCreations += 1
    applyWindowPolicy()
    model.appendLog("window-created count=\(visibleWindowCreations) mode=\(model.configuration.mode.rawValue)")
  }

  private func applyWindowPolicy() {
    guard let window else { return }
    let policy = WindowPresentationPolicy.resolve(
      mode: model.configuration.mode,
      isPinned: model.configuration.isPinned
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
    model.appendLog(
      "policy level=\(policy.level.rawValue) capabilities=\(policy.collectionCapabilities.map(\.rawValue).sorted().joined(separator: ","))"
    )
  }

  private func placeWindow() {
    guard let window, let screen = currentScreenGeometry() else { return }
    let requestedSize: CGSize
    let style: WindowPlacementStyle
    switch model.configuration.mode {
    case .standard:
      requestedSize = CGSize(width: 760, height: 620)
      style = .centered
    case .menuBarPanel:
      requestedSize = CGSize(width: 700, height: 580)
      style = .centered
    case .dropdownPanel:
      requestedSize = CGSize(
        width: model.configuration.dropdownDimensions.width,
        height: model.configuration.dropdownDimensions.height
      )
      style = .dropdown(anchorX: statusItemAnchorX(on: screen))
    }
    let frame = WindowPlacement.frame(requestedSize: requestedSize, on: screen, style: style)
    window.setFrame(frame, display: true)
    model.appendLog(
      "placement screen=\(screen.identifier) frame=\(NSStringFromRect(frame)) visible=\(WindowPlacement.isFullyVisible(frame, on: screen))"
    )
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
    guard
      screen.frame.contains(
        CGPoint(x: buttonWindow.frame.midX, y: buttonWindow.frame.midY)
      )
    else { return nil }
    return buttonWindow.frame.midX
  }

  private func updatePresence() {
    let presence = model.configuration.presence
    NSApp.setActivationPolicy(presence.showsDockIcon ? .regular : .accessory)
    if presence.showsStatusItem {
      if statusItem == nil {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
          systemSymbolName: "note.text",
          accessibilityDescription: "Toggle Window Spike"
        )
        item.button?.target = self
        item.button?.action = #selector(statusItemInvoked)
        item.button?.toolTip = "Toggle Window Spike"
        statusItem = item
      }
    } else if let statusItem {
      NSStatusBar.system.removeStatusItem(statusItem)
      self.statusItem = nil
    }
  }

  private func beginOwnedPanel(_ kind: OwnedPanelKind) -> AutoHideSuspension {
    let suspension = AutoHideSuspension(kind: kind)
    execute(visibility.transition(.beginOwnedPanel(suspension)))
    return suspension
  }

  private func endOwnedPanel(_ suspension: AutoHideSuspension) {
    execute(visibility.transition(.endOwnedPanel(suspension)))
  }
}

private final class WindowSpikePanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
