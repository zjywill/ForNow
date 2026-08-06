import Combine
import ForNowEditor
import Foundation

@MainActor
final class FindReplaceModel: ObservableObject {
  @Published private(set) var isPresented = false
  @Published private(set) var query = ""
  @Published private(set) var replacement = ""
  @Published private(set) var matchMode = FindMatchMode.contains
  @Published private(set) var isCaseSensitive = false
  @Published private(set) var isReplacementVisible = false
  @Published private(set) var matches: [FindSourceMatch] = []
  @Published private(set) var selectedIndex: Int?
  @Published private(set) var errorMessage: String?
  @Published private(set) var findFocusRequest: UInt64 = 0
  @Published private(set) var replacementFocusRequest: UInt64 = 0
  @Published private(set) var lastReplacementCount: Int?

  let editorTarget: EditorFindReplaceTarget

  private let engine: FindReplaceEngine
  private var isApplyingReplacement = false

  init(
    editorTarget: EditorFindReplaceTarget = EditorFindReplaceTarget(),
    engine: FindReplaceEngine = FindReplaceEngine()
  ) {
    self.editorTarget = editorTarget
    self.engine = engine
    editorTarget.sourceDidChange = { [weak self] in
      self?.editorSourceDidChange()
    }
  }

  var selectedMatch: FindSourceMatch? {
    guard let selectedIndex, matches.indices.contains(selectedIndex) else { return nil }
    return matches[selectedIndex]
  }

  var statusText: String {
    if let errorMessage {
      return errorMessage
    }
    if let lastReplacementCount {
      return "Replaced \(lastReplacementCount)"
    }
    guard !query.isEmpty else { return "" }
    guard let selectedIndex, !matches.isEmpty else { return "0 matches" }
    return "\(selectedIndex + 1) of \(matches.count)"
  }

  func present() {
    if !isPresented {
      isPresented = true
      editorTarget.setTemporarilyExpandsLinks(true)
      let selection = editorTarget.selectedRange
      if query.isEmpty,
        selection.length > 0,
        selection.length <= 512,
        let selectedSource = editorTarget.sourceText(in: selection),
        !selectedSource.contains(where: \Character.isNewline)
      {
        query = selectedSource
      }
      refresh(preferredLocation: selection.location)
    }
    findFocusRequest &+= 1
  }

  func dismiss() {
    guard isPresented else { return }
    isPresented = false
    errorMessage = nil
    lastReplacementCount = nil
    editorTarget.setTemporarilyExpandsLinks(false)
  }

  func setQuery(_ query: String) {
    guard isPresented, self.query != query else { return }
    self.query = query
    lastReplacementCount = nil
    refresh(preferredLocation: editorTarget.selectedRange.location)
  }

  func setReplacement(_ replacement: String) {
    guard self.replacement != replacement else { return }
    self.replacement = replacement
    lastReplacementCount = nil
  }

  func setMatchMode(_ mode: FindMatchMode) {
    guard matchMode != mode else { return }
    matchMode = mode
    lastReplacementCount = nil
    refresh(preferredLocation: editorTarget.selectedRange.location)
  }

  func setCaseSensitive(_ isCaseSensitive: Bool) {
    guard self.isCaseSensitive != isCaseSensitive else { return }
    self.isCaseSensitive = isCaseSensitive
    lastReplacementCount = nil
    refresh(preferredLocation: editorTarget.selectedRange.location)
  }

  func showReplacement() {
    guard isPresented else { return }
    isReplacementVisible = true
    replacementFocusRequest &+= 1
  }

  func toggleReplacementVisibility() {
    guard isPresented else { return }
    isReplacementVisible.toggle()
    if isReplacementVisible {
      replacementFocusRequest &+= 1
    } else {
      findFocusRequest &+= 1
    }
  }

  func navigate(by delta: Int) {
    guard !matches.isEmpty else { return }
    let current = selectedIndex ?? (delta >= 0 ? -1 : 0)
    let count = matches.count
    selectedIndex = (current + delta % count + count) % count
    lastReplacementCount = nil
    selectCurrentMatch()
  }

