import AppKit
import ForNowCore
import ForNowEditor
import ForNowIntegrations
import ForNowModes
import ForNowPersistence
import ForNowWindowing
import XCTest

@testable import ForNow

final class AppEnvironmentTests: XCTestCase {
  @MainActor
  func testApplicationEnvironmentUsesForNowName() {
    XCTAssertEqual(AppEnvironment.test().appName, "ForNow")
  }

  @MainActor
  func testTestEnvironmentInjectsEveryRequiredService() async throws {
    let environment = AppEnvironment.test()
    let generatedUUID = await environment.uuidGenerator.next()
    let parsedSource = await environment.parser.parse(source: "hello 你好", version: 4)
    let notificationState = await environment.notifications.authorizationState()
    let cachedRates = await environment.rateCache.snapshot(
      base: CurrencyCode(rawValue: "USD")
    )

    XCTAssertEqual(environment.variant, .test)
    XCTAssertEqual(environment.clock.now(), Date(timeIntervalSince1970: 0))
    XCTAssertEqual(
      generatedUUID,
      UUID(uuidString: "00000000-0000-0000-0000-000000000001")
    )
    XCTAssertEqual(
      parsedSource,
      ParsedSource(version: 4, utf16Length: 8, mode: .plain)
    )
    XCTAssertNil(environment.clipboard.currentText())
    XCTAssertNil(cachedRates)
    XCTAssertEqual(notificationState, .denied)

    do {
      _ = try await environment.ocr.recognizeText(in: Data())
      XCTFail("The test OCR service must remain unavailable")
    } catch {
      XCTAssertEqual(error as? UnavailableOCRError, .unavailable)
    }

    do {
      _ = try await environment.rateProvider.rates(base: CurrencyCode(rawValue: "USD"))
      XCTFail("The test rate provider must not access a network")
    } catch {
      XCTAssertEqual(error as? CurrencyRateProviderError, .disabled)
    }
  }

  @MainActor
  func testPreviewLaunchUsesOnlyOfflineDependencies() async throws {
    let environment = AppEnvironment.preview()

    XCTAssertEqual(environment.variant, .preview)
    XCTAssertTrue(environment.repository is InMemoryNoteRepository)
    XCTAssertTrue(environment.ocr is UnavailableOCRService)
    XCTAssertTrue(environment.rateProvider is DisabledCurrencyRateProvider)
    XCTAssertTrue(environment.rateCache is InMemoryCurrencyRateCache)

    try await environment.start()
    XCTAssertEqual(environment.state, .running)
    try await environment.shutdown()
    XCTAssertEqual(environment.state, .stopped)
  }

  @MainActor
  func testLaunchSmokeAndIdempotentStartup() async throws {
    let logger = InMemoryLifecycleLogger()
    let environment = AppEnvironment.test(logger: logger)

    try await environment.start()
    try await environment.start()
    let events = await logger.events()

    XCTAssertEqual(environment.state, .running)
    XCTAssertEqual(
      events,
      [
        .startupBegan,
        .serviceStarted(.repository),
        .noteSessionLoaded,
        .serviceStarted(.clipboard),
        .serviceStarted(.notifications),
        .serviceStarted(.windowCoordinator),
        .startupCompleted,
      ]
    )
  }

  @MainActor
  func testShutdownFlushesRepositoryBeforeAnyServiceTeardown() async throws {
    let logger = InMemoryLifecycleLogger()
    let repository = InMemoryNoteRepository()
    let environment = AppEnvironment.test(repository: repository, logger: logger)
    let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    try await environment.start()
    try await repository.schedule(
      NoteDraft(
        id: noteID,
        body: "source remains private",
        modifiedAt: Date(timeIntervalSince1970: 10)
      )
    )
    try await environment.shutdown()
    try await environment.shutdown()

    XCTAssertEqual(environment.state, .stopped)
    let events = await logger.events()
    XCTAssertEqual(
      events,
      [
        .startupBegan,
        .serviceStarted(.repository),
        .noteSessionLoaded,
        .serviceStarted(.clipboard),
        .serviceStarted(.notifications),
        .serviceStarted(.windowCoordinator),
        .startupCompleted,
        .shutdownBegan,
        .noteSessionPrepared,
        .repositoryFlushed,
        .serviceStopped(.windowCoordinator),
        .serviceStopped(.notifications),
        .serviceStopped(.clipboard),
        .serviceStopped(.repository),
        .shutdownCompleted,
      ]
    )

    let flushIndex = try XCTUnwrap(events.firstIndex(of: .repositoryFlushed))
    for service in [
      AppLifecycleService.windowCoordinator,
      .notifications,
      .clipboard,
      .repository,
    ] {
      let stopIndex = try XCTUnwrap(events.firstIndex(of: .serviceStopped(service)))
      XCTAssertLessThan(flushIndex, stopIndex)
    }
  }

