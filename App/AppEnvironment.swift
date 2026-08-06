import AppKit
import Combine
import ForNowCore
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
  let uuidGenerator: any UUIDGenerating
  let parser: any SourceParsing
  let windowCoordinator: any WindowCoordinating
  let clipboard: any ClipboardService
  let ocr: any OCRService
  let notifications: any NotificationService
  let rateProvider: any CurrencyRateProvider
  let lifecycleSettings: any LifecycleSettingsStoring
  let windowSettings: any WindowSettingsStoring
  let pasteSettings: any PasteSettingsStoring
  let editorSettings: any EditorSettingsStoring
  let modeSettings: any ModeSettingsStoring
  let mathSettings: any MathSettingsStoring
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
  let uuidGenerator: any UUIDGenerating
  let parser: any SourceParsing
  let windowCoordinator: any WindowCoordinating
  let clipboard: any ClipboardService
  let ocr: any OCRService
  let notifications: any NotificationService
  let rateProvider: any CurrencyRateProvider
  let lifecycleSettings: any LifecycleSettingsStoring
  let windowSettings: any WindowSettingsStoring
  let pasteSettingsStore: any PasteSettingsStoring
  let editorSettingsStore: any EditorSettingsStoring
  let modeSettingsStore: any ModeSettingsStoring
  let mathSettingsStore: any MathSettingsStoring
  let expandedLinkStateStore: any ExpandedLinkStateStoring
  let logger: any AppLifecycleLogging
  let noteSession: NoteSessionModel
  let noteSearch: NoteSearchModel
  let findReplace: FindReplaceModel
  let slashCommand: SlashCommandModel
  let deleteConfirmationCoordinator: DeleteConfirmationCoordinator

  @Published private(set) var windowConfiguration = WindowConfiguration()
  @Published private(set) var pasteSettings = PasteSettings()
  @Published private(set) var editorSettings = EditorSettings()
  @Published private(set) var modeSettings = ModeSettings()
  @Published private(set) var mathSettings = MathSettings()
  @Published private(set) var expandedLinkState: [UUID: Set<LinkIdentity>] = [:]
  @Published private(set) var currentGlobalShortcut = GlobalShortcutCandidate.optionA
  @Published private(set) var shortcutRegistrationResult: ShortcutRegistrationResult = .accepted

  private(set) var state: AppEnvironmentState = .idle
  private var repositoryIsPrepared = false
  private var clipboardIsStarted = false
  private var notificationsAreStarted = false
  private var windowCoordinatorIsStarted = false
  private var settingsSuspension: AutoHideSuspension?
  private var searchSuspension: AutoHideSuspension?
  private var findReplaceSuspension: AutoHideSuspension?
  private var slashCommandSuspension: AutoHideSuspension?

  init(variant: AppEnvironmentVariant, dependencies: AppDependencies) {
    self.variant = variant
    repository = dependencies.repository
    clock = dependencies.clock
    uuidGenerator = dependencies.uuidGenerator
    parser = dependencies.parser
    windowCoordinator = dependencies.windowCoordinator
    clipboard = dependencies.clipboard
    ocr = dependencies.ocr
    notifications = dependencies.notifications
    rateProvider = dependencies.rateProvider
    lifecycleSettings = dependencies.lifecycleSettings
    windowSettings = dependencies.windowSettings
    pasteSettingsStore = dependencies.pasteSettings
    editorSettingsStore = dependencies.editorSettings
    modeSettingsStore = dependencies.modeSettings
    mathSettingsStore = dependencies.mathSettings
    expandedLinkStateStore = dependencies.expandedLinkState
    logger = dependencies.logger
    let noteSession = NoteSessionModel(
      repository: dependencies.repository,
      clock: dependencies.clock,
      uuidGenerator: dependencies.uuidGenerator,
      settingsStore: dependencies.lifecycleSettings
    )
    self.noteSession = noteSession
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
    return AppEnvironment(
      variant: .production,
      dependencies: AppDependencies(
        repository: PersistenceNoteRepository(
          databaseURL: paths.databaseURL,
          backupDirectoryURL: paths.backupDirectoryURL
        ),
        clock: SystemWallClock(),
        uuidGenerator: SystemUUIDGenerator(),
        parser: PlainSourceParser(),
        windowCoordinator: SwiftUIWindowCoordinator(),
        clipboard: DisabledClipboardService(),
        ocr: VisionOCRService(),
        notifications: UserNotificationService(),
        rateProvider: DisabledCurrencyRateProvider(),
        lifecycleSettings: UserDefaultsLifecycleSettingsStore(),
        windowSettings: UserDefaultsWindowSettingsStore(),
        pasteSettings: UserDefaultsPasteSettingsStore(),
        editorSettings: UserDefaultsEditorSettingsStore(),
        modeSettings: UserDefaultsModeSettingsStore(),
        mathSettings: UserDefaultsMathSettingsStore(),
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
        uuidGenerator: SequenceUUIDGenerator(values: [Self.previewUUID]),
        parser: PlainSourceParser(),
        windowCoordinator: DisabledWindowCoordinator(),
        clipboard: DisabledClipboardService(),
        ocr: UnavailableOCRService(),
        notifications: DisabledNotificationService(),
        rateProvider: DisabledCurrencyRateProvider(),
        lifecycleSettings: InMemoryLifecycleSettingsStore(),
        windowSettings: InMemoryWindowSettingsStore(),
        pasteSettings: InMemoryPasteSettingsStore(),
        editorSettings: InMemoryEditorSettingsStore(),
        modeSettings: InMemoryModeSettingsStore(),
        mathSettings: InMemoryMathSettingsStore(),
        expandedLinkState: InMemoryExpandedLinkStateStore(),
        logger: InMemoryLifecycleLogger()
      )
    )
  }

  static func test(
    repository: any NoteRepository = InMemoryNoteRepository(),
    clock: any WallClock = FixedWallClock(Date(timeIntervalSince1970: 0)),
    uuidGenerator: any UUIDGenerating = SequenceUUIDGenerator(values: [previewUUID]),
    parser: any SourceParsing = PlainSourceParser(),
    windowCoordinator: any WindowCoordinating = DisabledWindowCoordinator(),
    clipboard: any ClipboardService = DisabledClipboardService(),
    ocr: any OCRService = UnavailableOCRService(),
    notifications: any NotificationService = DisabledNotificationService(),
    rateProvider: any CurrencyRateProvider = DisabledCurrencyRateProvider(),
    lifecycleSettings: any LifecycleSettingsStoring = InMemoryLifecycleSettingsStore(),
    windowSettings: any WindowSettingsStoring = InMemoryWindowSettingsStore(),
    pasteSettings: any PasteSettingsStoring = InMemoryPasteSettingsStore(),
    editorSettings: any EditorSettingsStoring = InMemoryEditorSettingsStore(),
    modeSettings: any ModeSettingsStoring = InMemoryModeSettingsStore(),
    mathSettings: any MathSettingsStoring = InMemoryMathSettingsStore(),
    expandedLinkState: any ExpandedLinkStateStoring = InMemoryExpandedLinkStateStore(),
    logger: any AppLifecycleLogging = InMemoryLifecycleLogger()
  ) -> AppEnvironment {
    AppEnvironment(
      variant: .test,
      dependencies: AppDependencies(
        repository: repository,
        clock: clock,
        uuidGenerator: uuidGenerator,
        parser: parser,
        windowCoordinator: windowCoordinator,
        clipboard: clipboard,
        ocr: ocr,
        notifications: notifications,
        rateProvider: rateProvider,
        lifecycleSettings: lifecycleSettings,
        windowSettings: windowSettings,
        pasteSettings: pasteSettings,
        editorSettings: editorSettings,
        modeSettings: modeSettings,
        mathSettings: mathSettings,
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
      windowConfiguration = await windowSettings.load()
      pasteSettings = await pasteSettingsStore.load()
      editorSettings = await editorSettingsStore.load()
      modeSettings = await modeSettingsStore.load()
      mathSettings = await mathSettingsStore.load()
      try await noteSession.updateMeaningfulContentPolicy(
        meaningfulContentPolicy(for: modeSettings)
      )
      try await noteSession.start()
      await logger.record(.noteSessionLoaded)
      expandedLinkState = await expandedLinkStateStore.load()
      windowCoordinator.applyConfiguration(windowConfiguration)
      clipboard.start()
      clipboardIsStarted = true
      await logger.record(.serviceStarted(.clipboard))
      await notifications.start()
      notificationsAreStarted = true
      await logger.record(.serviceStarted(.notifications))
      windowCoordinator.start()
      windowCoordinatorIsStarted = true
      currentGlobalShortcut = windowCoordinator.currentShortcut
      shortcutRegistrationResult = windowCoordinator.lastShortcutRegistration
      await logger.record(.serviceStarted(.windowCoordinator))
      state = .running
      await logger.record(.startupCompleted)
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

    var firstError: (any Error)?
    releaseSearch(restoresEditorFocus: false)
    releaseFindReplace(restoresEditorFocus: false)
    releaseSlashCommand(restoresEditorFocus: false)
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
    if clipboardIsStarted {
      clipboard.stop()
      clipboardIsStarted = false
      await logger.record(.serviceStopped(.clipboard))
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
    let outcome = try await noteSession.requestDeletion()
    guard outcome == .confirmationRequired else { return }
    let suspension = windowCoordinator.beginOwnedPanel(.confirmation)
    defer { windowCoordinator.endOwnedPanel(suspension) }
    let result = await deleteConfirmationCoordinator.requestConfirmation()
    try await noteSession.resolveDeletion(
      confirm: result.confirmsDeletion,
      suppressFutureWarning: result.suppressesFutureWarning
    )
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
    mathSettings = settings
    do {
      try await mathSettingsStore.save(settings)
    } catch {
      if mathSettings == settings {
        mathSettings = previousSettings
      }
      throw error
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
