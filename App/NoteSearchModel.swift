import Combine
import ForNowCore
import Foundation

struct NoteSearchResultPresentation: Equatable, Identifiable {
  let noteID: UUID
  let title: String
  let context: String
  let modifiedAt: Date

  var id: UUID { noteID }

  var accessibilityDescription: String {
    let timestamp = modifiedAt.formatted(date: .abbreviated, time: .shortened)
    if context == title {
      return "\(title). Modified \(timestamp)"
    }
    return "\(title). \(context). Modified \(timestamp)"
  }

  init(note: Note, query: String) {
    noteID = note.id
    modifiedAt = note.modifiedAt

    let lines = note.body.split(whereSeparator: \Character.isNewline)
    let firstLine = lines.first.map(String.init) ?? note.body
    let compactTitle = Self.compact(firstLine)
    title = Self.truncate(compactTitle.isEmpty ? "Untitled note" : compactTitle, to: 80)

    let compactBody = Self.compact(note.body)
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedQuery.isEmpty {
      let remainder =
        compactBody.hasPrefix(compactTitle)
        ? String(compactBody.dropFirst(compactTitle.count)).trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        : compactBody
      context = Self.truncate(remainder.isEmpty ? compactBody : remainder, to: 140)
    } else {
      context = Self.excerpt(around: normalizedQuery, in: compactBody)
    }
  }

  private static func compact(_ source: String) -> String {
    source
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private static func excerpt(around query: String, in source: String) -> String {
    guard
      let range = source.range(
        of: query,
        options: [.caseInsensitive, .diacriticInsensitive]
      )
    else {
      return truncate(source, to: 140)
    }
    let start =
      source.index(
        range.lowerBound,
        offsetBy: -48,
        limitedBy: source.startIndex
      ) ?? source.startIndex
    let end =
      source.index(
        range.upperBound,
        offsetBy: 88,
        limitedBy: source.endIndex
      ) ?? source.endIndex
    let prefix = start == source.startIndex ? "" : "..."
    let suffix = end == source.endIndex ? "" : "..."
    return prefix + source[start..<end] + suffix
  }

  private static func truncate(_ source: String, to limit: Int) -> String {
    guard source.count > limit else { return source }
    return String(source.prefix(max(0, limit - 3))) + "..."
  }
}

@MainActor
final class NoteSearchModel: ObservableObject {
  @Published private(set) var isPresented = false
  @Published private(set) var query = ""
  @Published private(set) var results: [NoteSearchResultPresentation] = []
  @Published private(set) var selectedIndex = 0
  @Published private(set) var hasMore = false
  @Published private(set) var isSearching = false
  @Published private(set) var isActivating = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var focusRequest: UInt64 = 0

  var selectedResult: NoteSearchResultPresentation? {
    guard results.indices.contains(selectedIndex) else { return nil }
    return results[selectedIndex]
  }

  private let repository: any NoteRepository
  private let noteSession: NoteSessionModel
  private let prepareLiveSource: @MainActor () async throws -> Void
  private let pageSize: Int
  private var generation: UInt64 = 0
  private var preparationTask: Task<Void, Error>?
  private var searchTask: Task<Void, Never>?

  init(
    repository: any NoteRepository,
    noteSession: NoteSessionModel,
    prepareLiveSource: @escaping @MainActor () async throws -> Void = {},
    pageSize: Int = 50
  ) {
    self.repository = repository
    self.noteSession = noteSession
    self.prepareLiveSource = prepareLiveSource
    self.pageSize = max(1, pageSize)
  }

  func present() {
    guard !isPresented else {
      focusRequest &+= 1
      return
    }
    generation &+= 1
    searchTask?.cancel()
    preparationTask?.cancel()
    query = ""
    results = []
    selectedIndex = 0
    hasMore = false
    errorMessage = nil
    isPresented = true
    focusRequest &+= 1
    preparationTask = Task { [weak self] in
      guard let self else { return }
      try await self.prepareLiveSource()
      try await self.noteSession.prepareForSearch()
    }
    loadPage(reset: true)
  }

  func dismiss() {
    guard isPresented else { return }
    generation &+= 1
    searchTask?.cancel()
    preparationTask?.cancel()
    searchTask = nil
    preparationTask = nil
    isSearching = false
    isActivating = false
    isPresented = false
  }

  func setQuery(_ query: String) {
    guard isPresented, self.query != query else { return }
    self.query = query
    loadPage(reset: true)
  }

  func moveSelection(by delta: Int) {
    guard !results.isEmpty else { return }
    selectedIndex = min(max(0, selectedIndex + delta), results.count - 1)
  }

  func selectResult(id: UUID) {
    guard let index = results.firstIndex(where: { $0.id == id }) else { return }
    selectedIndex = index
  }

  func loadNextPageIfNeeded(after resultID: UUID) {
    guard hasMore, !isSearching, results.last?.id == resultID else { return }
    loadPage(reset: false)
  }

  func activateSelected() async throws -> Bool {
    guard let selectedResult, !isActivating else { return false }
    isActivating = true
    searchTask?.cancel()
    defer { isActivating = false }
    if let preparationTask {
      try await preparationTask.value
    }
    try await noteSession.promoteAndOpenSearchResult(noteID: selectedResult.noteID)
    return true
  }

  func waitForIdle() async {
    if let preparationTask {
      _ = await preparationTask.result
    }
    await searchTask?.value
  }

  private func loadPage(reset: Bool) {
    generation &+= 1
    let requestGeneration = generation
    let requestQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let offset = reset ? 0 : results.count
    let preparationTask = preparationTask
    searchTask?.cancel()
    if reset {
      results = []
      selectedIndex = 0
      hasMore = false
    }
    isSearching = true
    errorMessage = nil

    searchTask = Task { [weak self] in
      guard let self else { return }
      do {
        if let preparationTask {
          try await preparationTask.value
        }
        try Task.checkCancellation()
        let page = try await repository.searchPage(
          requestQuery,
          limit: pageSize,
          offset: offset
        )
        try Task.checkCancellation()
        guard generation == requestGeneration,
          query.trimmingCharacters(
            in: .whitespacesAndNewlines
          ) == requestQuery
        else { return }
        let presentations = page.notes.map {
          NoteSearchResultPresentation(note: $0, query: requestQuery)
        }
        if reset {
          results = presentations
        } else {
          let existingIDs = Set(results.map(\.id))
          results.append(contentsOf: presentations.filter { !existingIDs.contains($0.id) })
        }
        selectedIndex = min(selectedIndex, max(0, results.count - 1))
        hasMore = page.hasMore
        isSearching = false
      } catch is CancellationError {
        return
      } catch {
        guard generation == requestGeneration else { return }
        errorMessage = "Search is unavailable."
        hasMore = false
        isSearching = false
      }
    }
  }
}
