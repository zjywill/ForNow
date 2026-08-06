import AppKit
import Combine
import ForNowCore
import ForNowDesign
import ForNowEditor
import ForNowIntegrations
import ForNowModes
import ForNowPersistence
import ForNowWindowing
import Foundation
import SwiftUI

@MainActor
struct AppDependencies {
  let repository: any NoteRepository
  let clock: any WallClock
  let monotonicClock: any MonotonicClock
  let uuidGenerator: any UUIDGenerating
  let parser: any SourceParsing
  let windowCoordinator: any WindowCoordinating
  let clipboard: any ClipboardService
  let autoPasteSettings: any AutoPasteSettingsStoring
  let ocr: any OCRService
  let ocrSettings: any OCRSettingsStoring
  let notifications: any NotificationService
  let rateProvider: any CurrencyRateProvider
  let rateCache: any CurrencyRateCaching
  let lifecycleSettings: any LifecycleSettingsStoring
  let windowSettings: any WindowSettingsStoring
  let pasteSettings: any PasteSettingsStoring
  let editorSettings: any EditorSettingsStoring
  let appearanceSettings: any AppearanceSettingsStoring
  let quickActionSettings: any QuickActionSettingsStoring
  let exportSettings: any ExportSettingsStoring
  let exportFileChooser: any ExportFileChoosing
  let externalURLOpener: any ExternalURLOpening
  let modeSettings: any ModeSettingsStoring
  let mathSettings: any MathSettingsStoring
  let timerSettings: any TimerSettingsStoring
  let timerSoundPlayer: any TimerSoundPlaying
  let expandedLinkState: any ExpandedLinkStateStoring
  let logger: any AppLifecycleLogging
}

enum AppEnvironmentVariant: String, Equatable, Sendable {
  case production
  case preview
  case test
}

enum AppEnvironmentState: Equatable, Sendable {
  case idle
  case starting
  case running
  case stopping
  case stopped
  case failed
}

@MainActor
final class AppEnvironment: ObservableObject {
  let appName = "ForNow"
  let variant: AppEnvironmentVariant
  let repository: any NoteRepository
  let clock: any WallClock
  let monotonicClock: any MonotonicClock
  let uuidGenerator: any UUIDGenerating
  let parser: any SourceParsing
  let windowCoordinator: any WindowCoordinating
  let clipboard: any ClipboardService
  let autoPasteSettingsStore: any AutoPasteSettingsStoring
  let ocr: any OCRService
  let ocrSettingsStore: any OCRSettingsStoring
  let notifications: any NotificationService
  let rateProvider: any CurrencyRateProvider
  let rateCache: any CurrencyRateCaching
  let lifecycleSettings: any LifecycleSettingsStoring
  let windowSettings: any WindowSettingsStoring
  let pasteSettingsStore: any PasteSettingsStoring
  let editorSettingsStore: any EditorSettingsStoring
  let appearanceSettingsStore: any AppearanceSettingsStoring
  let quickActionSettingsStore: any QuickActionSettingsStoring
  let exportSettingsStore: any ExportSettingsStoring
  let exportFileChooser: any ExportFileChoosing
  let externalURLOpener: any ExternalURLOpening
  let modeSettingsStore: any ModeSettingsStoring
  let mathSettingsStore: any MathSettingsStoring
  let timerSettingsStore: any TimerSettingsStoring
  let timerSoundPlayer: any TimerSoundPlaying
  let expandedLinkStateStore: any ExpandedLinkStateStoring
  let logger: any AppLifecycleLogging
  let noteSession: NoteSessionModel
  let noteSearch: NoteSearchModel
  let findReplace: FindReplaceModel
  let slashCommand: SlashCommandModel
  let deleteConfirmationCoordinator: DeleteConfirmationCoordinator
  let bulkDeletionConfirmationCoordinator: BulkDeletionConfirmationCoordinator
  let timerModel: TimerModel
  let ocrModel: OCRWorkflowModel
  let autoPasteModel: AutoPasteModel
  private let currencyRateCoordinator: CurrencyRateRefreshCoordinator

  @Published private(set) var windowConfiguration = WindowConfiguration()
  @Published private(set) var pasteSettings = PasteSettings()
  @Published private(set) var editorSettings = EditorSettings()
  @Published private(set) var appearanceSettings = AppearanceSettings()
  @Published private(set) var quickActionSettings = QuickActionSettings()
  @Published private(set) var exportSettings = ExportSettings()
  @Published private(set) var exportDestinationDiagnostic = ExportDestinationDiagnostic(
    status: .available,
    message: "A save location will be requested."
  )
  @Published private(set) var isExporting = false
  @Published private(set) var exportErrorMessage: String?
  @Published private(set) var lastExportReceipt: ExportReceipt?
  @Published private(set) var lastExpirationReceipt: ExpirationDeletionReceipt?
  @Published private(set) var expirationErrorMessage: String?
  @Published private(set) var bulkDeletionPreview: BulkDeletionPreview?
  @Published private(set) var lastBulkDeletionReceipt: BulkDeletionReceipt?
  @Published private(set) var bulkDeletionErrorMessage: String?
  @Published private(set) var isBulkDeletionWorking = false
  @Published private(set) var modeSettings = ModeSettings()
  @Published private(set) var mathSettings = MathSettings()
  @Published private(set) var rateSnapshot: RateSnapshot?
  @Published private(set) var currencyRateRefreshState = CurrencyRateRefreshState.idle
  @Published private(set) var expandedLinkState: [UUID: Set<LinkIdentity>] = [:]
  @Published private(set) var currentGlobalShortcut = GlobalShortcutCandidate.optionA
  @Published private(set) var shortcutRegistrationResult: ShortcutRegistrationResult = .accepted

  private(set) var state: AppEnvironmentState = .idle
  private var repositoryIsPrepared = false
  private var notificationsAreStarted = false
  private var windowCoordinatorIsStarted = false
  private var timerIsStarted = false
  private var settingsSuspension: AutoHideSuspension?
  private var searchSuspension: AutoHideSuspension?
  private var findReplaceSuspension: AutoHideSuspension?
  private var slashCommandSuspension: AutoHideSuspension?
  private var automaticCurrencyRefreshTask: Task<Void, Never>?
  private var expirationScheduleTask: Task<Void, Never>?
  private var isProcessingExpiration = false