  @discardableResult
  func replaceCurrent() -> Bool {
    guard let match = selectedMatch, errorMessage == nil else { return false }
    let expectedSource = editorTarget.source
    let replacementLocation = match.range.location.utf16Offset + replacement.utf16.count
    isApplyingReplacement = true
    let replaced = editorTarget.replace(
      expectedSource: expectedSource,
      range: match.range,
      replacement: replacement
    )
    isApplyingReplacement = false
    guard replaced else {
      refresh(preferredLocation: editorTarget.selectedRange.location)
      return false
    }
    lastReplacementCount = 1
    refresh(
      preferredLocation: replacementLocation,
      preservesReplacementCount: true,
      preservesSelectedRange: false
    )
    return true
  }

  @discardableResult
  func replaceAll() -> Int {
    let source = editorTarget.source
    let plan: FindReplaceAllPlan
    do {
      plan = try engine.replacingAll(
        in: source,
        request: request,
        replacement: replacement
      )
    } catch let error as FindReplaceError {
      errorMessage = error.localizedDescription
      matches = []
      selectedIndex = nil
      return 0
    } catch {
      errorMessage = FindReplaceError.invalidRegularExpression.localizedDescription
      matches = []
      selectedIndex = nil
      return 0
    }
    guard plan.replacementCount > 0 else {
      lastReplacementCount = nil
      return 0
    }

    isApplyingReplacement = true
    let replaced = editorTarget.replaceAll(with: plan)
    isApplyingReplacement = false
    guard replaced else {
      refresh(preferredLocation: editorTarget.selectedRange.location)
      return 0
    }
    lastReplacementCount = plan.replacementCount
    refresh(
      preferredLocation: editorTarget.selectedRange.location,
      preservesReplacementCount: true
    )
    return plan.replacementCount
  }

  private var request: FindRequest {
    FindRequest(
      query: query,
      mode: matchMode,
      isCaseSensitive: isCaseSensitive
    )
  }

  private func editorSourceDidChange() {
    guard isPresented, !isApplyingReplacement else { return }
    lastReplacementCount = nil
    refresh(preferredLocation: editorTarget.selectedRange.location)
  }

  private func refresh(
    preferredLocation: Int,
    preservesReplacementCount: Bool = false,
    preservesSelectedRange: Bool = true
  ) {
    let previousRange = preservesSelectedRange ? selectedMatch?.range : nil
    do {
      let updatedMatches = try engine.matches(in: editorTarget.source, request: request)
      errorMessage = nil
      matches = updatedMatches
      if !preservesReplacementCount {
        lastReplacementCount = nil
      }
      guard !updatedMatches.isEmpty else {
        selectedIndex = nil
        return
      }
      if let previousRange,
        let previousIndex = updatedMatches.firstIndex(where: { $0.range == previousRange })
      {
        selectedIndex = previousIndex
      } else if let exactSelectionIndex = updatedMatches.firstIndex(where: {
        $0.range.nsRange == editorTarget.selectedRange
      }) {
        selectedIndex = exactSelectionIndex
      } else {
        selectedIndex =
          updatedMatches.firstIndex(where: {
            $0.range.location.utf16Offset >= preferredLocation
          }) ?? 0
      }
      selectCurrentMatch()
    } catch let error as FindReplaceError {
      errorMessage = error.localizedDescription
      matches = []
      selectedIndex = nil
      if !preservesReplacementCount {
        lastReplacementCount = nil
      }
    } catch {
      errorMessage = FindReplaceError.invalidRegularExpression.localizedDescription
      matches = []
      selectedIndex = nil
      if !preservesReplacementCount {
        lastReplacementCount = nil
      }
    }
  }

  private func selectCurrentMatch() {
    guard let selectedMatch else { return }
    editorTarget.select(selectedMatch.range)
  }
}
