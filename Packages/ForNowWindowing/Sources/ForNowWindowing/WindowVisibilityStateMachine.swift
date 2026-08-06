import Foundation

public enum WindowInvocationSource: String, Codable, Sendable {
  case localCommand
  case globalShortcut
  case statusItem
}

public enum OwnedPanelKind: String, Codable, Sendable {
  case settings
  case save
  case permission
  case confirmation
  case commandPicker
}

public struct AutoHideSuspension: Hashable, Sendable {
  public let id: UUID
  public let kind: OwnedPanelKind

  public init(id: UUID = UUID(), kind: OwnedPanelKind) {
    self.id = id
    self.kind = kind
  }
}

public struct WindowVisibilityState: Equatable, Sendable {
  public var isVisible: Bool
  public var isApplicationActive: Bool
  public var isPinned: Bool
  public var autoHideEnabled: Bool
  public var suspensions: Set<AutoHideSuspension>

  public init(
    isVisible: Bool = false,
    isApplicationActive: Bool = false,
    isPinned: Bool = false,
    autoHideEnabled: Bool = false,
    suspensions: Set<AutoHideSuspension> = []
  ) {
    self.isVisible = isVisible
    self.isApplicationActive = isApplicationActive
    self.isPinned = isPinned
    self.autoHideEnabled = autoHideEnabled
    self.suspensions = suspensions
  }

  public var shouldAutoHide: Bool {
    isVisible
      && !isApplicationActive
      && !isPinned
      && autoHideEnabled
      && suspensions.isEmpty
  }
}

public enum WindowVisibilityEvent: Equatable, Sendable {
  case show(WindowInvocationSource)
  case toggle(WindowInvocationSource)
  case close
  case applicationFocusChanged(Bool)
  case setPinned(Bool)
  case setAutoHide(Bool)
  case beginOwnedPanel(AutoHideSuspension)
  case endOwnedPanel(AutoHideSuspension)
}

public enum WindowVisibilityEffect: Equatable, Sendable {
  case showWindow
  case focusEditor
  case flushPendingSource
  case orderOut
  case closeWindow
  case applyWindowPolicy
}

public struct WindowVisibilityTransition: Equatable, Sendable {
  public let event: WindowVisibilityEvent
  public let previous: WindowVisibilityState
  public let current: WindowVisibilityState
  public let effects: [WindowVisibilityEffect]

  public init(
    event: WindowVisibilityEvent,
    previous: WindowVisibilityState,
    current: WindowVisibilityState,
    effects: [WindowVisibilityEffect]
  ) {
    self.event = event
    self.previous = previous
    self.current = current
    self.effects = effects
  }
}

public struct WindowVisibilityStateMachine: Sendable {
  public private(set) var state: WindowVisibilityState

  public init(state: WindowVisibilityState = WindowVisibilityState()) {
    self.state = state
  }

  @discardableResult
  public mutating func transition(
    _ event: WindowVisibilityEvent
  ) -> WindowVisibilityTransition {
    let previous = state
    var effects: [WindowVisibilityEffect] = []

    switch event {
    case .show:
      state.isApplicationActive = true
      if state.isVisible {
        effects = [.focusEditor]
      } else {
        state.isVisible = true
        effects = [.showWindow, .focusEditor]
      }
    case .toggle:
      if state.isVisible {
        state.isVisible = false
        effects = [.flushPendingSource, .orderOut]
      } else {
        state.isVisible = true
        state.isApplicationActive = true
        effects = [.showWindow, .focusEditor]
      }
    case .close:
      guard state.isVisible else { break }
      state.isVisible = false
      effects = [.flushPendingSource, .closeWindow]
    case .applicationFocusChanged(let isActive):
      state.isApplicationActive = isActive
      if isActive, state.isVisible {
        effects = [.focusEditor]
      } else if state.shouldAutoHide {
        state.isVisible = false
        effects = [.flushPendingSource, .orderOut]
      }
    case .setPinned(let isPinned):
      state.isPinned = isPinned
      effects = [.applyWindowPolicy]
      if state.shouldAutoHide {
        state.isVisible = false
        effects.append(contentsOf: [.flushPendingSource, .orderOut])
      }
    case .setAutoHide(let isEnabled):
      state.autoHideEnabled = isEnabled
      if state.shouldAutoHide {
        state.isVisible = false
        effects = [.flushPendingSource, .orderOut]
      }
    case .beginOwnedPanel(let suspension):
      state.suspensions.insert(suspension)
    case .endOwnedPanel(let suspension):
      state.suspensions.remove(suspension)
      if state.shouldAutoHide {
        state.isVisible = false
        effects = [.flushPendingSource, .orderOut]
      }
    }

    return WindowVisibilityTransition(
      event: event,
      previous: previous,
      current: state,
      effects: effects
    )
  }
}
