import CoreGraphics
import Foundation

public struct ScreenGeometry: Equatable, Sendable {
  public let identifier: String
  public let frame: CGRect
  public let visibleFrame: CGRect

  public init(identifier: String, frame: CGRect, visibleFrame: CGRect) {
    self.identifier = identifier
    self.frame = frame
    self.visibleFrame = visibleFrame
  }
}

public enum WindowPlacementStyle: Sendable {
  case centered
  case dropdown(anchorX: CGFloat?)
}

public enum WindowPlacement {
  public static func targetScreen(
    containing point: CGPoint,
    screens: [ScreenGeometry]
  ) -> ScreenGeometry? {
    screens.first { $0.frame.contains(point) } ?? screens.first
  }

  public static func frame(
    requestedSize: CGSize,
    on screen: ScreenGeometry,
    style: WindowPlacementStyle
  ) -> CGRect {
    let visibleFrame = screen.visibleFrame
    let size = DropdownDimensions(
      width: requestedSize.width,
      height: requestedSize.height
    ).clamped(to: visibleFrame.size)

    let proposedOrigin: CGPoint
    switch style {
    case .centered:
      proposedOrigin = CGPoint(
        x: visibleFrame.midX - size.width / 2,
        y: visibleFrame.midY - size.height / 2
      )
    case .dropdown(let anchorX):
      proposedOrigin = CGPoint(
        x: (anchorX ?? visibleFrame.midX) - size.width / 2,
        y: visibleFrame.maxY - size.height
      )
    }

    let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
    let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
    let origin = CGPoint(
      x: min(max(proposedOrigin.x, visibleFrame.minX), maximumX),
      y: min(max(proposedOrigin.y, visibleFrame.minY), maximumY)
    )
    return CGRect(origin: origin, size: size)
  }

  public static func isFullyVisible(_ frame: CGRect, on screen: ScreenGeometry) -> Bool {
    screen.visibleFrame.contains(frame)
      || (frame.minX >= screen.visibleFrame.minX
        && frame.maxX <= screen.visibleFrame.maxX
        && frame.minY >= screen.visibleFrame.minY
        && frame.maxY <= screen.visibleFrame.maxY)
  }
}
