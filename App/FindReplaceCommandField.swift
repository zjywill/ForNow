import AppKit
import SwiftUI

enum FindReplaceFieldRole {
  case find
  case replacement
}

enum FindReplaceFieldCommand: Equatable {
  case nextMatch
  case previousMatch
  case showReplacement
  case replaceCurrent
  case replaceAll
  case dismiss
}

struct FindReplaceCommandRouter {
  static func command(
    for selector: Selector,
    role: FindReplaceFieldRole,
    hasShiftModifier: Bool
  ) -> FindReplaceFieldCommand? {
    switch selector {
    case #selector(NSResponder.insertNewline(_:)),
      #selector(NSResponder.insertLineBreak(_:)):
      switch role {
      case .find:
        return hasShiftModifier ? .previousMatch : .nextMatch
      case .replacement:
        return hasShiftModifier ? .replaceAll : .replaceCurrent
      }
    case #selector(NSResponder.insertTab(_:)) where role == .find:
      return .showReplacement
    case #selector(NSResponder.cancelOperation(_:)):
      return .dismiss
    default:
      return nil
    }
  }
}

private final class FindReplaceTextField: NSTextField {
  var role = FindReplaceFieldRole.find
  var commandHandler: ((FindReplaceFieldCommand) -> Void)?
}

struct FindReplaceCommandField: NSViewRepresentable {
  let text: String
  let role: FindReplaceFieldRole
  let placeholder: String
  let accessibilityIdentifier: String
  let focusRequest: UInt64
  let textDidChange: (String) -> Void
  let commandHandler: (FindReplaceFieldCommand) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSTextField {
    let field = FindReplaceTextField()
    field.delegate = context.coordinator
    field.role = role
    field.commandHandler = commandHandler
    field.placeholderString = placeholder
    field.font = .systemFont(ofSize: 13)
    field.isBezeled = true
    field.bezelStyle = .roundedBezel
    field.focusRingType = .exterior
    field.setAccessibilityLabel(placeholder)
    field.setAccessibilityIdentifier(accessibilityIdentifier)
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != text {
      field.stringValue = text
    }
    if let field = field as? FindReplaceTextField {
      field.role = role
      field.commandHandler = commandHandler
    }
    guard context.coordinator.lastFocusRequest != focusRequest else { return }
    context.coordinator.lastFocusRequest = focusRequest
    Task { @MainActor [weak field] in
      guard let field else { return }
      field.window?.makeFirstResponder(field)
      field.selectText(nil)
    }
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: FindReplaceCommandField
    var lastFocusRequest: UInt64?

    init(parent: FindReplaceCommandField) {
      self.parent = parent
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.textDidChange(field.stringValue)
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      let hasShiftModifier =
        NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask)
        .contains(.shift) == true
      guard
        let command = FindReplaceCommandRouter.command(
          for: commandSelector,
          role: parent.role,
          hasShiftModifier: hasShiftModifier
        )
      else { return false }
      parent.commandHandler(command)
      return true
    }
  }
}
