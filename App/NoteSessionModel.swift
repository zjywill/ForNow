import Combine
import ForNowCore
import Foundation

enum NoteSessionPhase: Equatable, Sendable {
  case loading
  case transient
  case durable
}

@MainActor
final class NoteSessionModel: ObservableObject {
  @Published private(set) var text = ""
  @Published private(set) var currentNoteID: UUID?
  @Published private(set) var phase: NoteSessionPhase = .loading
  @Published private(set) var noteCount = 0
  @Published private(set) var settings = LifecycleSettings()
  @Published private(set) var hasPersistenceFailure = false
  @Published private(set) var navigationEntryToken: UInt64 = 0
  @Published private(set) var viewportRestorationToken: UInt64 = 0
  @Published private(set) var isDeleteConfirmationPending = false

  var visibleNoteCount: Int? {
    settings.showsNoteCount ? noteCount : nil
  }

  var editorSelectionRange: NSRange {
    NSRange(location: selection.location, length: selection.length)
  }

  var editorScrollOffset: Int {
    scrollOffset
  }

  private let repository: any NoteRepository
  private let clock: any WallClock
  private let uuidGenerator: any UUIDGenerating
  private let settingsStore: any LifecycleSettingsStoring
  private var meaningfulContentPolicy: MeaningfulContentPolicy
  private let resumeNotePolicy: ResumeNotePolicy
  private let deleteConfirmationPolicy: DeleteConfirmationPolicy

  private var committedText = ""
  private var hasMarkedText = false
  private var createdAt: Date?
  private var selection = NoteSelection()
  private var scrollOffset = 0
  private var editRevision: UInt64 = 0
  private var persistenceTask: Task<Void, Never>?

  init(
    repository: any NoteRepository,
    clock: any WallClock,
    uuidGenerator: any UUIDGenerating,
    settingsStore: any LifecycleSettingsStoring,
    meaningfulContentPolicy: MeaningfulContentPolicy = MeaningfulContentPolicy(),
    resumeNotePolicy: ResumeNotePolicy = ResumeNotePolicy(),
    deleteConfirmationPolicy: DeleteConfirmationPolicy = DeleteConfirmationPolicy()
  ) {
    self.repository = repository
    self.clock = clock
    self.uuidGenerator = uuidGenerator
    self.settingsStore = settingsStore
    self.meaningfulContentPolicy = meaningfulContentPolicy
    self.resumeNotePolicy = resumeNotePolicy
    self.deleteConfirmationPolicy = deleteConfirmationPolicy
  }

  func start() async throws {
    guard phase == .loading else { return }
    let pendingLaunchEdit =
      editRevision > 0
      ? (text: text, committedText: committedText, hasMarkedText: hasMarkedText)
      : nil
    settings = await settingsStore.load()
    let notes = try await repository.allNotes()
    let lastWindowClosedAt = await settingsStore.lastWindowClosedAt()
    let createsNewNote = resumeNotePolicy.shouldCreateNewNote(
      for: .launch,
      settings: settings,
      now: clock.now(),
      lastWindowClosedAt: lastWindowClosedAt
    )
    noteCount = notes.count
    if let pendingLaunchEdit {
      await createTransientNote()
      text = pendingLaunchEdit.text
      committedText = pendingLaunchEdit.committedText
      hasMarkedText = pendingLaunchEdit.hasMarkedText
      editRevision &+= 1
      try await persistIfCurrent(revision: editRevision)
    } else if notes.isEmpty || createsNewNote {
      await createTransientNote()
    } else if let note = notes.first {
      load(note)
    }
  }

