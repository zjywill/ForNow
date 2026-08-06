import AppKit
import ForNowCore
import ForNowWindowing
import XCTest

@testable import ForNow

final class NoteSearchTests: XCTestCase {
  @MainActor
  func test_UT_NOTE_007_EmptyQueryPaginationArrowsAndCancellation() async throws {
    let notes = [
      makeNote(suffix: 101, body: "Shared title\nold alpha detail", orderKey: 0),
      makeNote(suffix: 102, body: "Shared title\nmiddle beta detail", orderKey: 1),
      makeNote(suffix: 103, body: "Recent alpha\nthird detail", orderKey: 2),
      makeNote(suffix: 104, body: "Newest beta\nfourth detail", orderKey: 3),
    ]
    let repository = InMemoryNoteRepository(notes: notes)
    let session = makeSession(repository: repository, generatedID: uuid(suffix: 105))
    let model = NoteSearchModel(repository: repository, noteSession: session, pageSize: 2)
    try await repository.prepare()
    try await session.start()

    model.present()
    await model.waitForIdle()
    XCTAssertTrue(model.isPresented)
    XCTAssertEqual(model.results.map(\.id), [notes[3].id, notes[2].id])
    XCTAssertTrue(model.hasMore)

    model.moveSelection(by: 1)
    model.moveSelection(by: 10)
    XCTAssertEqual(model.selectedResult?.id, notes[2].id)
    model.loadNextPageIfNeeded(after: notes[2].id)
    await model.waitForIdle()
    XCTAssertEqual(model.results.map(\.id), [notes[3].id, notes[2].id, notes[1].id, notes[0].id])
    XCTAssertFalse(model.hasMore)

    model.setQuery("alpha")
    model.setQuery("beta")
    await model.waitForIdle()
    XCTAssertEqual(model.query, "beta")
    XCTAssertEqual(model.results.map(\.id), [notes[3].id, notes[1].id])
    XCTAssertFalse(model.isSearching)

    model.dismiss()
    XCTAssertFalse(model.isPresented)
  }

  @MainActor
  func test_UIT_NOTE_007_OpenFlushesSourceAndEnterPromotesThroughSharedTransaction()
    async throws
  {
    let current = makeNote(suffix: 111, body: "current source", orderKey: 2)
    let target = makeNote(suffix: 112, body: "target note\nsearch match", orderKey: 1)
    let oldest = makeNote(suffix: 113, body: "oldest", orderKey: 0)
    let repository = InMemoryNoteRepository(notes: [oldest, target, current])
    let environment = AppEnvironment.test(
      repository: repository,
      uuidGenerator: SequenceUUIDGenerator(values: [uuid(suffix: 114)]),
      lifecycleSettings: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: false)
      )
    )
    try await environment.start()
    environment.noteSession.editorTextChanged(
      "current source edited immediately before search",
      hasMarkedText: false
    )

    environment.openSearch()
    environment.noteSearch.setQuery("search match")
    await environment.noteSearch.waitForIdle()
    XCTAssertEqual(environment.noteSearch.results.map(\.id), [target.id])

    await environment.activateSelectedSearchResult()

    let orderedNotes = try await repository.allNotes()
    let savedCurrent = try await repository.note(id: current.id)
    XCTAssertFalse(environment.noteSearch.isPresented)
    XCTAssertEqual(environment.noteSession.currentNoteID, target.id)
    XCTAssertEqual(orderedNotes.first?.id, target.id)
    XCTAssertEqual(
      savedCurrent?.body,
      "current source edited immediately before search"
    )
    try await environment.shutdown()
  }

  @MainActor
  func test_UT_NOTE_007_ResultContextAndVoiceOverDistinguishDuplicateTitles() {
    let first = NoteSearchResultPresentation(
      note: makeNote(
        suffix: 121,
        body: "Shared title\nalpha project context",
        orderKey: 1
      ),
      query: ""
    )
    let second = NoteSearchResultPresentation(
      note: makeNote(
        suffix: 122,
        body: "Shared title\nbeta project context",
        orderKey: 0
      ),
      query: ""
    )

    XCTAssertEqual(first.title, second.title)
    XCTAssertNotEqual(first.context, second.context)
    XCTAssertTrue(first.accessibilityDescription.contains("alpha project context"))
    XCTAssertTrue(second.accessibilityDescription.contains("beta project context"))
    XCTAssertTrue(first.accessibilityDescription.contains("Modified"))
  }

  @MainActor
  func test_UT_NOTE_007_SearchPreparationCommitsLiveMarkedEditorSource() async throws {
    let shortcutName = "forNow.tests.searchPreparation"
    defer {
      UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_\(shortcutName)")
    }
    let shortcut = ValidatedGlobalShortcut(
      nameIdentifier: shortcutName,
      preflight: SearchShortcutPreflight()
    )
    let coordinator = SwiftUIWindowCoordinator(shortcut: shortcut)
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
    textView.string = "live source "
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    textView.setMarkedText(
      "中文",
      selectedRange: NSRange(location: 2, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    XCTAssertTrue(textView.hasMarkedText())
    var flushedSource: String?
    coordinator.configure(
      WindowCoordinatorCallbacks(
        makeContentViewController: {
          let controller = NSViewController()
          controller.view = textView
          return controller
        },
        flushPendingSource: { source, _ in
          flushedSource = source
        },
        windowDidReopen: {},
        windowDidClose: {}
      )
    )
    coordinator.applyConfiguration(WindowConfiguration(presence: .dock))
    coordinator.start()
    await coordinator.waitForPendingTransitions()

    try await coordinator.flushPendingSourceForCommand()

    XCTAssertFalse(textView.hasMarkedText())
    XCTAssertEqual(flushedSource, "live source 中文")
    coordinator.stop()
  }

  @MainActor
  private func makeSession(
    repository: InMemoryNoteRepository,
    generatedID: UUID
  ) -> NoteSessionModel {
    NoteSessionModel(
      repository: repository,
      clock: FixedWallClock(Date(timeIntervalSince1970: 1_000)),
      uuidGenerator: SequenceUUIDGenerator(values: [generatedID]),
      settingsStore: InMemoryLifecycleSettingsStore(
        settings: LifecycleSettings(createsNewNoteOnLaunch: false)
      )
    )
  }

  private func makeNote(suffix: Int, body: String, orderKey: Int64) -> Note {
    Note(
      id: uuid(suffix: suffix),
      body: body,
      createdAt: Date(timeIntervalSince1970: Double(orderKey)),
      modifiedAt: Date(timeIntervalSince1970: 100 + Double(orderKey)),
      orderKey: orderKey
    )
  }

  private func uuid(suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
  }
}

@MainActor
private struct SearchShortcutPreflight: GlobalShortcutPreflighting {
  func registrationStatus(for candidate: GlobalShortcutCandidate) -> Int32 {
    0
  }
}
