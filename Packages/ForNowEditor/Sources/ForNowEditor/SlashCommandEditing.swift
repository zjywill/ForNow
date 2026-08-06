import ForNowModes
import Foundation

public enum EditorSlashCommandKey: Sendable, Equatable {
  case moveUp
  case moveDown
  case select
  case dismiss
  case deleteBackward
  case selectNumber(Int)
  case append(String)
}

@MainActor
public final class EditorSlashCommandTarget: Sendable {
  public var presentationRequested: (@MainActor () -> Bool)?
  public var keyCommandHandler: (@MainActor (EditorSlashCommandKey) -> Bool)?

  private weak var container: ProjectionEditorContainer?

  public init() {}

  public var source: String {
    container?.slashCommandSource ?? ""
  }

  public var selectedRange: NSRange {
    container?.textView.selectedRange() ?? NSRange(location: 0, length: 0)
  }

  public var modeSettings: ModeSettings {
    container?.modeSettings ?? ModeSettings()
  }

  public func attach(to container: ProjectionEditorContainer) {
    guard self.container !== container else { return }
    self.container?.detachSlashCommandTarget(self)
    self.container = container
    container.attachSlashCommandTarget(self)
  }

  public func setActive(_ isActive: Bool) {
    container?.setSlashCommandActive(isActive)
  }

  @discardableResult
  public func apply(_ plan: SlashCommandEditPlan) -> Bool {
    container?.performSlashCommand(plan) ?? false
  }

  public func focusEditor() {
    container?.focusEditor()
  }

  func requestPresentation() -> Bool {
    presentationRequested?() ?? false
  }

  func handle(_ key: EditorSlashCommandKey) -> Bool {
    keyCommandHandler?(key) ?? false
  }
}