  init(variant: AppEnvironmentVariant, dependencies: AppDependencies) {
    self.variant = variant
    repository = dependencies.repository
    clock = dependencies.clock
    monotonicClock = dependencies.monotonicClock
    uuidGenerator = dependencies.uuidGenerator
    parser = dependencies.parser
    windowCoordinator = dependencies.windowCoordinator
    clipboard = dependencies.clipboard
    autoPasteSettingsStore = dependencies.autoPasteSettings
    ocr = dependencies.ocr
    ocrSettingsStore = dependencies.ocrSettings
    notifications = dependencies.notifications
    rateProvider = dependencies.rateProvider
    rateCache = dependencies.rateCache
    lifecycleSettings = dependencies.lifecycleSettings
    windowSettings = dependencies.windowSettings
    pasteSettingsStore = dependencies.pasteSettings
    editorSettingsStore = dependencies.editorSettings
    appearanceSettingsStore = dependencies.appearanceSettings
    quickActionSettingsStore = dependencies.quickActionSettings
    exportSettingsStore = dependencies.exportSettings
    exportFileChooser = dependencies.exportFileChooser
    externalURLOpener = dependencies.externalURLOpener
    modeSettingsStore = dependencies.modeSettings
    mathSettingsStore = dependencies.mathSettings
    timerSettingsStore = dependencies.timerSettings
    timerSoundPlayer = dependencies.timerSoundPlayer
    expandedLinkStateStore = dependencies.expandedLinkState
    logger = dependencies.logger
    currencyRateCoordinator = CurrencyRateRefreshCoordinator(
      provider: dependencies.rateProvider,
      cache: dependencies.rateCache,
      clock: dependencies.clock
    )
    let noteSession = NoteSessionModel(
      repository: dependencies.repository,
      clock: dependencies.clock,
      uuidGenerator: dependencies.uuidGenerator,
      settingsStore: dependencies.lifecycleSettings
    )
    self.noteSession = noteSession
    autoPasteModel = AutoPasteModel(
      clipboard: dependencies.clipboard,
      clock: dependencies.clock,
      settingsStore: dependencies.autoPasteSettings,
      appendHandler: { [weak noteSession] noteID, text, policy, capturedAt, isFirstCapture in
        guard let noteSession else { return .destinationUnavailable }
        return try await noteSession.appendAutoPasteCapture(
          to: noteID,
          capturedText: text,
          policy: policy,
          capturedAt: capturedAt,
          isFirstCapture: isFirstCapture
        )
      }
    )
    timerModel = TimerModel(
      timerClock: TimerClock(
        repository: dependencies.repository,
        wallClock: dependencies.clock,
        monotonicClock: dependencies.monotonicClock,
        uuidGenerator: dependencies.uuidGenerator
      ),
      wallClock: dependencies.clock,
      settingsStore: dependencies.timerSettings,
      notifications: dependencies.notifications,
      soundPlayer: dependencies.timerSoundPlayer,
      windowCoordinator: dependencies.windowCoordinator
    )
    ocrModel = OCRWorkflowModel(
      service: dependencies.ocr,
      settingsStore: dependencies.ocrSettings
    )
    findReplace = FindReplaceModel()
    slashCommand = SlashCommandModel()
    noteSearch = NoteSearchModel(
      repository: dependencies.repository,
      noteSession: noteSession,
      prepareLiveSource: {
        try await dependencies.windowCoordinator.flushPendingSourceForCommand()
      }
    )
    deleteConfirmationCoordinator = DeleteConfirmationCoordinator()
    bulkDeletionConfirmationCoordinator = BulkDeletionConfirmationCoordinator()
    windowCoordinator.configure(
      WindowCoordinatorCallbacks(
        makeContentViewController: { [weak self] in
          guard let self else { return NSViewController() }
          return NSHostingController(rootView: ContentView(environment: self))
        },
        flushPendingSource: { [weak self] source, hasMarkedText in
          guard let self else { return }
          try await self.flushWindowSource(source, hasMarkedText: hasMarkedText)
        },
        windowDidReopen: { [weak self] in
          guard let self else { return }
          try await self.reopenWindow()
        },
        windowDidClose: { [weak self] in
          try? await self?.windowWillClose()
        }
      )
    )
    slashCommand.presentationDidChange = { [weak self] isPresented in
      self?.slashCommandPresentationDidChange(isPresented)
    }
  }

  static func production(fileManager: FileManager = .default) -> AppEnvironment {
    let paths = ProductionPaths.standard(fileManager: fileManager)
    let rateCache = UserDefaultsCurrencyRateCache()
    return AppEnvironment(
      variant: .production,
      dependencies: AppDependencies(
        repository: PersistenceNoteRepository(
          databaseURL: paths.databaseURL,
          backupDirectoryURL: paths.backupDirectoryURL
        ),
        clock: SystemWallClock(),
        monotonicClock: SystemMonotonicClock(),
        uuidGenerator: SystemUUIDGenerator(),
        parser: PlainSourceParser(),
        windowCoordinator: SwiftUIWindowCoordinator(),
        clipboard: SystemClipboardService(),
        autoPasteSettings: UserDefaultsAutoPasteSettingsStore(),
        ocr: VisionOCRService(),
        ocrSettings: UserDefaultsOCRSettingsStore(),
        notifications: UserNotificationService(),
        rateProvider: CachedCurrencyRateProvider(
          upstream: ECBCurrencyRateProvider(),
          cache: rateCache
        ),
        rateCache: rateCache,
        lifecycleSettings: UserDefaultsLifecycleSettingsStore(),
        windowSettings: UserDefaultsWindowSettingsStore(),
        pasteSettings: UserDefaultsPasteSettingsStore(),
        editorSettings: UserDefaultsEditorSettingsStore(),
        appearanceSettings: UserDefaultsAppearanceSettingsStore(),
        quickActionSettings: UserDefaultsQuickActionSettingsStore(),
        exportSettings: UserDefaultsExportSettingsStore(),
        exportFileChooser: SystemExportFileChooser(),
        externalURLOpener: SystemExternalURLOpener(),
        modeSettings: UserDefaultsModeSettingsStore(),
        mathSettings: UserDefaultsMathSettingsStore(),
        timerSettings: UserDefaultsTimerSettingsStore(),
        timerSoundPlayer: SystemTimerSoundPlayer(),
        expandedLinkState: UserDefaultsExpandedLinkStateStore(),
        logger: OSLifecycleLogger()
      )
    )
  }