  @MainActor
  func testProductionCompositionDefersDatabaseOpeningUntilStartup() {
    let environment = AppEnvironment.production()

    XCTAssertEqual(environment.variant, .production)
    XCTAssertEqual(environment.state, .idle)
    XCTAssertTrue(environment.repository is PersistenceNoteRepository)
    XCTAssertTrue(environment.clipboard is DisabledClipboardService)
    XCTAssertTrue(environment.ocr is VisionOCRService)
    XCTAssertTrue(environment.rateProvider is CachedCurrencyRateProvider)
    XCTAssertTrue(environment.rateCache is UserDefaultsCurrencyRateCache)
  }

  @MainActor
  func test_UT_WIN_002_WindowSettingsRoundTripAndEnvironmentLoadsThem() async throws {
    let suiteName = "ForNowWindowSettingsTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let configuration = WindowConfiguration(
      mode: .dropdownPanel,
      presence: .neither,
      isPinned: true,
      autoHideEnabled: true,
      dropdownDimensions: DropdownDimensions(width: 740, height: 680)
    )
    let firstStore = UserDefaultsWindowSettingsStore(suiteName: suiteName)
    try await firstStore.save(configuration)
    let secondStore = UserDefaultsWindowSettingsStore(suiteName: suiteName)
    let loadedConfiguration = await secondStore.load()
    XCTAssertEqual(loadedConfiguration, configuration)

    let coordinator = DisabledWindowCoordinator()
    let environment = AppEnvironment.test(
      windowCoordinator: coordinator,
      windowSettings: secondStore
    )
    try await environment.start()

