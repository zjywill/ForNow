import CoreGraphics
import Foundation

public enum WindowPresentationMode: String, CaseIterable, Codable, Sendable {
  case standard
  case menuBarPanel
  case dropdownPanel
}

public enum ApplicationPresenceMode: String, CaseIterable, Codable, Sendable {
  case dock
  case menuBar
  case both
  case neither

  public var showsDockIcon: Bool {
    self == .dock || self == .both
  }

  public var showsStatusItem: Bool {
    self == .menuBar || self == .both
  }
}

public struct DropdownDimensions: Codable, Equatable, Sendable {
  public static let minimum = CGSize(width: 360, height: 280)

  public var width: CGFloat
  public var height: CGFloat

  public init(width: CGFloat = 560, height: CGFloat = 560) {
    self.width = width
    self.height = height
  }

  public func clamped(to visibleSize: CGSize) -> CGSize {
    CGSize(
      width: min(max(width, min(Self.minimum.width, visibleSize.width)), visibleSize.width),
      height: min(max(height, min(Self.minimum.height, visibleSize.height)), visibleSize.height)
    )
  }
}

public struct WindowConfiguration: Codable, Equatable, Sendable {
  public var mode: WindowPresentationMode
  public var presence: ApplicationPresenceMode
  public var isPinned: Bool
  public var autoHideEnabled: Bool
  public var dropdownDimensions: DropdownDimensions

  public init(
    mode: WindowPresentationMode = .standard,
    presence: ApplicationPresenceMode = .both,
    isPinned: Bool = false,
    autoHideEnabled: Bool = false,
    dropdownDimensions: DropdownDimensions = DropdownDimensions()
  ) {
    self.mode = mode
    self.presence = presence
    self.isPinned = isPinned
    self.autoHideEnabled = autoHideEnabled
    self.dropdownDimensions = dropdownDimensions
  }
}

public enum WindowLevelPolicy: String, Codable, Sendable {
  case normal
  case floating
  case statusBar
}

public enum WindowCollectionCapability: String, CaseIterable, Codable, Sendable {
  case managed
  case moveToActiveSpace
  case canJoinAllSpaces
  case fullScreenAuxiliary
  case transient
  case ignoresCycle
}

public struct WindowPresentationPolicy: Equatable, Sendable {
  public let level: WindowLevelPolicy
  public let collectionCapabilities: Set<WindowCollectionCapability>
  public let usesPanel: Bool
  public let usesNonactivatingPanel: Bool

  public init(
    level: WindowLevelPolicy,
    collectionCapabilities: Set<WindowCollectionCapability>,
    usesPanel: Bool,
    usesNonactivatingPanel: Bool
  ) {
    self.level = level
    self.collectionCapabilities = collectionCapabilities
    self.usesPanel = usesPanel
    self.usesNonactivatingPanel = usesNonactivatingPanel
  }

  public static func resolve(
    mode: WindowPresentationMode,
    isPinned: Bool
  ) -> WindowPresentationPolicy {
    switch mode {
    case .standard:
      return WindowPresentationPolicy(
        level: isPinned ? .floating : .normal,
        collectionCapabilities: [.managed, .moveToActiveSpace],
        usesPanel: false,
        usesNonactivatingPanel: false
      )
    case .menuBarPanel:
      return WindowPresentationPolicy(
        level: .floating,
        collectionCapabilities: [
          .canJoinAllSpaces,
          .fullScreenAuxiliary,
          .transient,
          .ignoresCycle,
        ],
        usesPanel: true,
        usesNonactivatingPanel: true
      )
    case .dropdownPanel:
      return WindowPresentationPolicy(
        level: .statusBar,
        collectionCapabilities: [
          .canJoinAllSpaces,
          .fullScreenAuxiliary,
          .transient,
          .ignoresCycle,
        ],
        usesPanel: true,
        usesNonactivatingPanel: true
      )
    }
  }
}