  static func preview() -> AppEnvironment {
    AppEnvironment(
      variant: .preview,
      dependencies: AppDependencies(
        repository: InMemoryNoteRepository(),
        clock: FixedWallClock(Date(timeIntervalSince1970: 0)),
        monotonicClock: ManualMonotonicClock(),
        uuidGenerator: SequenceUUIDGenerator(values: [Self.previewUUID]),
        parser: PlainSourceParser(),
        windowCoordinator: DisabledWindowCoordinator(),
        clipboard: DisabledClipboardService(),
        autoPasteSettings: InMemoryAutoPasteSettingsStore(),
        ocr: UnavailableOCRService(),
        ocrSettings: InMemoryOCRSettingsStore(),
        notifications: DisabledNotificationService(),
        rateProvider: DisabledCurrencyRateProvider(),
        rateCache: InMemoryCurrencyRateCache(),
        lifecycleSettings: InMemoryLifecycleSettingsStore(),
        windowSettings: InMemoryWindowSettingsStore(),
        pasteSettings: InMemoryPasteSettingsStore(),
        editorSettings: InMemoryEditorSettingsStore(),
        appearanceSettings: InMemoryAppearanceSettingsStore(),
        quickActionSettings: InMemoryQuickActionSettingsStore(),
        exportSettings: InMemoryExportSettingsStore(),
        exportFileChooser: CancelledExportFileChooser(),
        externalURLOpener: UnavailableExternalURLOpener(),
        modeSettings: InMemoryModeSettingsStore(),
        mathSettings: InMemoryMathSettingsStore(),
        timerSettings: InMemoryTimerSettingsStore(),
        timerSoundPlayer: DisabledTimerSoundPlayer(),
        expandedLinkState: InMemoryExpandedLinkStateStore(),
        logger: InMemoryLifecycleLogger()
      )
    )
  }