    XCTAssertEqual(environment.windowConfiguration, configuration)
    XCTAssertEqual(coordinator.configuration, configuration)
    try await environment.shutdown()
  }

  @MainActor
  func test_UT_CLIP_SETTINGS_PasteSettingsRoundTripAndEnvironmentLoadsThem() async throws {
    let suiteName = "ForNowPasteSettingsTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let settings = PasteSettings(
      stripsLeadingWhitespace: false,
      stripsListNumbers: true,
      stripsBullets: false,
      stripsMarkdown: true,
      stripsEmptyLines: false
    )
    let firstStore = UserDefaultsPasteSettingsStore(suiteName: suiteName)
    try await firstStore.save(settings)
    let secondStore = UserDefaultsPasteSettingsStore(suiteName: suiteName)
    let loadedSettings = await secondStore.load()
    XCTAssertEqual(loadedSettings, settings)

    let environment = AppEnvironment.test(pasteSettings: secondStore)
    try await environment.start()
    XCTAssertEqual(environment.pasteSettings, settings)

    var updated = settings
    updated.stripsLeadingWhitespace = true
    try await environment.updatePasteSettings(updated)
    XCTAssertEqual(environment.pasteSettings, updated)
    let persistedSettings = await secondStore.load()
    XCTAssertEqual(persistedSettings, updated)
    try await environment.shutdown()
  }

  func testPasteSettingsStoreFallsBackForUnreadablePayload() async {
    let suiteName = "ForNowPasteSettingsFallbackTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(Data("not-json".utf8), forKey: "app.fornow.paste.settings.v1")

    let loaded = await UserDefaultsPasteSettingsStore(suiteName: suiteName).load()

    XCTAssertEqual(loaded, PasteSettings())
  }

  @MainActor
  func test_ET_EDIT_004_EditorSettingsAndExpandedLinksPersistOutsideSource() async throws {
    let suiteName = "ForNowEditorStateTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let settingsStore = UserDefaultsEditorSettingsStore(suiteName: suiteName)
    let linkStateStore = UserDefaultsExpandedLinkStateStore(suiteName: suiteName)
    let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let originalURL = "https://private.example/A%2Fb?q=source-canary"
    let identity = LinkIdentity(originalURL: originalURL, occurrenceIndex: 2)
    let settings = EditorSettings(
      automaticallyShortensLinks: false,
      hyperlinkFeaturesEnabled: true,
      defaultCodeLanguage: .python,
      codeHighlightTheme: .midnight
    )
    try await settingsStore.save(settings)
    try await linkStateStore.save([noteID: [identity]])

    let firstEnvironment = AppEnvironment.test(
      editorSettings: settingsStore,
      expandedLinkState: linkStateStore
    )
    try await firstEnvironment.start()
    XCTAssertEqual(firstEnvironment.editorSettings, settings)
    XCTAssertEqual(firstEnvironment.expandedLinkIdentities(for: noteID), [identity])

    var updatedSettings = settings
    updatedSettings.hyperlinkFeaturesEnabled = false
    updatedSettings.codeHighlightTheme = .classic
    try await firstEnvironment.updateEditorSettings(updatedSettings)
    try await firstEnvironment.toggleExpandedLink(identity, noteID: noteID)
    XCTAssertTrue(firstEnvironment.expandedLinkIdentities(for: noteID).isEmpty)
    try await firstEnvironment.toggleExpandedLink(identity, noteID: noteID)
    try await firstEnvironment.shutdown()

    let secondEnvironment = AppEnvironment.test(
      editorSettings: UserDefaultsEditorSettingsStore(suiteName: suiteName),
      expandedLinkState: UserDefaultsExpandedLinkStateStore(suiteName: suiteName)
    )
    try await secondEnvironment.start()
    XCTAssertEqual(secondEnvironment.editorSettings, updatedSettings)
    XCTAssertEqual(secondEnvironment.expandedLinkIdentities(for: noteID), [identity])
    try await secondEnvironment.shutdown()

    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let persistedPayload = [
      defaults.data(forKey: "app.fornow.editor.settings.v1"),
      defaults.data(forKey: "app.fornow.editor.expanded-links.v1"),
    ].compactMap { $0 }.reduce(into: Data()) { $0.append($1) }
    XCTAssertFalse(String(decoding: persistedPayload, as: UTF8.self).contains(originalURL))
  }

  func testEditorSettingsVersionOneMigratesWithoutLosingLinkPreferences() async throws {
    let suiteName = "ForNowEditorSettingsMigrationTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let legacyPayload: [String: Any] = [
      "version": 1,
      "settings": [
        "automaticallyShortensLinks": false,
        "hyperlinkFeaturesEnabled": false,
      ],
    ]
    defaults.set(
      try JSONSerialization.data(withJSONObject: legacyPayload),
      forKey: "app.fornow.editor.settings.v1"
    )

    let store = UserDefaultsEditorSettingsStore(suiteName: suiteName)
    let migrated = await store.load()

    XCTAssertEqual(
      migrated,
      EditorSettings(
        automaticallyShortensLinks: false,
        hyperlinkFeaturesEnabled: false,
        defaultCodeLanguage: .plainText,
        codeHighlightTheme: .adaptive,
        omitsChecklistTriggersOnExport: true
      )
    )
    try await store.save(migrated)
    let saved = try XCTUnwrap(defaults.data(forKey: "app.fornow.editor.settings.v1"))
    XCTAssertTrue(String(decoding: saved, as: UTF8.self).contains("\"version\":3"))
  }

  @MainActor
  func testEditorSettingsSaveFailureRollsBackPublishedState() async throws {
    let original = EditorSettings(
      automaticallyShortensLinks: false,
      hyperlinkFeaturesEnabled: true,
      defaultCodeLanguage: .swift,
      codeHighlightTheme: .adaptive
    )
    let store = FailingEditorSettingsStore(settings: original)
    let environment = AppEnvironment.test(editorSettings: store)
    try await environment.start()
    var updated = original
    updated.defaultCodeLanguage = .typescript
    updated.codeHighlightTheme = .midnight

    do {
      try await environment.updateEditorSettings(updated)
      XCTFail("A settings write failure must be surfaced")
    } catch {
      XCTAssertEqual(error as? FailingEditorSettingsStore.Failure, .save)
    }

    XCTAssertEqual(environment.editorSettings, original)
    try await environment.shutdown()
  }

  func testEditorStateStoresFallBackForUnreadablePayloads() async {
    let suiteName = "ForNowEditorStateFallbackTests.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(Data("not-json".utf8), forKey: "app.fornow.editor.settings.v1")
    defaults.set(Data("not-json".utf8), forKey: "app.fornow.editor.expanded-links.v1")

    let settings = await UserDefaultsEditorSettingsStore(suiteName: suiteName).load()
    let linkState = await UserDefaultsExpandedLinkStateStore(suiteName: suiteName).load()

    XCTAssertEqual(settings, EditorSettings())
    XCTAssertTrue(linkState.isEmpty)
  }

  @MainActor
  func test_UIT_WIN_002_ModeChangesFlushAndPreserveExactSource() async {
    let shortcutName = "forNow.tests.modeChanges"
    defer {
      UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_\(shortcutName)")
    }
    let shortcut = ValidatedGlobalShortcut(
      nameIdentifier: shortcutName,
      preflight: AcceptingShortcutPreflight()
    )
    let coordinator = SwiftUIWindowCoordinator(shortcut: shortcut)
    var source = "mode fixture 中文 📝"
    var textViews: [NSTextView] = []
    var flushedSources: [String] = []
    coordinator.configure(
      WindowCoordinatorCallbacks(
        makeContentViewController: {
          let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
          textView.string = source
          textViews.append(textView)
          let controller = NSViewController()
          controller.view = textView
          return controller
        },
        flushPendingSource: { currentSource, _ in
          if let currentSource {
            source = currentSource
            flushedSources.append(currentSource)
          }
        },
        windowDidReopen: {},
        windowDidClose: {}
      )
    )
    var configuration = WindowConfiguration(presence: .dock)
    coordinator.applyConfiguration(configuration)
    coordinator.start()
    await coordinator.waitForPendingTransitions()

    configuration.mode = .menuBarPanel
    coordinator.applyConfiguration(configuration)
    await coordinator.waitForPendingTransitions()
    configuration.mode = .dropdownPanel
    coordinator.applyConfiguration(configuration)
    await coordinator.waitForPendingTransitions()

    XCTAssertEqual(flushedSources, [source, source])
    XCTAssertEqual(textViews.map(\.string), [source, source, source])
    XCTAssertEqual(coordinator.windowCreationCount, 3)
    XCTAssertTrue(coordinator.isWindowVisible)
    coordinator.stop()
  }

  @MainActor
  func test_IT_WIN_005_OneThousandToggleCyclesKeepOneWindowAndSelection() async {
    let shortcutName = "forNow.tests.toggleCycles"
    defer {
      UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_\(shortcutName)")
    }
    let shortcut = ValidatedGlobalShortcut(
      nameIdentifier: shortcutName,
      preflight: AcceptingShortcutPreflight()
    )
    let coordinator = SwiftUIWindowCoordinator(shortcut: shortcut)
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
    textView.string = "selection survives"
    textView.setSelectedRange(NSRange(location: 4, length: 3))
    var flushCount = 0
    coordinator.configure(
      WindowCoordinatorCallbacks(
        makeContentViewController: {
          let controller = NSViewController()
          controller.view = textView
          return controller
        },
        flushPendingSource: { currentSource, _ in
          XCTAssertEqual(currentSource, "selection survives")
          flushCount += 1
        },
        windowDidReopen: {},
        windowDidClose: {}
      )
    )
    coordinator.applyConfiguration(WindowConfiguration(presence: .dock))
    coordinator.start()
    await coordinator.waitForPendingTransitions()

    for _ in 0..<1_000 {
      coordinator.toggleWindow(source: .localCommand)
      coordinator.toggleWindow(source: .localCommand)
    }
    await coordinator.waitForPendingTransitions()

    XCTAssertEqual(flushCount, 1_000)
    XCTAssertEqual(coordinator.windowCreationCount, 1)
    XCTAssertTrue(coordinator.isWindowVisible)
    XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 3))
    coordinator.stop()
  }

  @MainActor
  func testFailedRepositoryPreparationDoesNotPreventShutdown() async throws {
    let logger = InMemoryLifecycleLogger()
    let environment = AppEnvironment.test(
      repository: FailingPrepareNoteRepository(),
      logger: logger
    )

    do {
      try await environment.start()
      XCTFail("Startup must surface repository preparation failure")
    } catch {
      XCTAssertEqual(error as? FailingPrepareNoteRepository.Failure, .prepare)
    }
    XCTAssertEqual(environment.state, .failed)

    try await environment.shutdown()

    XCTAssertEqual(environment.state, .stopped)
    let events = await logger.events()
    XCTAssertEqual(
      events,
      [
        .startupBegan,
        .startupFailed,
        .shutdownBegan,
        .repositoryFlushSkipped,
        .shutdownCompleted,
      ]
    )
  }
}

