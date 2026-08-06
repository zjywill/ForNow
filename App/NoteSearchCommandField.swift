import AppKit
import SwiftUI

enum NoteSearchFieldCommand {
  case moveUp
  case moveDown
  case activate
  case dismiss
}

private final class CommandSearchField: NSSearchField {
  var commandHandler: ((NoteSearchFieldCommand) -> Void)?

  override func keyDown(with event: NSEvent) {
    let command: NoteSearchFieldCommand?
    switch event.keyCode {
    case 126:
      command = .moveUp
    case 125:
      command = .moveDown
    case 36, 76:
      command = .activate
    case 53:
      command = .dismiss
    default:
      command = nil
    }
    if let command {
      commandHandler?(command)
    } else {
      super.keyDown(with: event)
    }
  }
}

struct NoteSearchCommandField: NSViewRepresentable {
  let text: String
  let focusRequest: UInt64
  let textDidChange: (String) -> Void
  let commandHandler: (NoteSearchFieldCommand) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSSearchField {
    let searchField = CommandSearchField()
    searchField.delegate = context.coordinator
    searchField.commandHandler = commandHandler
    searchField.placeholderString = "Search notes"
    searchField.sendsSearchStringImmediately = true
    searchField.font = .systemFont(ofSize: 15)
    searchField.setAccessibilityLabel("Search notes")
    searchField.setAccessibilityIdentifier("Cross-note search")
    return searchField
  }

  func updateNSView(_ searchField: NSSearchField, context: Context) {
    context.coordinator.parent = self
    if searchField.stringValue != text {
      searchField.stringValue = text
    }
    (searchField as? CommandSearchField)?.commandHandler = commandHandler
    guard context.coordinator.lastFocusRequest != focusRequest else { return }
    context.coordinator.lastFocusRequest = focusRequest
    Task { @MainActor [weak searchField] in
      guard let searchField else { return }
      searchField.window?.makeFirstResponder(searchField)
    }
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: NoteSearchCommandField
    var lastFocusRequest: UInt64?

    init(parent: NoteSearchCommandField) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let searchField = notification.object as? NSSearchField else { return }
      parent.textDidChange(searchField.stringValue)
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      let command: NoteSearchFieldCommand?
      switch commandSelector {
      case #selector(NSResponder.moveUp(_:)):
        command = .moveUp
      case #selector(NSResponder.moveDown(_:)):
        command = .moveDown
      case #selector(NSResponder.insertNewline(_:)):
        command = .activate
      case #selector(NSResponder.cancelOperation(_:)):
        command = .dismiss
      default:
        command = nil
      }
      guard let command else { return false }
      parent.commandHandler(command)
      return true
    }
  }
}