  func editorTextChanged(_ newText: String, hasMarkedText: Bool) {
    updateInMemory(newText, hasMarkedText: hasMarkedText)
    let revision = editRevision
    persistenceTask?.cancel()
    persistenceTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.persistIfCurrent(revision: revision)
      } catch is CancellationError {
        return
      } catch {
        self.hasPersistenceFailure = true
      }
    }
  }

  func editorViewportChanged(selectionRange: NSRange, scrollOffset: Int) {
    let sourceLength = text.utf16.count
    let clampedLocation = min(max(0, selectionRange.location), sourceLength)
    let clampedLength = min(
      max(0, selectionRange.length),
      sourceLength - clampedLocation
    )
    selection = NoteSelection(location: clampedLocation, length: clampedLength)
    self.scrollOffset = max(0, scrollOffset)
  }

  func applyEditorText(_ newText: String, hasMarkedText: Bool) async throws {
    persistenceTask?.cancel()
    persistenceTask = nil
    updateInMemory(newText, hasMarkedText: hasMarkedText)
    try await persistIfCurrent(revision: editRevision)
  }

  func prepareForDeparture() async throws {
    persistenceTask?.cancel()
    persistenceTask = nil
    guard let currentNoteID else { return }

    let state = meaningfulContentPolicy.classify(committedText, hasMarkedText: false)
    switch state {
    case .meaningful:
      if phase == .transient {
        phase = .durable
        noteCount += 1
      }
      try await scheduleCurrentDraft(noteID: currentNoteID)
    case .blank, .provisionalMarkedText:
      await repository.discardPending(noteID: currentNoteID)
      if phase == .durable {
        try await repository.deleteNote(id: currentNoteID)
        noteCount = max(0, noteCount - 1)
        phase = .transient
      }
    }
  }

  func recordWindowClosed() async throws {
    try await prepareForDeparture()
    await settingsStore.recordWindowClosed(at: clock.now())
  }

  func reopen() async throws {
    let now = clock.now()
    let shouldCreate = resumeNotePolicy.shouldCreateNewNote(
      for: .reopen,
      settings: settings,
      now: now,
      lastWindowClosedAt: await settingsStore.lastWindowClosedAt()
    )
    guard shouldCreate else { return }
    try await prepareForDeparture()
    await createTransientNote(armsDirectionalEntry: true)
  }

  func updateSettings(_ settings: LifecycleSettings) async throws {
    try await settingsStore.save(settings)
    self.settings = settings
  }

  func updateMeaningfulContentPolicy(_ policy: MeaningfulContentPolicy) async throws {
    guard meaningfulContentPolicy != policy else { return }
    meaningfulContentPolicy = policy
    guard phase != .loading else { return }
    editRevision &+= 1
    try await persistIfCurrent(revision: editRevision)
  }

  func navigate(_ direction: NoteNavigationDirection) async throws {
    let departingID = currentNoteID
    let departingContentState = meaningfulContentPolicy.classify(
      committedText,
      hasMarkedText: false
    )
    try await prepareForDeparture()
    _ = try await repository.flush()
    let notes = try await repository.allNotes()
    noteCount = notes.count

    if departingContentState != .meaningful || phase == .transient {
      if direction == .previous, let newest = notes.first {
        load(newest, armsDirectionalEntry: true)
      }
      return
    }

    guard let departingID,
      let currentIndex = notes.firstIndex(where: { $0.id == departingID })
    else {
      if let newest = notes.first {
        load(newest, armsDirectionalEntry: true)
      } else {
        await createTransientNote(armsDirectionalEntry: true)
      }
      return
    }

    switch direction {
    case .previous:
      let olderIndex = currentIndex + 1
      guard notes.indices.contains(olderIndex) else { return }
      load(notes[olderIndex], armsDirectionalEntry: true)
    case .next:
      let newerIndex = currentIndex - 1
      if notes.indices.contains(newerIndex) {
        load(notes[newerIndex], armsDirectionalEntry: true)
      } else {
        await createTransientNote(armsDirectionalEntry: true)
      }
    }
  }

  func jumpToNewest() async throws {
    try await prepareForDeparture()
    _ = try await repository.flush()
    let notes = try await repository.allNotes()
    noteCount = notes.count
    guard let newest = notes.first else { return }
    guard newest.id != currentNoteID else { return }
    load(newest, armsDirectionalEntry: true)
  }

  func promoteCurrent() async throws {
    guard let currentNoteID,
      meaningfulContentPolicy.classify(committedText, hasMarkedText: false) == .meaningful
    else { return }
    try await promoteAndOpen(noteID: currentNoteID)
  }

  func promoteAndOpenSearchResult(noteID: UUID) async throws {
    try await promoteAndOpen(noteID: noteID)
  }

  func prepareForSearch() async throws {
    try await prepareForDeparture()
    _ = try await repository.flush()
  }

  private func promoteAndOpen(noteID: UUID) async throws {
    try await prepareForDeparture()
    _ = try await repository.flush()
    let promoted = try await repository.promoteNote(id: noteID, at: clock.now())
    load(promoted, armsDirectionalEntry: true)
  }

  func requestDeletion() async throws -> DeleteRequestOutcome {
    guard currentNoteID != nil else { return .noNote }
    let contentState = meaningfulContentPolicy.classify(
      committedText,
      hasMarkedText: hasMarkedText
    )
    if deleteConfirmationPolicy.requiresConfirmation(
      contentState: contentState,
      suppressesWarning: settings.suppressesDeleteWarning
    ) {
      isDeleteConfirmationPending = true
      return .confirmationRequired
    }
    try await deleteCurrentNote()
    return .deleted
  }

  func resolveDeletion(confirm: Bool, suppressFutureWarning: Bool = false) async throws {
    guard isDeleteConfirmationPending else { return }
    isDeleteConfirmationPending = false
    guard confirm else { return }
    if suppressFutureWarning {
      var updatedSettings = settings
      updatedSettings.suppressesDeleteWarning = true
      try await updateSettings(updatedSettings)
    }
    try await deleteCurrentNote()
  }

  func resetDeleteWarning() async throws {
    guard settings.suppressesDeleteWarning else { return }
    var updatedSettings = settings
    updatedSettings.suppressesDeleteWarning = false
    try await updateSettings(updatedSettings)
  }

  private func updateInMemory(_ newText: String, hasMarkedText: Bool) {
    text = newText
    self.hasMarkedText = hasMarkedText
    if !hasMarkedText {
      committedText = newText
    }
    editRevision &+= 1
    hasPersistenceFailure = false
  }

  private func persistIfCurrent(revision: UInt64) async throws {
    guard revision == editRevision, let currentNoteID else { return }
    let contentState = meaningfulContentPolicy.classify(
      committedText,
      hasMarkedText: hasMarkedText
    )
    switch contentState {
    case .provisionalMarkedText:
      return
    case .blank:
      await repository.discardPending(noteID: currentNoteID)
    case .meaningful:
      if phase == .transient {
        phase = .durable
        noteCount += 1
      }
      try await scheduleCurrentDraft(noteID: currentNoteID)
    }
  }

  private func scheduleCurrentDraft(noteID: UUID) async throws {
    try await repository.schedule(
      NoteDraft(
        id: noteID,
        body: committedText,
        createdAt: createdAt,
        modifiedAt: clock.now(),
        selection: selection,
        scrollOffset: scrollOffset
      )
    )
  }

  private func deleteCurrentNote() async throws {
    persistenceTask?.cancel()
    persistenceTask = nil
    guard let currentNoteID else { return }
    await repository.discardPending(noteID: currentNoteID)
    if phase == .durable {
      try await repository.deleteNote(id: currentNoteID)
    }
    let notes = try await repository.allNotes()
    noteCount = notes.count
    if let newest = notes.first {
      load(newest, armsDirectionalEntry: true)
    } else {
      await createTransientNote(armsDirectionalEntry: true)
    }
  }

  private func createTransientNote(armsDirectionalEntry: Bool = false) async {
    let now = clock.now()
    currentNoteID = await uuidGenerator.next()
    text = ""
    committedText = ""
    hasMarkedText = false
    createdAt = now
    selection = NoteSelection()
    scrollOffset = 0
    phase = .transient
    editRevision &+= 1
    viewportRestorationToken &+= 1
    if armsDirectionalEntry {
      navigationEntryToken &+= 1
    }
  }

  private func load(_ note: Note, armsDirectionalEntry: Bool = false) {
    currentNoteID = note.id
    text = note.body
    committedText = note.body
    hasMarkedText = false
    createdAt = note.createdAt
    let sourceLength = note.body.utf16.count
    let clampedLocation = min(max(0, note.selection.location), sourceLength)
    selection = NoteSelection(
      location: clampedLocation,
      length: min(max(0, note.selection.length), sourceLength - clampedLocation)
    )
    scrollOffset = max(0, note.scrollOffset)
    phase = .durable
    editRevision &+= 1
    viewportRestorationToken &+= 1
    if armsDirectionalEntry {
      navigationEntryToken &+= 1
    }
  }
}