@MainActor
private struct AcceptingShortcutPreflight: GlobalShortcutPreflighting {
  func registrationStatus(for candidate: GlobalShortcutCandidate) -> Int32 {
    0
  }
}

private actor FailingPrepareNoteRepository: NoteRepository {
  enum Failure: Error, Equatable {
    case prepare
  }

  func prepare() throws {
    throw Failure.prepare
  }

  func schedule(_ draft: NoteDraft) throws {
    throw Failure.prepare
  }

  func discardPending(noteID: UUID) {}

  func flush() throws -> [Note] {
    throw Failure.prepare
  }

  func note(id: UUID) throws -> Note? {
    throw Failure.prepare
  }

  func allNotes() throws -> [Note] {
    throw Failure.prepare
  }

  func search(_ query: String) throws -> [Note] {
    throw Failure.prepare
  }

  func promoteNote(id: UUID, at date: Date) throws -> Note {
    throw Failure.prepare
  }

  func deleteNote(id: UUID) throws {
    throw Failure.prepare
  }

  func shutdown() throws {
    throw Failure.prepare
  }
}

private actor FailingEditorSettingsStore: EditorSettingsStoring {
  enum Failure: Error, Equatable {
    case save
  }

  private let settings: EditorSettings

  init(settings: EditorSettings) {
    self.settings = settings
  }

  func load() -> EditorSettings {
    settings
  }

  func save(_ settings: EditorSettings) throws {
    throw Failure.save
  }
}
