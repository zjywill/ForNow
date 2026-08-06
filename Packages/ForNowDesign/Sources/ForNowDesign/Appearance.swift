import AppKit
import Foundation

public enum InterfaceAppearance: String, CaseIterable, Codable, Sendable {
  case light
  case dark

  public var displayName: String {
    switch self {
    case .light:
      "Light"
    case .dark:
      "Dark"
    }
  }
}

public struct ThemeColor: Codable, Equatable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = Self.clamp(red)
    self.green = Self.clamp(green)
    self.blue = Self.clamp(blue)
    self.alpha = Self.clamp(alpha)
  }

  public var nsColor: NSColor {
    NSColor(
      srgbRed: red,
      green: green,
      blue: blue,
      alpha: alpha
    )
  }

  public func contrastRatio(with other: ThemeColor) -> Double {
    let first = relativeLuminance
    let second = other.relativeLuminance
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)
  }

  public var relativeLuminance: Double {
    0.2126 * Self.linearized(red)
      + 0.7152 * Self.linearized(green)
      + 0.0722 * Self.linearized(blue)
  }

  private static func clamp(_ component: Double) -> Double {
    min(max(component, 0), 1)
  }

  private static func linearized(_ component: Double) -> Double {
    component <= 0.04045
      ? component / 12.92
      : pow((component + 0.055) / 1.055, 2.4)
  }
}

public struct SemanticTheme: Equatable, Sendable {
  public let id: BuiltInThemeID
  public let displayName: String
  public let intendedAppearance: InterfaceAppearance
  public let canvas: ThemeColor
  public let primaryText: ThemeColor
  public let secondaryText: ThemeColor
  public let controlFill: ThemeColor
  public let controlText: ThemeColor
  public let accent: ThemeColor
  public let paperMark: ThemeColor
  public let selection: ThemeColor

  public var minimumRequiredContrastRatio: Double { 4.5 }

  public var textContrastRatio: Double {
    primaryText.contrastRatio(with: canvas)
  }

  public var secondaryTextContrastRatio: Double {
    secondaryText.contrastRatio(with: canvas)
  }

  public var controlContrastRatio: Double {
    controlText.contrastRatio(with: controlFill)
  }

  public var passesContrastChecks: Bool {
    textContrastRatio >= minimumRequiredContrastRatio
      && secondaryTextContrastRatio >= minimumRequiredContrastRatio
      && controlContrastRatio >= minimumRequiredContrastRatio
  }
}

public enum BuiltInThemeID: String, CaseIterable, Codable, Sendable {
  case porcelainLight
  case sageLight
  case inkDark
  case charcoalDark

  public var theme: SemanticTheme {
    switch self {
    case .porcelainLight:
      SemanticTheme(
        id: self,
        displayName: "Porcelain",
        intendedAppearance: .light,
        canvas: .hex(0xFAFAF7),
        primaryText: .hex(0x1D1D1F),
        secondaryText: .hex(0x55555B),
        controlFill: .hex(0xFFFFFF),
        controlText: .hex(0x1D1D1F),
        accent: .hex(0x0067C0),
        paperMark: .hex(0x6D7178),
        selection: .hex(0xB7D9F4)
      )
    case .sageLight:
      SemanticTheme(
        id: self,
        displayName: "Sage",
        intendedAppearance: .light,
        canvas: .hex(0xF3F8F5),
        primaryText: .hex(0x17211D),
        secondaryText: .hex(0x4C5B54),
        controlFill: .hex(0xFFFFFF),
        controlText: .hex(0x17211D),
        accent: .hex(0x006A55),
        paperMark: .hex(0x60766B),
        selection: .hex(0xB9E3D5)
      )
    case .inkDark:
      SemanticTheme(
        id: self,
        displayName: "Ink",
        intendedAppearance: .dark,
        canvas: .hex(0x1C1C1E),
        primaryText: .hex(0xF2F2F7),
        secondaryText: .hex(0xB8B8C0),
        controlFill: .hex(0x303034),
        controlText: .hex(0xF2F2F7),
        accent: .hex(0x64D2FF),
        paperMark: .hex(0x98989F),
        selection: .hex(0x164D67)
      )
    case .charcoalDark:
      SemanticTheme(
        id: self,
        displayName: "Charcoal",
        intendedAppearance: .dark,
        canvas: .hex(0x20211F),
        primaryText: .hex(0xF5F3ED),
        secondaryText: .hex(0xBBB9B0),
        controlFill: .hex(0x343631),
        controlText: .hex(0xF5F3ED),
        accent: .hex(0xFFD60A),
        paperMark: .hex(0x9C9D96),
        selection: .hex(0x5B5216)
      )
    }
  }

