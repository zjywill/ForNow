import Combine
import ForNowEditor
import ForNowModes
import Foundation

@MainActor
final class SlashCommandModel: ObservableObject {
  @Published private(set) var isPresented = false
  @Published private(set) var query = ""
  @Published private(set) var commands: [SlashCommand] = []
  @Published private(set) var selectedIndex: Int?

  let editorTarget: EditorSlashCommandTarget
  var presentationDidChange: (@MainActor (Bool) -> Void)?

  private let engine: SlashCommandEngine
  private var settings = ModeSettings()

  init(
    editorTarget: EditorSlashCommandTarget = EditorSlashCommandTarget(),
    engine: SlashCommandEngine = SlashCommandEngine()
  ) {
    self.editorTarget = editorTarget
    self.engine = engine
    editorTarget.presentationRequested = { [weak self] in
      self?.present() ?? false
    }
    editorTarget.keyCommandHandler = { [weak self] key in
      self?.handleKeyCommand(key) ?? false
    }
  }

  var selectedCommand: SlashCommand? {
    guard let selectedIndex, commands.indices.contains(selectedIndex) else { return nil }
    return commands[selectedIndex]
  }

  @discardableResult
  func present() -> Bool {
    guard !isPresented else { return true }
    settings = editorTarget.modeSettings
    query = ""
    guard refreshCommands(), !commands.isEmpty else { return false }
    isPresented = true
    selectedIndex = 0
    editorTarget.setActive(true)
    presentationDidChange?(true)
    return true
  }

  func dismiss(restoresEditorFocus: Bool = true) {
    guard isPresented else { return }
    isPresented = false
    query = ""
    commands = []
    selectedIndex = nil
    editorTarget.setActive(false)
    presentationDidChange?(false)
    if restoresEditorFocus {
      editorTarget.focusEditor()
    }
  }

  func moveSelection(by delta: Int) {
    guard !commands.isEmpty else { return }
    let current = selectedIndex ?? (delta >= 0 ? -1 : 0)
    selectedIndex = (current + delta % commands.count + commands.count) % commands.count
  }

  @discardableResult
  func selectVisibleCommand(at index: Int) -> Bool {
    guard commands.indices.contains(index) else { return false }
    selectedIndex = index
    return performSelectedCommand()
  }

  @discardableResult
  func performSelectedCommand() -> Bool {
    guard let selectedCommand else { return false }
    do {
      guard
        let plan = try engine.editPlan(
          in: editorTarget.source,
          selection: editorTarget.selectedRange,
          selecting: selectedCommand.modeID,
          settings: settings
        ), editorTarget.apply(plan)
      else {
        dismiss()
        return false
      }
      dismiss()
      return true
    } catch {
      dismiss()
      return false
    }
  }

  @discardableResult
  func handleKeyCommand(_ key: EditorSlashCommandKey) -> Bool {
    guard isPresented else { return false }
    switch key {
    case .moveUp:
      moveSelection(by: -1)
    case .moveDown:
      moveSelection(by: 1)
    case .select:
      _ = performSelectedCommand()
    case .dismiss:
      dismiss()
    case .deleteBackward:
      if !query.isEmpty {
        query.removeLast()
        _ = refreshCommands()
      }
    case .selectNumber(let number):
      _ = selectVisibleCommand(at: number - 1)
    case .append(let text):
      query += text
      _ = refreshCommands()
    }
    return true
  }

  @discardableResult
  private func refreshCommands() -> Bool {
    let previousMode = selectedCommand?.modeID
    do {
      commands = try engine.commands(matching: query, settings: settings)
    } catch {
      commands = []
    }
    if let previousMode,
      let previousIndex = commands.firstIndex(where: { $0.modeID == previousMode })
    {
      selectedIndex = previousIndex
    } else {
      selectedIndex = commands.isEmpty ? nil : 0
    }
    return !commands.isEmpty
  }
}
