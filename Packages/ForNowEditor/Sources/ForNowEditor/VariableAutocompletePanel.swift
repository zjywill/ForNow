import AppKit
import ForNowModes

enum EditorVariableAutocompleteKey: Sendable, Equatable {
  case acceptFirst
  case acceptNumber(Int)
  case dismiss
}

@MainActor
final class VariableAutocompletePanelView: NSVisualEffectView {
  static let width: CGFloat = 280
  static let rowHeight: CGFloat = 30
  static let verticalPadding: CGFloat = 6

  init(
    context: VariableAutocompleteContext,
    selectionHandler: @escaping @MainActor (Int) -> Void
  ) {
    super.init(frame: .zero)
    material = .popover
    blendingMode = .withinWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = 6
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.separatorColor.cgColor
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Variable autocomplete")

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.distribution = .fillEqually
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
    ])

    for (index, suggestion) in context.suggestions.enumerated() {
      let button = VariableSuggestionButton(
        title: "\(index + 1)  \(suggestion.name)",
        handler: { selectionHandler(index) }
      )
      button.isBordered = false
      button.bezelStyle = .inline
      button.alignment = .left
      button.font = .systemFont(ofSize: 13, weight: .medium)
      button.lineBreakMode = .byTruncatingTail
      button.setAccessibilityLabel("Variable suggestion \(suggestion.name)")
      button.setAccessibilityValue("\(index + 1) of \(context.suggestions.count)")
      stack.addArrangedSubview(button)
      button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    frame.size = NSSize(
      width: Self.width,
      height: CGFloat(context.suggestions.count) * Self.rowHeight + Self.verticalPadding * 2
    )
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }
}

@MainActor
private final class VariableSuggestionButton: NSButton {
  private let handler: @MainActor () -> Void

  init(title: String, handler: @escaping @MainActor () -> Void) {
    self.handler = handler
    super.init(frame: .zero)
    self.title = title
    target = self
    action = #selector(activateSuggestion(_:))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  @objc private func activateSuggestion(_ sender: Any?) {
    handler()
  }
}
