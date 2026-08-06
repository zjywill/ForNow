import Combine
import ForNowCore
import ForNowIntegrations
import ForNowModes
import Foundation

enum AutoPastePhase: Equatable, Sendable {
  case inactive
  case requestingAccess
  case active
  case stopping
}

enum AutoPasteStopReason: Equatable, Sendable {
  case escape
  case repeatedCommand
  case indicator
  case destinationDeleted
  case destinationUnavailable
  case appTermination
  case failure
}

enum AutoPasteAppendOutcome: Equatable, Sendable {
  case appended
  case destinationBusy
  case destinationUnavailable
}

struct AutoPasteSession: Equatable, Sendable {
  let id: UUID
  let destinationNoteID: NoteID
  let destinationName: String
  let policy: AutoPasteCapturePolicy
  var captureCount: Int
}

@MainActor
final class AutoPasteModel: ObservableObject {
  typealias AppendHandler = @MainActor @Sendable (
    _ destinationNoteID: NoteID,
    _ capturedText: String,
    _ policy: AutoPasteCapturePolicy,
    _ capturedAt: Date,
    _ isFirstCapture: Bool
  ) async throws -> AutoPasteAppendOutcome

  @Published private(set) var phase = AutoPastePhase.inactive
  @Published private(set) var session: AutoPasteSession?
  @Published private(set) var settings = AutoPasteSettings()
  @Published private(set) var lastStopReason: AutoPasteStopReason?
  @Published private(set) var errorMessage: String?
  @Published private(set) var hasSettingsPersistenceFailure = false

  var isActive: Bool {
    phase == .active && session != nil
  }

  private struct PendingCapture {
    let text: String
    let capturedAt: Date
  }

  private let clipboard: any ClipboardService
  private let clock: any WallClock
  private let settingsStore: any AutoPasteSettingsStoring
  private let appendHandler: AppendHandler
  private var deduplicator = AutoPasteEventDeduplicator()
  private var pendingCaptures: [PendingCapture] = []
  private var processingTask: Task<Void, Never>?

  init(
    clipboard: any ClipboardService,
    clock: any WallClock,
    settingsStore: any AutoPasteSettingsStoring,
    appendHandler: @escaping AppendHandler
  ) {
    self.clipboard = clipboard
    self.clock = clock
    self.settingsStore = settingsStore
    self.appendHandler = appendHandler
  }

  func loadSettings() async {
    settings = await settingsStore.load()
    hasSettingsPersistenceFailure = false
  }

  func updateSettings(_ settings: AutoPasteSettings) async throws {
    let settings = try settings.validated()
    let previous = self.settings
    self.settings = settings
    do {
      try await settingsStore.save(settings)
      hasSettingsPersistenceFailure = false
    } catch {
      if self.settings == settings {
        self.settings = previous
      }
      hasSettingsPersistenceFailure = true
      throw error
    }
  }

  func startSession(
    destinationNoteID: NoteID,
    destinationName: String,
    command: AutoPasteCommand
  ) {
    guard phase == .inactive else { return }
    phase = .requestingAccess
    lastStopReason = nil
    errorMessage = nil
    pendingCaptures.removeAll(keepingCapacity: true)
    deduplicator = AutoPasteEventDeduplicator()
    let session = AutoPasteSession(
      id: UUID(),
      destinationNoteID: destinationNoteID,
      destinationName: destinationName,
      policy: AutoPasteCapturePolicy(
        settings: settings,
        separatorOverride: command.separatorOverride
      ),
      captureCount: 0
    )
    self.session = session
    clipboard.startMonitoring { [weak self] change in
      self?.receive(change)
    }
    phase = .active
  }

  func stop(_ reason: AutoPasteStopReason) {
    guard phase != .inactive else { return }
    phase = .stopping
    clipboard.stopMonitoring()
    processingTask?.cancel()
    processingTask = nil
    pendingCaptures.removeAll(keepingCapacity: false)
    session = nil
    lastStopReason = reason
    phase = .inactive
  }

  func stopIfDestination(_ noteID: NoteID, reason: AutoPasteStopReason) {
    guard session?.destinationNoteID == noteID else { return }
    stop(reason)
  }

  func markCurrentClipboardChangeAsOwn() {
    clipboard.markCurrentChangeAsOwn()
  }

  func dismissError() {
    errorMessage = nil
  }

  func waitForPendingEvents() async {
    await processingTask?.value
  }

  private func receive(_ change: ClipboardTextChange) {
    guard isActive, deduplicator.accepts(changeCount: change.changeCount, text: change.text)
    else { return }
    pendingCaptures.append(PendingCapture(text: change.text, capturedAt: clock.now()))
    startProcessingIfNeeded()
  }

  private func startProcessingIfNeeded() {
    guard processingTask == nil else { return }
    processingTask = Task { [weak self] in
      await self?.processPendingCaptures()
    }
  }

  private func processPendingCaptures() async {
    defer { processingTask = nil }
    while !Task.isCancelled, let activeSession = session, !pendingCaptures.isEmpty {
      let pending = pendingCaptures[0]
      do {
        let outcome = try await appendHandler(
          activeSession.destinationNoteID,
          pending.text,
          activeSession.policy,
          pending.capturedAt,
          activeSession.captureCount == 0
        )
        guard session?.id == activeSession.id else { return }
        switch outcome {
        case .appended:
          pendingCaptures.removeFirst()
          session?.captureCount += 1
        case .destinationBusy:
          try await Task.sleep(for: .milliseconds(100))
        case .destinationUnavailable:
          stop(.destinationUnavailable)
          return
        }
      } catch is CancellationError {
        return
      } catch {
        errorMessage = "AutoPaste stopped because the destination could not be updated."
        stop(.failure)
        return
      }
    }
  }
}
