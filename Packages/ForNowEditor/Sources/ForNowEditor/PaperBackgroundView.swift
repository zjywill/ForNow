import AppKit
import ForNowDesign

@MainActor
final class PaperBackgroundView: NSView {
  var settings = AppearanceSettings() {
    didSet { needsDisplay = true }
  }
  var presentation = AppearancePresentation.resolve(
    settings: AppearanceSettings(),
    environment: AppearanceEnvironment(
      operatingSystemMajorVersion: 14,
      interfaceAppearance: .light,
      reducesTransparency: false,
      increasesContrast: false
    )
  ) {
    didSet { needsDisplay = true }
  }
  var lineHeight: CGFloat = 22 {
    didSet { needsDisplay = true }
  }
  var verticalScrollOffset: CGFloat = 0 {
    didSet { needsDisplay = true }
  }

  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let background = presentation.theme.canvas.nsColor.withAlphaComponent(
      presentation.backgroundAlpha
    )
    background.setFill()
    dirtyRect.fill()

    guard settings.paperStyle != .blank else { return }
    presentation.theme.paperMark.nsColor.withAlphaComponent(
      presentation.paperAlpha
    ).setStroke()
    presentation.theme.paperMark.nsColor.withAlphaComponent(
      presentation.paperAlpha
    ).setFill()

    switch settings.paperStyle {
    case .blank:
      break
    case .lined:
      drawLines(in: dirtyRect)
    case .dotted:
      drawDots(in: dirtyRect, spacing: 24)
    case .smallGrid:
      drawGrid(in: dirtyRect, spacing: 18)
    case .largeGrid:
      drawGrid(in: dirtyRect, spacing: 32)
    }
  }

  private func drawLines(in dirtyRect: NSRect) {
    let spacing = max(16, lineHeight + CGFloat(settings.effectiveListSpacing.points))
    let offset = normalizedOffset(spacing: spacing)
    let path = NSBezierPath()
    path.lineWidth = pixelWidth
    var y = 24 + lineHeight - offset
    while y <= bounds.maxY {
      if y >= dirtyRect.minY - pixelWidth {
        path.move(to: NSPoint(x: bounds.minX, y: y.rounded(.toNearestOrAwayFromZero)))
        path.line(to: NSPoint(x: bounds.maxX, y: y.rounded(.toNearestOrAwayFromZero)))
      }
      y += spacing
    }
    path.stroke()
  }

  private func drawDots(in dirtyRect: NSRect, spacing: CGFloat) {
    let offset = normalizedOffset(spacing: spacing)
    let radius = max(pixelWidth, 0.8)
    var y = spacing - offset
    while y <= bounds.maxY {
      var x = spacing
      while x <= bounds.maxX {
        let dot = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        if dirtyRect.intersects(dot) {
          NSBezierPath(ovalIn: dot).fill()
        }
        x += spacing
      }
      y += spacing
    }
  }

  private func drawGrid(in dirtyRect: NSRect, spacing: CGFloat) {
    let offset = normalizedOffset(spacing: spacing)
    let path = NSBezierPath()
    path.lineWidth = pixelWidth
    var x = spacing
    while x <= bounds.maxX {
      if x >= dirtyRect.minX - pixelWidth {
        path.move(to: NSPoint(x: x, y: bounds.minY))
        path.line(to: NSPoint(x: x, y: bounds.maxY))
      }
      x += spacing
    }
    var y = spacing - offset
    while y <= bounds.maxY {
      if y >= dirtyRect.minY - pixelWidth {
        path.move(to: NSPoint(x: bounds.minX, y: y))
        path.line(to: NSPoint(x: bounds.maxX, y: y))
      }
      y += spacing
    }
    path.stroke()
  }

  private func normalizedOffset(spacing: CGFloat) -> CGFloat {
    guard spacing > 0 else { return 0 }
    let remainder = verticalScrollOffset.truncatingRemainder(dividingBy: spacing)
    return remainder >= 0 ? remainder : remainder + spacing
  }

  private var pixelWidth: CGFloat {
    1 / max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1)
  }
}
