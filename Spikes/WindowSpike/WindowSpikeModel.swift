import Combine
import ForNowWindowing
import Foundation

@MainActor
final class WindowSpikeModel: ObservableObject {
  @Published private(set) var configuration = WindowConfiguration()
  @Published var draft = "# Window state fixture\n\nDraft survives presentation changes."
  @Published private(set) var status = "Starting"
  @Published private(set) var logEntries: [String] = []
  @Published private(set) var focusGeneration = 0
  @Published private(set) var flushCount = 0

  weak var coordinator: WindowSpikeCoordinator?

  var shortcut: GlobalShortcutCandidate {
    coordinator?.currentShortcut ?? .optionA
  }

  func setMode(_ mode: WindowPresentationMode) {
    guard configuration.mode != mode else { return }
    configuration.mode = mode
    coordinator?.presentationModeDidChange()
  }

  func setPresence(_ presence: ApplicationPresenceMode) {
    guard configuration.presence != presence else { return }
    configuration.presence = presence
    coordinator?.presenceDidChange()
  }

  func setPinned(_ isPinned: Bool) {
    guard configuration.isPinned != isPinned else { return }
    configuration.isPinned = isPinned
    coordinator?.pinDidChange()
  }

  func setAutoHide(_ isEnabled: Bool) {
    guard configuration.autoHideEnabled != isEnabled else { return }
    configuration.autoHideEnabled = isEnabled
    coordinator?.autoHideDidChange()
  }

  func setDropdownWidth(_ width: CGFloat) {
    configuration.dropdownDimensions.width = width
    coordinator?.dropdownDimensionsDidChange()
  }

  func setDropdownHeight(_ height: CGFloat) {
    configuration.dropdownDimensions.height = height
    coordinator?.dropdownDimensionsDidChange()
  }

  func applyShortcut(_ candidate: GlobalShortcutCandidate) -> ShortcutRegistrationResult {
    coordinator?.applyShortcut(candidate) ?? .failed(status: -1)
  }

  func appendLog(_ message: String) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let line = "\(formatter.string(from: Date())) \(message)"
    logEntries.append(line)
    if logEntries.count > 80 {
      logEntries.removeFirst(logEntries.count - 80)
    }
    status = message
    print(line)
  }

  func requestEditorFocus() {
    focusGeneration += 1
  }

  func recordFlush() {
    flushCount += 1
  }
}
