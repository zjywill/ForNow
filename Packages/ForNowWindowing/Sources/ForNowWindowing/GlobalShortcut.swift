import AppKit
import Carbon.HIToolbox
import Foundation
@preconcurrency import KeyboardShortcuts

public struct GlobalShortcutModifiers: OptionSet, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let command = GlobalShortcutModifiers(rawValue: 1 << 0)
  public static let control = GlobalShortcutModifiers(rawValue: 1 << 1)
  public static let option = GlobalShortcutModifiers(rawValue: 1 << 2)
  public static let shift = GlobalShortcutModifiers(rawValue: 1 << 3)
}

public struct GlobalShortcutCandidate: Hashable, Sendable {
  public let keyCode: Int
  public let modifiers: GlobalShortcutModifiers

  public init(keyCode: Int, modifiers: GlobalShortcutModifiers) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  public init(_ shortcut: KeyboardShortcuts.Shortcut) {
    keyCode = shortcut.carbonKeyCode
    var mapped: GlobalShortcutModifiers = []
    if shortcut.modifiers.contains(.command) { mapped.insert(.command) }
    if shortcut.modifiers.contains(.control) { mapped.insert(.control) }
    if shortcut.modifiers.contains(.option) { mapped.insert(.option) }
    if shortcut.modifiers.contains(.shift) { mapped.insert(.shift) }
    modifiers = mapped
  }

  public static let optionA = GlobalShortcutCandidate(
    keyCode: KeyboardShortcuts.Key.a.rawValue,
    modifiers: .option
  )

  public var usesOptionWithoutCommandOrControl: Bool {
    modifiers.contains(.option)
      && !modifiers.contains(.command)
      && !modifiers.contains(.control)
  }

  public var isEligibleForGlobalRegistration: Bool {
    !modifiers.isEmpty
  }

  public var shortcut: KeyboardShortcuts.Shortcut {
    var carbonModifiers = 0
    if modifiers.contains(.command) { carbonModifiers |= cmdKey }
    if modifiers.contains(.control) { carbonModifiers |= controlKey }
    if modifiers.contains(.option) { carbonModifiers |= optionKey }
    if modifiers.contains(.shift) { carbonModifiers |= shiftKey }
    return KeyboardShortcuts.Shortcut(
      carbonKeyCode: keyCode,
      carbonModifiers: carbonModifiers
    )
  }

  public var displayName: String {
    shortcut.description
  }
}

public enum ShortcutRegistrationResult: Equatable, Sendable {
  case accepted
  case invalid
  case conflict
  case optionOnlyUnavailable
  case failed(status: Int32)

  public var isAccepted: Bool {
    self == .accepted
  }

  public var message: String {
    switch self {
    case .accepted:
      "Shortcut registered"
    case .invalid:
      "Add Command, Control, or Option to the shortcut. The previous shortcut remains active."
    case .conflict:
      "This shortcut is already registered. The previous shortcut remains active."
    case .optionOnlyUnavailable:
      "Option-only global shortcuts are unavailable on macOS 15.0 and 15.1. Add Command or Control, or upgrade to macOS 15.2 or newer."
    case .failed(let status):
      "The shortcut could not be registered (OSStatus \(status)). The previous shortcut remains active."
    }
  }
}

public enum ShortcutRegistrationDiagnostic {
  public static func evaluate(
    status: Int32,
    candidate: GlobalShortcutCandidate,
    operatingSystem: OperatingSystemVersion
  ) -> ShortcutRegistrationResult {
    guard status != noErr else { return .accepted }
    if operatingSystem.majorVersion == 15,
      operatingSystem.minorVersion <= 1,
      candidate.usesOptionWithoutCommandOrControl
    {
      return .optionOnlyUnavailable
    }
    if status == eventHotKeyExistsErr {
      return .conflict
    }
    return .failed(status: status)
  }
}

public struct GlobalShortcutBindingState: Equatable, Sendable {
  public private(set) var current: GlobalShortcutCandidate

  public init(current: GlobalShortcutCandidate = .optionA) {
    self.current = current
  }