  static func uiTest() -> AppEnvironment {
    test(
      windowCoordinator: SwiftUIWindowCoordinator(),
      clipboard: SystemClipboardService(),
      lifecycleSettings: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: true)
      )
    )
  }

  static func test(
    repository: any NoteRepository = InMemoryNoteRepository(),
    clock: any WallClock = FixedWallClock(Date(timeIntervalSince1970: 0)),
    monotonicClock: any MonotonicClock = ManualMonotonicClock(),
    uuidGenerator: any UUIDGenerating = SequenceUUIDGenerator(values: [previewUUID]),
    parser: any SourceParsing = PlainSourceParser(),
    windowCoordinator: any WindowCoordinating = DisabledWindowCoordinator(),
    clipboard: any ClipboardService = DisabledClipboardService(),
    autoPasteSettings: any AutoPasteSettingsStoring = InMemoryAutoPasteSettingsStore(),
    ocr: any OCRService = UnavailableOCRService(),
    ocrSettings: any OCRSettingsStoring = InMemoryOCRSettingsStore(),
    notifications: any NotificationService = DisabledNotificationService(),
    rateProvider: any CurrencyRateProvider = DisabledCurrencyRateProvider(),
    rateCache: any CurrencyRateCaching = InMemoryCurrencyRateCache(),
    lifecycleSettings: any LifecycleSettingsStoring = InMemoryLifecycleSettingsStore(),
    windowSettings: any WindowSettingsStoring = InMemoryWindowSettingsStore(),
    pasteSettings: any PasteSettingsStoring = InMemoryPasteSettingsStore(),
    editorSettings: any EditorSettingsStoring = InMemoryEditorSettingsStore(),
    appearanceSettings: any AppearanceSettingsStoring = InMemoryAppearanceSettingsStore(),
    quickActionSettings: any QuickActionSettingsStoring = InMemoryQuickActionSettingsStore(),
    exportSettings: any ExportSettingsStoring = InMemoryExportSettingsStore(),
    exportFileChooser: any ExportFileChoosing = CancelledExportFileChooser(),
    externalURLOpener: any ExternalURLOpening = UnavailableExternalURLOpener(),
    modeSettings: any ModeSettingsStoring = InMemoryModeSettingsStore(),
    mathSettings: any MathSettingsStoring = InMemoryMathSettingsStore(),
    timerSettings: any TimerSettingsStoring = InMemoryTimerSettingsStore(),
    timerSoundPlayer: any TimerSoundPlaying = DisabledTimerSoundPlayer(),
    expandedLinkState: any ExpandedLinkStateStoring = InMemoryExpandedLinkStateStore(),
    logger: any AppLifecycleLogging = InMemoryLifecycleLogger()
  ) -> AppEnvironment {
    AppEnvironment(
      variant: .test,
      dependencies: AppDependencies(
        repository: repository,
        clock: clock,
        monotonicClock: monotonicClock,
        uuidGenerator: uuidGenerator,
        parser: parser,
        windowCoordinator: windowCoordinator,
        clipboard: clipboard,
        autoPasteSettings: autoPasteSettings,
        ocr: ocr,
        ocrSettings: ocrSettings,
        notifications: notifications,
        rateProvider: rateProvider,
        rateCache: rateCache,
        lifecycleSettings: lifecycleSettings,
        windowSettings: windowSettings,
        pasteSettings: pasteSettings,
        editorSettings: editorSettings,
        appearanceSettings: appearanceSettings,
        quickActionSettings: quickActionSettings,
        exportSettings: exportSettings,
        exportFileChooser: exportFileChooser,
        externalURLOpener: externalURLOpener,
        modeSettings: modeSettings,
        mathSettings: mathSettings,
        timerSettings: timerSettings,
        timerSoundPlayer: timerSoundPlayer,
        expandedLinkState: expandedLinkState,
        logger: logger
      )
    )
  }

  func start() async throws {
    guard state == .idle else { return }
    state = .starting
    await logger.record(.startupBegan)

    do {
      try await repository.prepare()
      repositoryIsPrepared = true
      await logger.record(.serviceStarted(.repository))
      lastExpirationReceipt = try await repository.deleteExpiredNotes(at: clock.now())
      windowConfiguration = await windowSettings.load()
      pasteSettings = await pasteSettingsStore.load()
      editorSettings = await editorSettingsStore.load()
      appearanceSettings = await appearanceSettingsStore.load()
      quickActionSettings = await quickActionSettingsStore.load()
      exportSettings = await exportSettingsStore.load()
      modeSettings = await modeSettingsStore.load()
      mathSettings = await mathSettingsStore.load()
      await autoPasteModel.loadSettings()
      rateSnapshot = await currencyRateCoordinator.cachedSnapshot(
        base: mathSettings.primaryCurrency
      )
      currencyRateRefreshState = rateSnapshot == nil ? .idle : .current
      try await noteSession.updateMeaningfulContentPolicy(
        meaningfulContentPolicy(for: modeSettings)
      )
      try await noteSession.start()
      await logger.record(.noteSessionLoaded)
      expandedLinkState = await expandedLinkStateStore.load()
      windowCoordinator.applyConfiguration(windowConfiguration)
      await notifications.start()
      notificationsAreStarted = true
      await logger.record(.serviceStarted(.notifications))
      windowCoordinator.start()
      windowCoordinatorIsStarted = true
      currentGlobalShortcut = windowCoordinator.currentShortcut
      shortcutRegistrationResult = windowCoordinator.lastShortcutRegistration
      await repairQuickActionSettingsIfNeeded()
      await refreshExportDestinationDiagnostic()
      await logger.record(.serviceStarted(.windowCoordinator))
      try await timerModel.start()
      timerIsStarted = true
      await ocrModel.start()
      state = .running
      await logger.record(.startupCompleted)
      scheduleAutomaticCurrencyRefreshIfNeeded()
      scheduleExpirationProcessing()
    } catch {
      state = .failed
      await logger.record(.startupFailed)
      throw error
    }
  }

  func shutdown() async throws {
    guard state != .stopping, state != .stopped else { return }
    state = .stopping
    await logger.record(.shutdownBegan)

    automaticCurrencyRefreshTask?.cancel()
    await automaticCurrencyRefreshTask?.value
    automaticCurrencyRefreshTask = nil
    expirationScheduleTask?.cancel()
    await expirationScheduleTask?.value
    expirationScheduleTask = nil
    while isProcessingExpiration || isBulkDeletionWorking {
      await Task.yield()
    }

    var firstError: (any Error)?
    releaseSearch(restoresEditorFocus: false)
    releaseFindReplace(restoresEditorFocus: false)
    releaseSlashCommand(restoresEditorFocus: false)
    ocrModel.cancel()
    autoPasteModel.stop(.appTermination)
    await windowCoordinator.waitForPendingTransitions()
    if repositoryIsPrepared {
      do {
        try await noteSession.prepareForDeparture()
        await logger.record(.noteSessionPrepared)
      } catch {
        firstError = error
        await logger.record(.noteSessionPreparationFailed)
      }
    }
    if timerIsStarted {
      do {
        try await timerModel.prepareForQuit()
      } catch {
        if firstError == nil {
          firstError = error
        }
      }
      timerIsStarted = false
    }
    if repositoryIsPrepared {
      do {
        _ = try await repository.flush()
        await logger.record(.repositoryFlushed)
      } catch {
        firstError = error
        await logger.record(.repositoryFlushFailed)
      }
    } else {
      await logger.record(.repositoryFlushSkipped)
    }

    if windowCoordinatorIsStarted {
      windowCoordinator.stop()
      windowCoordinatorIsStarted = false
      await logger.record(.serviceStopped(.windowCoordinator))
    }
    if notificationsAreStarted {
      await notifications.stop()
      notificationsAreStarted = false
      await logger.record(.serviceStopped(.notifications))
    }
    if repositoryIsPrepared {
      do {
        try await repository.shutdown()
        repositoryIsPrepared = false
        await logger.record(.serviceStopped(.repository))
      } catch {
        if firstError == nil {
          firstError = error
        }
        await logger.record(.repositoryShutdownFailed)
      }
    }

    if let firstError {
      state = .failed
      await logger.record(.shutdownFailed)
      throw firstError
    }

    state = .stopped
    await logger.record(.shutdownCompleted)
  }

  func reopenWindow() async throws {
    guard state == .running else { return }
    try await noteSession.reopen()
  }

  func windowWillClose() async throws {
    ocrModel.cancel()
    let closeDate = clock.now()
    do {
      if repositoryIsPrepared {
        try await noteSession.prepareForDeparture()
      }
    } catch {
      await lifecycleSettings.recordWindowClosed(at: closeDate)
      throw error
    }
    await lifecycleSettings.recordWindowClosed(at: closeDate)
  }

  func deleteCurrentNote() async throws {
    let deletingNoteID = noteSession.currentNoteID
    let outcome = try await noteSession.requestDeletion()
    guard outcome == .confirmationRequired else {
      if outcome == .deleted, let deletingNoteID {
        autoPasteModel.stopIfDestination(deletingNoteID, reason: .destinationDeleted)
        try await timerModel.removeTimer(linkedTo: deletingNoteID)
      }
      return
    }
    let suspension = windowCoordinator.beginOwnedPanel(.confirmation)
    defer { windowCoordinator.endOwnedPanel(suspension) }
    let result = await deleteConfirmationCoordinator.requestConfirmation()
    try await noteSession.resolveDeletion(
      confirm: result.confirmsDeletion,
      suppressFutureWarning: result.suppressesFutureWarning
    )
    if result.confirmsDeletion, let deletingNoteID {
      autoPasteModel.stopIfDestination(deletingNoteID, reason: .destinationDeleted)
      try await timerModel.removeTimer(linkedTo: deletingNoteID)
    }
  }

  func updateExpirationChoice(_ choice: NoteExpirationChoice) async throws {
    guard choice != noteSession.settings.noteExpirationChoice else { return }
    try await windowCoordinator.flushPendingSourceForCommand()
    var settings = noteSession.settings
    settings.noteExpirationChoice = choice
    try await noteSession.updateSettings(settings)
    _ = try await processExpiredNotes()
  }

  @discardableResult
  func processExpiredNotes() async throws -> ExpirationDeletionReceipt? {
    guard state == .running, repositoryIsPrepared, !isProcessingExpiration else { return nil }
    isProcessingExpiration = true
    defer { isProcessingExpiration = false }
    do {
      let receipt = try await repository.deleteExpiredNotes(at: clock.now())
      lastExpirationReceipt = receipt
      expirationErrorMessage = nil
      try await reconcileDeletedNoteIDs(receipt.deletedNoteIDs)
      return receipt
    } catch {
      expirationErrorMessage = error.localizedDescription
      throw error
    }
  }

  func synchronizeWallClock() async {
    await timerModel.synchronizeClock()
    do {
      _ = try await processExpiredNotes()
    } catch {
      NSSound.beep()
    }
  }

  @discardableResult
  func previewBulkDeletion(before cutoff: Date) async throws -> BulkDeletionPreview {
    guard !isBulkDeletionWorking else { throw BulkDeletionOperationError.inProgress }
    isBulkDeletionWorking = true
    defer { isBulkDeletionWorking = false }
    do {
      try await windowCoordinator.flushPendingSourceForCommand()
      _ = try await repository.flush()
      let preview = try await repository.previewBulkDeletion(before: cutoff)
      bulkDeletionPreview = preview
      lastBulkDeletionReceipt = nil
      bulkDeletionErrorMessage = nil
      return preview
    } catch {
      bulkDeletionErrorMessage = error.localizedDescription
      throw error
    }
  }

  func cancelBulkDeletion() {
    bulkDeletionPreview = nil
    bulkDeletionErrorMessage = nil
  }

  @discardableResult
  func confirmBulkDeletion() async throws -> BulkDeletionReceipt? {
    guard let preview = bulkDeletionPreview, preview.count > 0, !isBulkDeletionWorking else {
      return nil
    }
    isBulkDeletionWorking = true
    defer { isBulkDeletionWorking = false }
    do {
      try await windowCoordinator.flushPendingSourceForCommand()
      _ = try await repository.flush()
      let receipt = try await repository.confirmBulkDeletion(
        preview,
        backupAt: clock.now()
      )
      lastBulkDeletionReceipt = receipt
      bulkDeletionPreview = nil
      bulkDeletionErrorMessage = nil
      try await reconcileDeletedNoteIDs(receipt.deletedNoteIDs)
      return receipt
    } catch {
      bulkDeletionErrorMessage = error.localizedDescription
      throw error
    }
  }

  @discardableResult
  func requestBulkDeletionConfirmation() async throws -> BulkDeletionReceipt? {
    guard let preview = bulkDeletionPreview, preview.count > 0 else { return nil }
    let suspension = windowCoordinator.beginOwnedPanel(.confirmation)
    defer { windowCoordinator.endOwnedPanel(suspension) }
    guard await bulkDeletionConfirmationCoordinator.requestConfirmation(for: preview) else {
      cancelBulkDeletion()
      return nil
    }
    return try await confirmBulkDeletion()
  }

  func executeTimerCommand(_ command: TimerCommand, source: String) async throws {
    guard state == .running else { return }
    try await noteSession.applyEditorText(source, hasMarkedText: false)
    try await noteSession.prepareForDeparture()
    _ = try await repository.flush()
    guard let noteID = noteSession.currentNoteID else { return }
    try await timerModel.perform(command, noteID: noteID)
  }

  func executeAutoPasteCommand(_ command: AutoPasteCommand, source: String) async throws {
    guard state == .running else { return }
    try await noteSession.applyEditorText(source, hasMarkedText: false)
    try await noteSession.prepareForDeparture()
    _ = try await repository.flush()
    if autoPasteModel.isActive {
      autoPasteModel.stop(.repeatedCommand)
      return
    }
    guard let noteID = noteSession.currentNoteID else { return }
    autoPasteModel.startSession(
      destinationNoteID: noteID,
      destinationName: AutoPasteDestinationName().resolve(from: source),
      command: command
    )
  }

  func stopAutoPaste(_ reason: AutoPasteStopReason) {
    autoPasteModel.stop(reason)
  }

  func markCurrentClipboardChangeAsOwn() {
    autoPasteModel.markCurrentClipboardChangeAsOwn()
  }

  func stopCurrentTimer() async {
    try? await timerModel.handleStop()
  }

  func openSearch() {
    guard state == .running else { return }
    releaseFindReplace(restoresEditorFocus: false)
    releaseSlashCommand(restoresEditorFocus: false)
    if searchSuspension == nil {
      searchSuspension = windowCoordinator.beginOwnedPanel(.commandPicker)
    }
    noteSearch.present()
  }

  func dismissSearch() {
    releaseSearch(restoresEditorFocus: true)
  }

  func openFindReplace() {
    guard state == .running else { return }
    releaseSearch(restoresEditorFocus: false)
    releaseSlashCommand(restoresEditorFocus: false)
    if findReplaceSuspension == nil {
      findReplaceSuspension = windowCoordinator.beginOwnedPanel(.commandPicker)
    }
    findReplace.present()
  }

  func dismissFindReplace() {
    releaseFindReplace(restoresEditorFocus: true)
  }

  func activateSelectedSearchResult() async {
    do {
      if try await noteSearch.activateSelected() {
        releaseSearch(restoresEditorFocus: true)
      }
    } catch {
      NSSound.beep()
    }
  }

  func updateWindowConfiguration(_ configuration: WindowConfiguration) async throws {
    try await windowSettings.save(configuration)
    windowConfiguration = configuration
    windowCoordinator.applyConfiguration(configuration)
  }

  func updatePasteSettings(_ settings: PasteSettings) async throws {
    let previousSettings = pasteSettings
    pasteSettings = settings
    do {
      try await pasteSettingsStore.save(settings)
    } catch {
      if pasteSettings == settings {
        pasteSettings = previousSettings
      }
      throw error
    }
  }

  func updateEditorSettings(_ settings: EditorSettings) async throws {
    let previousSettings = editorSettings
    editorSettings = settings
    do {
      try await editorSettingsStore.save(settings)
    } catch {
      if editorSettings == settings {
        editorSettings = previousSettings
      }
      throw error
    }
  }

  func updateAppearanceSettings(_ settings: AppearanceSettings) async throws {
    let previousSettings = appearanceSettings
    var settings = settings
    settings.normalize()
    appearanceSettings = settings
    do {
      try await appearanceSettingsStore.save(settings)
    } catch {
      if appearanceSettings == settings {
        appearanceSettings = previousSettings
      }
      throw error
    }
  }

  func stepTextSize(by delta: Int) async throws {
    var settings = appearanceSettings
    settings.stepTextSize(by: delta)
    try await updateAppearanceSettings(settings)
  }

  func updateQuickActionSettings(_ settings: QuickActionSettings) async throws {
    try QuickActionSettingsValidator().validate(
      settings,
      globalInvocation: currentGlobalShortcut
    )
    let previousSettings = quickActionSettings
    quickActionSettings = settings
    do {
      try await quickActionSettingsStore.save(settings)
    } catch {
      if quickActionSettings == settings {
        quickActionSettings = previousSettings
      }
      throw error
    }
  }

  func updateExportSettings(_ settings: ExportSettings) async throws {
    var settings = settings
    settings.normalize()
    guard settings.version == ExportSettings.currentVersion else {
      throw ExportError.invalidTemplate("Only export settings version 1 is supported.")
    }
    if settings.quickDestination == .customURL {
      _ = try ValidatedCustomURLTemplate(source: settings.customURLTemplate)
    }
    let previousSettings = exportSettings
    exportSettings = settings
    do {
      try await exportSettingsStore.save(settings)
      await refreshExportDestinationDiagnostic()
    } catch {
      if exportSettings == settings {
        exportSettings = previousSettings
      }
      throw error
    }
  }

  @discardableResult
  func performQuickExport() async throws -> ExportReceipt? {
    guard !isExporting else { return nil }
    isExporting = true
    exportErrorMessage = nil
    defer { isExporting = false }
    do {
      let document = try await currentExportDocument()
      let receipt: ExportReceipt?
      switch exportSettings.quickDestination {
      case .plainText, .markdown:
        let format: ExportFileFormat =
          exportSettings.quickDestination == .plainText ? .plainText : .markdown
        guard
          let selection = await exportFileChooser.chooseFile(
            suggestedFilenameBase: ExportFilenameSanitizer().filenameBase(for: document),
            format: format
          )
        else { return nil }
        receipt = try await FileExportDestination(
          destinationURL: selection.url,
          format: format,
          overwritePolicy: selection.overwritePolicy
        ).export(document)
      case .obsidian:
        receipt = try await ObsidianExportDestination(
          vault: exportSettings.obsidianVault,
          opener: externalURLOpener
        ).export(document)
      case .bear:
        receipt = try await BearExportDestination(opener: externalURLOpener).export(document)
      case .appleNotes:
        receipt = try await AppleShortcutExportDestination(
          shortcutName: exportSettings.appleShortcutName,
          opener: externalURLOpener
        ).export(document)
      case .customURL:
        receipt = try await CustomURLExportDestination(
          template: ValidatedCustomURLTemplate(source: exportSettings.customURLTemplate),
          opener: externalURLOpener
        ).export(document)
      }
      lastExportReceipt = receipt
      return receipt
    } catch {
      exportErrorMessage = error.localizedDescription
      throw error
    }
  }

  @discardableResult
  func performExportAll() async throws -> ExportReceipt? {
    guard !isExporting else { return nil }
    isExporting = true
    exportErrorMessage = nil
    defer { isExporting = false }
    do {
      try await windowCoordinator.flushPendingSourceForCommand()
      _ = try await repository.flush()
      let exportedAt = clock.now()
      let documents = try await repository.allNotes().map { note in
        ExportDocumentBuilder().document(
          from: note,
          settings: exportSettings,
          modeSettings: modeSettings,
          exportedAt: exportedAt
        )
      }
      guard !documents.isEmpty else { throw ExportError.emptyDocument }
      guard
        let selection = await exportFileChooser.chooseArchive(
          suggestedFilenameBase: "ForNow Export"
        )
      else { return nil }
      let receipt = try await ZIPExportDestination(
        destinationURL: selection.url,
        overwritePolicy: selection.overwritePolicy
      ).export(documents)
      lastExportReceipt = receipt
      return receipt
    } catch {
      exportErrorMessage = error.localizedDescription
      throw error
    }
  }

  func dismissExportError() {
    exportErrorMessage = nil
  }

  func refreshExportDestinationDiagnostic() async {
    let settings = exportSettings
    switch settings.quickDestination {
    case .plainText, .markdown:
      exportDestinationDiagnostic = ExportDestinationDiagnostic(
        status: .available,
        message: "A save location will be requested."
      )
    case .customURL:
      do {
        let template = try ValidatedCustomURLTemplate(source: settings.customURLTemplate)
        let sample = diagnosticExportDocument()
        let url = try template.render(document: sample)
        exportDestinationDiagnostic = await availabilityDiagnostic(
          for: url,
          availableMessage: "The custom destination is available.",
          unavailableMessage: "No application handles this custom URL scheme."
        )
      } catch {
        exportDestinationDiagnostic = ExportDestinationDiagnostic(
          status: .requiresConfiguration,
          message: error.localizedDescription
        )
      }
    case .obsidian:
      let url = try? ApplicationExportURLBuilder.obsidian(
        document: diagnosticExportDocument(),
        vault: settings.obsidianVault
      )
      exportDestinationDiagnostic = await availabilityDiagnostic(
        for: url,
        availableMessage: "Obsidian is available.",
        unavailableMessage: "Install Obsidian or choose another destination."
      )
    case .bear:
      let url = try? ApplicationExportURLBuilder.bear(document: diagnosticExportDocument())
      exportDestinationDiagnostic = await availabilityDiagnostic(
        for: url,
        availableMessage: "Bear is available.",
        unavailableMessage: "Install Bear or choose another destination."
      )
    case .appleNotes:
      let url = try? ApplicationExportURLBuilder.appleShortcut(
        document: diagnosticExportDocument(),
        shortcutName: settings.appleShortcutName
      )
      exportDestinationDiagnostic = await availabilityDiagnostic(
        for: url,
        availableMessage: "Apple Shortcuts is available; verify the configured shortcut exists.",
        unavailableMessage: "Apple Shortcuts is unavailable."
      )
    }
  }

  private func currentExportDocument() async throws -> ExportDocument {
    try await windowCoordinator.flushPendingSourceForCommand()
    _ = try await repository.flush()
    guard let noteID = noteSession.currentNoteID,
      let note = try await repository.note(id: noteID)
    else {
      throw ExportError.emptyDocument
    }
    return ExportDocumentBuilder().document(
      from: note,
      settings: exportSettings,
      modeSettings: modeSettings,
      exportedAt: clock.now()
    )
  }

  private func diagnosticExportDocument() -> ExportDocument {
    ExportDocument(
      id: Self.previewUUID,
      sourceRevision: 0,
      title: "ForNow",
      content: "Export diagnostic",
      text: "ForNow\nExport diagnostic",
      createdAt: clock.now(),
      modifiedAt: clock.now(),
      exportedAt: clock.now()
    )
  }

  private func availabilityDiagnostic(
    for url: URL?,
    availableMessage: String,
    unavailableMessage: String
  ) async -> ExportDestinationDiagnostic {
    guard let url else {
      return ExportDestinationDiagnostic(
        status: .requiresConfiguration,
        message: "The destination URL could not be constructed."
      )
    }
    guard await externalURLOpener.isAvailable(for: url) else {
      return ExportDestinationDiagnostic(status: .unavailable, message: unavailableMessage)
    }
    return ExportDestinationDiagnostic(status: .available, message: availableMessage)
  }

  private func scheduleExpirationProcessing() {
    expirationScheduleTask?.cancel()
    expirationScheduleTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(60))
        } catch {
          return
        }
        guard let self else { return }
        do {
          _ = try await self.processExpiredNotes()
        } catch {
          NSSound.beep()
        }
      }
    }
  }

  private func reconcileDeletedNoteIDs(_ noteIDs: [UUID]) async throws {
    guard !noteIDs.isEmpty else { return }
    var firstError: (any Error)?
    for noteID in noteIDs {
      autoPasteModel.stopIfDestination(noteID, reason: .destinationDeleted)
      do {
        try await timerModel.removeTimer(linkedTo: noteID)
      } catch {
        if firstError == nil {
          firstError = error
        }
      }
    }
    do {
      try await noteSession.reconcileDeletedNotes(noteIDs)
    } catch {
      if firstError == nil {
        firstError = error
      }
    }
    if let firstError {
      throw firstError
    }
  }

  func updateModeSettings(_ settings: ModeSettings) async throws {
    releaseSlashCommand(restoresEditorFocus: false)
    let registry = try ModeAliasRegistry(settings: settings)
    let previousSettings = modeSettings
    try await noteSession.updateMeaningfulContentPolicy(
      MeaningfulContentPolicy(
        modeAliases: registry.keywordInterpretationEnabled ? registry.allAliases : []
      )
    )
    do {
      try await modeSettingsStore.save(settings)
      modeSettings = settings
    } catch {
      if let previousRegistry = try? ModeAliasRegistry(settings: previousSettings) {
        try? await noteSession.updateMeaningfulContentPolicy(
          MeaningfulContentPolicy(
            modeAliases: previousRegistry.keywordInterpretationEnabled
              ? previousRegistry.allAliases : []
          )
        )
      }
      throw error
    }
  }

  func updateMathSettings(_ settings: MathSettings) async throws {
    let previousSettings = mathSettings
    let settings = try settings.validated()
    mathSettings = settings
    do {
      try await mathSettingsStore.save(settings)
      if settings.primaryCurrency != previousSettings.primaryCurrency {
        rateSnapshot = await currencyRateCoordinator.cachedSnapshot(
          base: settings.primaryCurrency
        )
        currencyRateRefreshState = rateSnapshot == nil ? .idle : .current
      }
      if settings.automaticCurrencyRefreshEnabled,
        !previousSettings.automaticCurrencyRefreshEnabled
          || settings.primaryCurrency != previousSettings.primaryCurrency
      {
        await refreshCurrencyRates(automatic: true)
      }
    } catch {
      if mathSettings == settings {
        mathSettings = previousSettings
      }
      throw error
    }
  }

  func updateTimerSettings(_ settings: TimerSettings) async throws {
    try await timerModel.updateSettings(settings)
  }

  func updateAutoPasteSettings(_ settings: AutoPasteSettings) async throws {
    try await autoPasteModel.updateSettings(settings)
  }

  func updateOCRSettings(_ settings: OCRSettings) async throws {
    try await ocrModel.updateSettings(settings)
  }

  var currencyConversionContext: CurrencyConversionContext {
    CurrencyConversionContext(
      rateSnapshot: rateSnapshot,
      evaluationDate: clock.now()
    )
  }

  func refreshCurrencyRatesManually() async {
    await refreshCurrencyRates(automatic: false)
  }

  func waitForPendingCurrencyRefresh() async {
    await automaticCurrencyRefreshTask?.value
  }

  private func scheduleAutomaticCurrencyRefreshIfNeeded() {
    guard mathSettings.automaticCurrencyRefreshEnabled else { return }
    automaticCurrencyRefreshTask?.cancel()
    automaticCurrencyRefreshTask = Task { [weak self] in
      await self?.refreshCurrencyRates(automatic: true)
    }
  }

  private func refreshCurrencyRates(automatic: Bool) async {
    let previousState = currencyRateRefreshState
    currencyRateRefreshState = .refreshing
    do {
      switch try await currencyRateCoordinator.refresh(
        base: mathSettings.primaryCurrency,
        automatic: automatic
      ) {
      case .skipped(let cached):
        rateSnapshot = cached ?? rateSnapshot
        currencyRateRefreshState = rateSnapshot == nil ? previousState : .current
      case .updated(let snapshot):
        rateSnapshot = snapshot
        currencyRateRefreshState = .current
      case .failed(let cached):
        rateSnapshot = cached ?? rateSnapshot
        currencyRateRefreshState = .failed
      }
    } catch is CancellationError {
      currencyRateRefreshState = previousState
    } catch {
      currencyRateRefreshState = .failed
    }
  }

  func expandedLinkIdentities(for noteID: UUID?) -> Set<LinkIdentity> {
    guard let noteID else { return [] }
    return expandedLinkState[noteID] ?? []
  }

  func toggleExpandedLink(_ identity: LinkIdentity, noteID: UUID) async throws {
    let previousState = expandedLinkState
    var updatedState = expandedLinkState
    var identities = updatedState[noteID] ?? []
    if identities.contains(identity) {
      identities.remove(identity)
    } else {
      identities.insert(identity)
    }
    if identities.isEmpty {
      updatedState.removeValue(forKey: noteID)
    } else {
      updatedState[noteID] = identities
    }
    expandedLinkState = updatedState

    do {
      try await expandedLinkStateStore.save(updatedState)
    } catch {
      if expandedLinkState == updatedState {
        expandedLinkState = previousState
      }
      throw error
    }
  }

  func applyGlobalShortcut(
    _ candidate: GlobalShortcutCandidate
  ) -> ShortcutRegistrationResult {
    guard
      (try? QuickActionSettingsValidator().validate(
        quickActionSettings,
        globalInvocation: candidate
      )) != nil
    else {
      shortcutRegistrationResult = .conflict
      return .conflict
    }
    let result = windowCoordinator.applyShortcut(candidate)
    currentGlobalShortcut = windowCoordinator.currentShortcut
    shortcutRegistrationResult = result
    return result
  }

  func showWindow() {
    windowCoordinator.showWindow(source: .localCommand)
  }

  func toggleWindow() {
    if noteSearch.isPresented {
      releaseSearch(restoresEditorFocus: false)
    }
    if findReplace.isPresented {
      releaseFindReplace(restoresEditorFocus: false)
    }
    if slashCommand.isPresented {
      releaseSlashCommand(restoresEditorFocus: false)
    }
    windowCoordinator.toggleWindow(source: .localCommand)
  }

  func closeWindow() {
    if noteSearch.isPresented {
      releaseSearch(restoresEditorFocus: false)
    }
    if findReplace.isPresented {
      releaseFindReplace(restoresEditorFocus: false)
    }
    if slashCommand.isPresented {
      releaseSlashCommand(restoresEditorFocus: false)
    }
    if let keyWindow = NSApp.keyWindow, keyWindow.title != appName {
      keyWindow.performClose(nil)
      return
    }
    windowCoordinator.closeWindow()
  }

  func togglePin() async throws {
    var updated = windowConfiguration
    updated.isPinned.toggle()
    try await updateWindowConfiguration(updated)
  }

  func applicationDidBecomeActive() {
    windowCoordinator.applicationDidBecomeActive()
  }

  func applicationDidResignActive() {
    releaseSlashCommand(restoresEditorFocus: false)
    windowCoordinator.applicationDidResignActive()
  }

  func settingsDidAppear() {
    releaseSlashCommand(restoresEditorFocus: false)
    guard settingsSuspension == nil else { return }
    settingsSuspension = windowCoordinator.beginOwnedPanel(.settings)
  }

  func settingsDidDisappear() {
    guard let settingsSuspension else { return }
    self.settingsSuspension = nil
    windowCoordinator.endOwnedPanel(settingsSuspension)
  }

  func waitForWindowTransitions() async {
    await windowCoordinator.waitForPendingTransitions()
  }

  private func flushWindowSource(_ source: String?, hasMarkedText: Bool) async throws {
    if let source {
      try await noteSession.applyEditorText(source, hasMarkedText: hasMarkedText)
    }
    try await noteSession.prepareForDeparture()
    _ = try await repository.flush()
  }

  private func meaningfulContentPolicy(for settings: ModeSettings) -> MeaningfulContentPolicy {
    guard let registry = try? ModeAliasRegistry(settings: settings) else {
      return MeaningfulContentPolicy()
    }
    return MeaningfulContentPolicy(
      modeAliases: registry.keywordInterpretationEnabled ? registry.allAliases : []
    )
  }

  private func repairQuickActionSettingsIfNeeded() async {
    let validator = QuickActionSettingsValidator()
    guard
      (try? validator.validate(
        quickActionSettings,
        globalInvocation: currentGlobalShortcut
      )) == nil
    else { return }

    let repaired = validator.safeDefaults(avoiding: currentGlobalShortcut)
    quickActionSettings = repaired
    try? await quickActionSettingsStore.save(repaired)
  }

  private func releaseSearch(restoresEditorFocus: Bool) {
    guard noteSearch.isPresented || searchSuspension != nil else { return }
    noteSearch.dismiss()
    if let searchSuspension {
      self.searchSuspension = nil
      windowCoordinator.endOwnedPanel(searchSuspension)
    }
    if restoresEditorFocus {
      windowCoordinator.showWindow(source: .localCommand)
    }
  }

  private func releaseFindReplace(restoresEditorFocus: Bool) {
    guard findReplace.isPresented || findReplaceSuspension != nil else { return }
    findReplace.dismiss()
    if let findReplaceSuspension {
      self.findReplaceSuspension = nil
      windowCoordinator.endOwnedPanel(findReplaceSuspension)
    }
    if restoresEditorFocus {
      windowCoordinator.showWindow(source: .localCommand)
    }
  }

  private func slashCommandPresentationDidChange(_ isPresented: Bool) {
    if isPresented {
      guard slashCommandSuspension == nil else { return }
      slashCommandSuspension = windowCoordinator.beginOwnedPanel(.commandPicker)
    } else if let slashCommandSuspension {
      self.slashCommandSuspension = nil
      windowCoordinator.endOwnedPanel(slashCommandSuspension)
    }
  }

  private func releaseSlashCommand(restoresEditorFocus: Bool) {
    guard slashCommand.isPresented || slashCommandSuspension != nil else { return }
    slashCommand.dismiss(restoresEditorFocus: restoresEditorFocus)
    if let slashCommandSuspension {
      self.slashCommandSuspension = nil
      windowCoordinator.endOwnedPanel(slashCommandSuspension)
    }
  }

  private static let previewUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

struct ProductionPaths: Equatable, Sendable {
  let databaseURL: URL
  let backupDirectoryURL: URL

  static func standard(fileManager: FileManager) -> ProductionPaths {
    let applicationSupport =
      fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    let root = applicationSupport.appendingPathComponent("ForNow", isDirectory: true)
    return ProductionPaths(
      databaseURL: root.appendingPathComponent("ForNow.sqlite"),
      backupDirectoryURL: root.appendingPathComponent("Backups", isDirectory: true)
    )
  }
}