  public var displayName: String { theme.displayName }
  public var intendedAppearance: InterfaceAppearance { theme.intendedAppearance }
}

public enum PaperStyle: String, CaseIterable, Codable, Sendable {
  case blank
  case lined
  case dotted
  case smallGrid
  case largeGrid

  public var displayName: String {
    switch self {
    case .blank:
      "Blank"
    case .lined:
      "Lined"
    case .dotted:
      "Dotted"
    case .smallGrid:
      "Small Grid"
    case .largeGrid:
      "Large Grid"
    }
  }
}

public enum PaperOpacity: String, CaseIterable, Codable, Sendable {
  case subtle
  case clear
  case bold

  public var displayName: String {
    rawValue.capitalized
  }

  public var alpha: Double {
    switch self {
    case .subtle:
      0.12
    case .clear:
      0.22
    case .bold:
      0.36
    }
  }
}

public enum ListSpacing: String, CaseIterable, Codable, Sendable {
  case compact
  case regular
  case spacious

  public var displayName: String {
    rawValue.capitalized
  }

  public var points: Double {
    switch self {
    case .compact:
      2
    case .regular:
      6
    case .spacious:
      10
    }
  }
}

public enum EditorTextSize: String, CaseIterable, Codable, Sendable {
  case extraSmall
  case small
  case medium
  case large
  case extraLarge

  public var displayName: String {
    switch self {
    case .extraSmall:
      "XS"
    case .small:
      "S"
    case .medium:
      "M"
    case .large:
      "L"
    case .extraLarge:
      "XL"
    }
  }

  public var points: Double {
    switch self {
    case .extraSmall:
      14
    case .small:
      16
    case .medium:
      18
    case .large:
      21
    case .extraLarge:
      24
    }
  }

  public func stepped(by delta: Int) -> EditorTextSize {
    guard let index = Self.allCases.firstIndex(of: self) else { return self }
    let target = min(max(index + delta, 0), Self.allCases.count - 1)
    return Self.allCases[target]
  }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version: Int
  public var lightThemeID: BuiltInThemeID
  public var darkThemeID: BuiltInThemeID
  public var paperStyle: PaperStyle
  public var paperOpacity: PaperOpacity
  public var linedPaperListSpacing: ListSpacing
  public var blankPaperListSpacing: ListSpacing
  public var textSize: EditorTextSize
  public var doublesTextSize: Bool
  public var translucentModeEnabled: Bool
  public var backgroundOpacity: Int

  public init(
    version: Int = currentVersion,
    lightThemeID: BuiltInThemeID = .porcelainLight,
    darkThemeID: BuiltInThemeID = .inkDark,
    paperStyle: PaperStyle = .blank,
    paperOpacity: PaperOpacity = .clear,
    linedPaperListSpacing: ListSpacing = .compact,
    blankPaperListSpacing: ListSpacing = .regular,
    textSize: EditorTextSize = .medium,
    doublesTextSize: Bool = false,
    translucentModeEnabled: Bool = false,
    backgroundOpacity: Int = 70
  ) {
    self.version = version
    self.lightThemeID = lightThemeID
    self.darkThemeID = darkThemeID
    self.paperStyle = paperStyle
    self.paperOpacity = paperOpacity
    self.linedPaperListSpacing = linedPaperListSpacing
    self.blankPaperListSpacing = blankPaperListSpacing
    self.textSize = textSize
    self.doublesTextSize = doublesTextSize
    self.translucentModeEnabled = translucentModeEnabled
    self.backgroundOpacity = Self.clampedOpacity(backgroundOpacity)
  }

  public var effectiveTextSize: Double {
    textSize.points * (doublesTextSize ? 2 : 1)
  }

  public var effectiveListSpacing: ListSpacing {
    paperStyle == .lined ? linedPaperListSpacing : blankPaperListSpacing
  }

  public func theme(for appearance: InterfaceAppearance) -> SemanticTheme {
    switch appearance {
    case .light:
      lightThemeID.theme
    case .dark:
      darkThemeID.theme
    }
  }

  public func hasThemeMismatch(for appearance: InterfaceAppearance) -> Bool {
    theme(for: appearance).intendedAppearance != appearance
  }