  @discardableResult
  public mutating func apply(
    _ candidate: GlobalShortcutCandidate,
    registrationStatus: Int32,
    operatingSystem: OperatingSystemVersion
  ) -> ShortcutRegistrationResult {
    guard candidate != current else { return .accepted }
    let result = ShortcutRegistrationDiagnostic.evaluate(
      status: registrationStatus,
      candidate: candidate,
      operatingSystem: operatingSystem
    )
    if result.isAccepted {
      current = candidate
    }
    return result
  }
}

@MainActor
public protocol GlobalShortcutPreflighting {
  func registrationStatus(for candidate: GlobalShortcutCandidate) -> Int32
}

@MainActor
public struct CarbonGlobalShortcutPreflight: GlobalShortcutPreflighting {
  private static var nextIdentifier: UInt32 = 1

  public init() {}

  public func registrationStatus(for candidate: GlobalShortcutCandidate) -> Int32 {
    let identifier = Self.nextIdentifier
    Self.nextIdentifier &+= 1
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(candidate.shortcut.carbonKeyCode),
      UInt32(candidate.shortcut.carbonModifiers),
      EventHotKeyID(signature: 0x464E_6F77, id: identifier),
      GetEventDispatcherTarget(),
      0,
      &reference
    )
    if let reference {
      UnregisterEventHotKey(reference)
    }
    return status
  }
}

@MainActor
public final class ValidatedGlobalShortcut {
  public let name: KeyboardShortcuts.Name
  public var current: GlobalShortcutCandidate { binding.current }

  private let preflight: any GlobalShortcutPreflighting
  private let operatingSystem: OperatingSystemVersion
  private var installed = false
  private var binding: GlobalShortcutBindingState

  public init(
    name: KeyboardShortcuts.Name,
    preflight: any GlobalShortcutPreflighting = CarbonGlobalShortcutPreflight(),
    operatingSystem: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
  ) {
    self.name = name
    self.preflight = preflight
    self.operatingSystem = operatingSystem
    binding = GlobalShortcutBindingState(
      current: KeyboardShortcuts.getShortcut(for: name).map(GlobalShortcutCandidate.init)
        ?? .optionA
    )
  }

  public convenience init(
    preflight: any GlobalShortcutPreflighting = CarbonGlobalShortcutPreflight(),
    operatingSystem: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
  ) {
    self.init(
      name: KeyboardShortcuts.Name("forNow.toggleWindow"),
      preflight: preflight,
      operatingSystem: operatingSystem
    )
  }

  public convenience init(
    nameIdentifier: String,
    preflight: any GlobalShortcutPreflighting,
    operatingSystem: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
  ) {
    self.init(
      name: KeyboardShortcuts.Name(nameIdentifier),
      preflight: preflight,
      operatingSystem: operatingSystem
    )
  }

  @discardableResult
  public func install(onKeyUp: @escaping @MainActor () -> Void) -> ShortcutRegistrationResult {
    let result = validate(current)
    guard result.isAccepted else { return result }
    KeyboardShortcuts.setShortcut(current.shortcut, for: name)
    KeyboardShortcuts.enable(name)
    if !installed {
      installed = true
      KeyboardShortcuts.onKeyUp(for: name) {
        MainActor.assumeIsolated {
          onKeyUp()
        }
      }
    }
    return result
  }

  public func uninstall() {
    KeyboardShortcuts.disable(name)
  }

  @discardableResult
  public func apply(_ candidate: GlobalShortcutCandidate) -> ShortcutRegistrationResult {
    guard candidate != current else { return .accepted }
    let result = binding.apply(
      candidate,
      registrationStatus: preflight.registrationStatus(for: candidate),
      operatingSystem: operatingSystem
    )
    guard result.isAccepted else { return result }
    KeyboardShortcuts.setShortcut(candidate.shortcut, for: name)
    return result
  }

  private func validate(_ candidate: GlobalShortcutCandidate) -> ShortcutRegistrationResult {
    ShortcutRegistrationDiagnostic.evaluate(
      status: preflight.registrationStatus(for: candidate),
      candidate: candidate,
      operatingSystem: operatingSystem
    )
  }
}
