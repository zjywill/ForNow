import AppKit
import SwiftUI

private final class NoteSearchAccessibilityElement: NSView {
  var activationHandler: (() -> Void)?

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func accessibilityPerformPress() -> Bool {
    activationHandler?()
    return true
  }
}

struct NoteSearchAccessibilityView: NSViewRepresentable {
  let label: String
  let isSelected: Bool
  let activationHandler: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NoteSearchAccessibilityElement()
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.button)
    update(view)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    guard let view = nsView as? NoteSearchAccessibilityElement else { return }
    update(view)
  }

  private func update(_ view: NoteSearchAccessibilityElement) {
    view.setAccessibilityLabel(label)
    view.setAccessibilityValue(isSelected ? "Selected" : "")
    view.activationHandler = activationHandler
  }
}