  public mutating func stepTextSize(by delta: Int) {
    textSize = textSize.stepped(by: delta)
  }

  public mutating func normalize() {
    version = Self.currentVersion
    backgroundOpacity = Self.clampedOpacity(backgroundOpacity)
  }

  private static func clampedOpacity(_ value: Int) -> Int {
    min(max(value, 0), 90)
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case lightThemeID
    case darkThemeID
    case paperStyle
    case paperOpacity
    case linedPaperListSpacing
    case blankPaperListSpacing
    case textSize
    case doublesTextSize
    case translucentModeEnabled
    case backgroundOpacity
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = AppearanceSettings()
    version = try values.decodeIfPresent(Int.self, forKey: .version) ?? defaults.version
    lightThemeID =
      try values.decodeIfPresent(BuiltInThemeID.self, forKey: .lightThemeID)
      ?? defaults.lightThemeID
    darkThemeID =
      try values.decodeIfPresent(BuiltInThemeID.self, forKey: .darkThemeID)
      ?? defaults.darkThemeID
    paperStyle =
      try values.decodeIfPresent(PaperStyle.self, forKey: .paperStyle)
      ?? defaults.paperStyle
    paperOpacity =
      try values.decodeIfPresent(PaperOpacity.self, forKey: .paperOpacity)
      ?? defaults.paperOpacity
    linedPaperListSpacing =
      try values.decodeIfPresent(ListSpacing.self, forKey: .linedPaperListSpacing)
      ?? defaults.linedPaperListSpacing
    blankPaperListSpacing =
      try values.decodeIfPresent(ListSpacing.self, forKey: .blankPaperListSpacing)
      ?? defaults.blankPaperListSpacing
    textSize =
      try values.decodeIfPresent(EditorTextSize.self, forKey: .textSize)
      ?? defaults.textSize
    doublesTextSize =
      try values.decodeIfPresent(Bool.self, forKey: .doublesTextSize)
      ?? defaults.doublesTextSize
    translucentModeEnabled =
      try values.decodeIfPresent(Bool.self, forKey: .translucentModeEnabled)
      ?? defaults.translucentModeEnabled
    backgroundOpacity = Self.clampedOpacity(
      try values.decodeIfPresent(Int.self, forKey: .backgroundOpacity)
        ?? defaults.backgroundOpacity
    )
  }
}

public struct AppearanceEnvironment: Equatable, Sendable {
  public var operatingSystemMajorVersion: Int
  public var interfaceAppearance: InterfaceAppearance
  public var reducesTransparency: Bool
  public var increasesContrast: Bool

  public init(
    operatingSystemMajorVersion: Int,
    interfaceAppearance: InterfaceAppearance,
    reducesTransparency: Bool,
    increasesContrast: Bool
  ) {
    self.operatingSystemMajorVersion = operatingSystemMajorVersion
    self.interfaceAppearance = interfaceAppearance
    self.reducesTransparency = reducesTransparency
    self.increasesContrast = increasesContrast
  }
}

public struct AppearancePresentation: Equatable, Sendable {
  public let theme: SemanticTheme
  public let usesTranslucentMaterial: Bool
  public let backgroundAlpha: Double
  public let paperAlpha: Double
  public let drawsContrastBorder: Bool
  public let showsThemeMismatchWarning: Bool
  public let translucentModeIsAvailable: Bool

  public static func resolve(
    settings: AppearanceSettings,
    environment: AppearanceEnvironment
  ) -> AppearancePresentation {
    let available = environment.operatingSystemMajorVersion >= 15
    let usesMaterial =
      settings.translucentModeEnabled
      && available
      && !environment.reducesTransparency
    let theme = settings.theme(for: environment.interfaceAppearance)
    return AppearancePresentation(
      theme: theme,
      usesTranslucentMaterial: usesMaterial,
      backgroundAlpha:
        usesMaterial
        ? Double(min(max(settings.backgroundOpacity, 0), 90)) / 100
        : 1,
      paperAlpha: min(
        1,
        settings.paperOpacity.alpha * (environment.increasesContrast ? 1.55 : 1)
      ),
      drawsContrastBorder: environment.increasesContrast,
      showsThemeMismatchWarning: settings.hasThemeMismatch(
        for: environment.interfaceAppearance
      ),
      translucentModeIsAvailable: available
    )
  }
}

extension ThemeColor {
  fileprivate static func hex(_ value: UInt32) -> ThemeColor {
    ThemeColor(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }
}
