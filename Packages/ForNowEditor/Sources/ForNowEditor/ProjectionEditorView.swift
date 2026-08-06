import AppKit
import ForNowCore
import ForNowDesign
import ForNowModes
import SwiftUI

public struct EditorViewportState: Sendable, Equatable {
  public let selection: SourceSelection
  public let verticalScrollOffset: Int

  public init(selection: SourceSelection, verticalScrollOffset: Int) {
    self.selection = selection
    self.verticalScrollOffset = max(0, verticalScrollOffset)
  }

  public init(selectionRange: NSRange = NSRange(location: 0, length: 0), scrollOffset: Int = 0) {
    self.init(
      selection: SourceSelection(range: SourceRange(selectionRange)),
      verticalScrollOffset: scrollOffset
    )
  }
}

public enum EditorTimerInteraction: Sendable, Equatable {
  case singleClick
  case stop
}

public struct ProjectionEditorView: NSViewRepresentable {
  private let sourceText: String
  private let accessibilityLabel: String
  private let sourceDidChange: (@MainActor (String, Bool) -> Void)?
  private let viewportState: EditorViewportState
  private let viewportRestorationToken: UInt64
  private let viewportDidChange: (@MainActor (EditorViewportState) -> Void)?
  private let navigationEntryToken: UInt64
  private let navigationHandler: (@MainActor (NoteNavigationDirection) -> Void)?
  private let pasteSettings: PasteSettings
  private let editorSettings: EditorSettings
  private let appearanceSettings: AppearanceSettings
  private let modeSettings: ModeSettings
  private let mathSettings: MathSettings
  private let currencyContext: CurrencyConversionContext
  private let timerSnapshot: TimerSnapshot?
  private let stopsTimerOnEscape: Bool
  private let autoPasteIsActive: Bool
  private let expandedLinkIdentities: Set<LinkIdentity>
  private let linkExpansionDidToggle: (@MainActor (LinkIdentity) -> Void)?
  private let findReplaceTarget: EditorFindReplaceTarget?
  private let slashCommandTarget: EditorSlashCommandTarget?
  private let ocrTarget: EditorOCRTarget?
  private let timerCommandDidCommit: (@MainActor (TimerCommand, String) -> Void)?
  private let timerInteractionHandler: (@MainActor (EditorTimerInteraction) -> Void)?
  private let autoPasteCommandDidCommit: (@MainActor (AutoPasteCommand, String) -> Void)?
  private let autoPasteStopHandler: (@MainActor () -> Void)?
  private let pasteboardDidWrite: (@MainActor () -> Void)?

  public init(initialText: String) {
    sourceText = initialText
    accessibilityLabel = "Editor projection source"
    sourceDidChange = nil
    viewportState = EditorViewportState()
    viewportRestorationToken = 0
    viewportDidChange = nil
    navigationEntryToken = 0
    navigationHandler = nil
    pasteSettings = PasteSettings()
    editorSettings = EditorSettings()
    appearanceSettings = AppearanceSettings()
    modeSettings = ModeSettings()
    mathSettings = MathSettings()
    currencyContext = CurrencyConversionContext()
    timerSnapshot = nil
    stopsTimerOnEscape = false
    autoPasteIsActive = false
    expandedLinkIdentities = []
    linkExpansionDidToggle = nil
    findReplaceTarget = nil
    slashCommandTarget = nil
    ocrTarget = nil
    timerCommandDidCommit = nil
    timerInteractionHandler = nil
    autoPasteCommandDidCommit = nil
    autoPasteStopHandler = nil
    pasteboardDidWrite = nil
  }

  public init(
    sourceText: String,
    accessibilityLabel: String,
    viewportState: EditorViewportState,
    viewportRestorationToken: UInt64,
    navigationEntryToken: UInt64,
    pasteSettings: PasteSettings,
    editorSettings: EditorSettings = EditorSettings(),
    appearanceSettings: AppearanceSettings = AppearanceSettings(),
    modeSettings: ModeSettings = ModeSettings(),
    mathSettings: MathSettings = MathSettings(),
    currencyContext: CurrencyConversionContext = CurrencyConversionContext(),
    timerSnapshot: TimerSnapshot? = nil,
    stopsTimerOnEscape: Bool = false,
    autoPasteIsActive: Bool = false,
    expandedLinkIdentities: Set<LinkIdentity> = [],
    findReplaceTarget: EditorFindReplaceTarget? = nil,
    slashCommandTarget: EditorSlashCommandTarget? = nil,
    ocrTarget: EditorOCRTarget? = nil,
    sourceDidChange: @escaping @MainActor (String, Bool) -> Void,
    viewportDidChange: @escaping @MainActor (EditorViewportState) -> Void,
    navigationHandler: @escaping @MainActor (NoteNavigationDirection) -> Void,
    linkExpansionDidToggle: @escaping @MainActor (LinkIdentity) -> Void = { _ in },
    timerCommandDidCommit: @escaping @MainActor (TimerCommand, String) -> Void = { _, _ in },
    timerInteractionHandler: @escaping @MainActor (EditorTimerInteraction) -> Void = { _ in },
    autoPasteCommandDidCommit: @escaping @MainActor (AutoPasteCommand, String) -> Void = { _, _ in
    },
    autoPasteStopHandler: @escaping @MainActor () -> Void = {},
    pasteboardDidWrite: @escaping @MainActor () -> Void = {}
  ) {
    self.sourceText = sourceText
    self.accessibilityLabel = accessibilityLabel
    self.viewportState = viewportState
    self.viewportRestorationToken = viewportRestorationToken
    self.navigationEntryToken = navigationEntryToken
    self.pasteSettings = pasteSettings
    self.editorSettings = editorSettings
    self.appearanceSettings = appearanceSettings
    self.modeSettings = modeSettings
    self.mathSettings = mathSettings
    self.currencyContext = currencyContext
    self.timerSnapshot = timerSnapshot
    self.stopsTimerOnEscape = stopsTimerOnEscape
    self.autoPasteIsActive = autoPasteIsActive
    self.expandedLinkIdentities = expandedLinkIdentities
    self.findReplaceTarget = findReplaceTarget
    self.slashCommandTarget = slashCommandTarget
    self.ocrTarget = ocrTarget
    self.sourceDidChange = sourceDidChange
    self.viewportDidChange = viewportDidChange
    self.navigationHandler = navigationHandler
    self.linkExpansionDidToggle = linkExpansionDidToggle
    self.timerCommandDidCommit = timerCommandDidCommit
    self.timerInteractionHandler = timerInteractionHandler
    self.autoPasteCommandDidCommit = autoPasteCommandDidCommit
    self.autoPasteStopHandler = autoPasteStopHandler
    self.pasteboardDidWrite = pasteboardDidWrite
  }

  public func makeNSView(context: Context) -> ProjectionEditorContainer {
    let container = ProjectionEditorContainer(
      initialText: sourceText,
      editorSettings: editorSettings,
      appearanceSettings: appearanceSettings,
      modeSettings: modeSettings,
      mathSettings: mathSettings,
      currencyContext: currencyContext
    )
    container.sourceDidChange = { [sourceDidChange, weak findReplaceTarget] source, hasMarkedText in
      sourceDidChange?(source, hasMarkedText)
      findReplaceTarget?.notifySourceDidChange()
    }
    container.viewportDidChange = viewportDidChange
    container.navigationHandler = navigationHandler
    container.pasteSettings = pasteSettings
    container.expandedLinkIdentities = expandedLinkIdentities
    container.timerSnapshot = timerSnapshot
    container.stopsTimerOnEscape = stopsTimerOnEscape
    container.autoPasteIsActive = autoPasteIsActive
    container.linkExpansionDidToggle = linkExpansionDidToggle
    container.timerCommandDidCommit = timerCommandDidCommit
    container.timerInteractionHandler = timerInteractionHandler
    container.autoPasteCommandDidCommit = autoPasteCommandDidCommit
    container.autoPasteStopHandler = autoPasteStopHandler
    container.pasteboardDidWrite = pasteboardDidWrite
    findReplaceTarget?.attach(to: container)
    slashCommandTarget?.attach(to: container)
    ocrTarget?.attach(to: container)
    container.textView.setAccessibilityLabel(accessibilityLabel)
    container.applyViewportRestoration(viewportState, token: viewportRestorationToken)
    container.armDirectionalEntry(token: navigationEntryToken)
    return container
  }

  public func updateNSView(_ nsView: ProjectionEditorContainer, context: Context) {
    nsView.sourceDidChange = { [sourceDidChange, weak findReplaceTarget] source, hasMarkedText in
      sourceDidChange?(source, hasMarkedText)
      findReplaceTarget?.notifySourceDidChange()
    }
    nsView.viewportDidChange = viewportDidChange
    nsView.navigationHandler = navigationHandler
    nsView.pasteSettings = pasteSettings
    nsView.editorSettings = editorSettings
    nsView.appearanceSettings = appearanceSettings
    nsView.modeSettings = modeSettings
    nsView.mathSettings = mathSettings
    nsView.currencyContext = currencyContext
    nsView.expandedLinkIdentities = expandedLinkIdentities
    nsView.timerSnapshot = timerSnapshot
    nsView.stopsTimerOnEscape = stopsTimerOnEscape
    nsView.autoPasteIsActive = autoPasteIsActive
    nsView.linkExpansionDidToggle = linkExpansionDidToggle
    nsView.timerCommandDidCommit = timerCommandDidCommit
    nsView.timerInteractionHandler = timerInteractionHandler
    nsView.autoPasteCommandDidCommit = autoPasteCommandDidCommit
    nsView.autoPasteStopHandler = autoPasteStopHandler
    nsView.pasteboardDidWrite = pasteboardDidWrite
    findReplaceTarget?.attach(to: nsView)
    slashCommandTarget?.attach(to: nsView)
    ocrTarget?.attach(to: nsView)
    nsView.textView.setAccessibilityLabel(accessibilityLabel)
    nsView.applyExternalSource(sourceText)
    nsView.applyViewportRestoration(viewportState, token: viewportRestorationToken)
    nsView.armDirectionalEntry(token: navigationEntryToken)
  }
}

@MainActor
public final class ProjectionEditorContainer: NSView, NSTextViewDelegate {
  public let textView: NSTextView
  public let decorationAccessibilityContainer = ProjectionDecorationAccessibilityContainer()
  public var sourceDidChange: (@MainActor (String, Bool) -> Void)?
  public var viewportDidChange: (@MainActor (EditorViewportState) -> Void)?
  public var navigationHandler: (@MainActor (NoteNavigationDirection) -> Void)?
  public var pasteSettings = PasteSettings()
  public var pasteErrorHandler: (@MainActor (PastePipelineError) -> Void)?
  public var editorSettings: EditorSettings {
    didSet {
      guard editorSettings != oldValue else { return }
      if followsEditorSettingsInParser {
        replaceDefaultParser()
      } else {
        scheduleAdornmentRefresh()
      }
      applyAppearance()
    }
  }
  public var appearanceSettings: AppearanceSettings {
    didSet {
      guard appearanceSettings != oldValue else { return }
      applyAppearance()
    }
  }
  public var modeSettings: ModeSettings {
    didSet {
      guard modeSettings != oldValue else { return }
      if followsEditorSettingsInParser {
        replaceDefaultParser()
      } else {
        scheduleAdornmentRefresh()
      }
      refreshVariableAutocomplete()
      applyAppearance()
    }
  }
  public var mathSettings: MathSettings {
    didSet {
      guard mathSettings != oldValue else { return }
      if followsEditorSettingsInParser {
        replaceDefaultParser()
      } else {
        scheduleAdornmentRefresh()
      }
    }
  }
  public var currencyContext: CurrencyConversionContext {
    didSet {
      guard currencyContext != oldValue else { return }
      if followsEditorSettingsInParser {
        replaceDefaultParser()
      } else {
        scheduleAdornmentRefresh()
      }
    }
  }
  public var expandedLinkIdentities: Set<LinkIdentity> = [] {
    didSet {
      guard expandedLinkIdentities != oldValue else { return }
      scheduleAdornmentRefresh()
    }
  }
  public var temporarilyExpandsLinks = false {
    didSet {
      guard temporarilyExpandsLinks != oldValue else { return }
      scheduleAdornmentRefresh()
    }
  }
  public var linkExpansionDidToggle: (@MainActor (LinkIdentity) -> Void)?
  public var linkOpenHandler: (@MainActor (URL) -> Bool)?
  public var timerSnapshot: TimerSnapshot? {
    didSet {
      guard timerSnapshot != oldValue else { return }
      scheduleAdornmentRefresh()
    }
  }
  public var stopsTimerOnEscape = false
  public var timerCommandDidCommit: (@MainActor (TimerCommand, String) -> Void)?
  public var timerInteractionHandler: (@MainActor (EditorTimerInteraction) -> Void)?
  public var autoPasteIsActive = false
  public var autoPasteCommandDidCommit: (@MainActor (AutoPasteCommand, String) -> Void)?
  public var autoPasteStopHandler: (@MainActor () -> Void)?
  public var pasteboardDidWrite: (@MainActor () -> Void)?

  private let scrollView = NSScrollView()
  private let materialView = NSVisualEffectView()
  private let paperBackgroundView = PaperBackgroundView()
  private var parsePipeline: ProjectionParsePipeline
  private let followsEditorSettingsInParser: Bool
  private let copyPolicy = ProjectionCopyPolicy()
  private let linkDisplayPolicy = LinkDisplayPolicy()
  private let linkInteractionPolicy = LinkInteractionPolicy()
  private let linkVisibilityPolicy = LinkVisibilityPolicy()
  private let pasteboard: NSPasteboard
  private var snapshot: SourceSnapshot
  private var projection: EditorProjection
  private var adornments: [NSView] = []
  private var parseRequestTask: Task<Void, Never>?
  private var refreshScheduled = false
  private var directionalEntryToken: UInt64 = 0
  private var awaitsDirectionalEntry = false
  private var lastViewportRestorationToken: UInt64?
  private var pendingViewportRestoration: EditorViewportState?
  private var isApplyingViewportRestoration = false
  private var lastReportedViewportState: EditorViewportState?
  private weak var slashCommandTarget: EditorSlashCommandTarget?
  private weak var ocrTarget: EditorOCRTarget?
  private let variableAutocompleteEngine = VariableAutocompleteEngine()
  private var variableAutocompleteContext: VariableAutocompleteContext?
  private var variableAutocompletePanel: VariableAutocompletePanelView?
  private var isApplyingVariableAutocomplete = false
  private var suppressedVariableAutocompleteVersion: UInt64?
  private var suppressedVariableAutocompleteSelection: NSRange?
  private var pendingTimerSingleClickTask: Task<Void, Never>?
  private var shownTimerTutorialVersion: UInt64?
  public private(set) var currentAppearancePresentation = AppearancePresentation.resolve(
    settings: AppearanceSettings(),
    environment: AppearanceEnvironment(
      operatingSystemMajorVersion: 14,
      interfaceAppearance: .light,
      reducesTransparency: false,
      increasesContrast: false
    )
  )

  public init(
    initialText: String,
    editorSettings: EditorSettings = EditorSettings(),
    appearanceSettings: AppearanceSettings = AppearanceSettings(),
    modeSettings: ModeSettings = ModeSettings(),
    mathSettings: MathSettings = MathSettings(),
    currencyContext: CurrencyConversionContext = CurrencyConversionContext(),
    parser: (any ProjectionParsing)? = nil,
    pasteboard: NSPasteboard = .general
  ) {
    let textView = ProjectionTextView(usingTextLayoutManager: true)
    self.textView = textView
    self.editorSettings = editorSettings
    self.appearanceSettings = appearanceSettings
    self.modeSettings = modeSettings
    self.mathSettings = mathSettings
    self.currencyContext = currencyContext
    timerSnapshot = nil
    self.pasteboard = pasteboard
    followsEditorSettingsInParser = parser == nil
    parsePipeline = ProjectionParsePipeline(
      parser: parser
        ?? ProductionProjectionParser(
          editorSettings: editorSettings,
          modeSettings: modeSettings,
          mathSettings: mathSettings,
          currencyContext: currencyContext
        )
    )
    let snapshot = SourceSnapshot(version: 0, text: initialText)
    self.snapshot = snapshot
    projection = EditorProjection(sourceVersion: snapshot.version, decorations: [])
    super.init(frame: .zero)

    wantsLayer = true

    materialView.blendingMode = .behindWindow
    materialView.material = .underWindowBackground
    materialView.state = .active
    materialView.isHidden = true
    addSubview(materialView)
    addSubview(paperBackgroundView)

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = textView
    addSubview(scrollView)

    textView.delegate = self
    textView.string = initialText
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 24, height: 24)
    textView.font = .systemFont(
      ofSize: CGFloat(appearanceSettings.effectiveTextSize),
      weight: .regular
    )
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainer?.widthTracksTextView = true
    textView.setAccessibilityLabel("Editor projection source")
    decorationAccessibilityContainer.frame = textView.bounds
    decorationAccessibilityContainer.autoresizingMask = [.width, .height]
    textView.addSubview(decorationAccessibilityContainer)
    textView.setAccessibilityChildren([decorationAccessibilityContainer])

    textView.copyHandler = { [weak self] selection in
      guard let self else { return nil }
      return self.copyPolicy.copyText(
        from: self.snapshot,
        selection: SourceSelection(range: SourceRange(selection)),
        exportPolicy: self.exportProjectionPolicy
      )
    }
    textView.pasteboardWriteHandler = { [weak self] in
      self?.pasteboardDidWrite?()
    }
    textView.layoutHandler = { [weak self] in
      self?.scheduleAdornmentRefresh()
    }
    textView.directionalEntryHandler = { [weak self] entry in
      self?.handleDirectionalEntry(entry) ?? false
    }
    textView.cancelDirectionalEntryHandler = { [weak self] in
      self?.awaitsDirectionalEntry = false
    }
    textView.navigationHandler = { [weak self] direction in
      self?.navigationHandler?(direction)
    }
    textView.pasteHandler = { [weak self] payload, mode in
      self?.paste(payload, mode: mode)
    }
    textView.ocrPasteboardHandler = { [weak self] pasteboard, source, replacementRange in
      self?.submitOCRInput(
        from: pasteboard,
        source: source,
        replacementRange: replacementRange
      ) ?? false
    }
    textView.registerForDraggedTypes(
      Array(Set(textView.registeredDraggedTypes + EditorOCRPasteboardReader.registeredTypes))
    )
    textView.toggleCommentHandler = { [weak self] in
      self?.toggleComments() ?? false
    }
    textView.slashCommandTriggerHandler = { [weak self] in
      self?.requestSlashCommandPresentation() ?? false
    }
    textView.slashCommandKeyHandler = { [weak self] key in
      self?.slashCommandTarget?.handle(key) ?? false
    }
    textView.variableAutocompleteKeyHandler = { [weak self] key in
      self?.handleVariableAutocompleteKey(key) ?? false
    }
    textView.timerCommandCommitHandler = { [weak self] in
      self?.commitCommandBeforeCaret()
    }
    textView.timerEscapeHandler = { [weak self] in
      self?.handleEscape() ?? false
    }

    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(scrollBoundsDidChange(_:)),
      name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView
    )
    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil
    )

    applyAppearance()
    scheduleProjectionParse()
    scheduleAdornmentRefresh()
  }

  deinit {
    parseRequestTask?.cancel()
    pendingTimerSingleClickTask?.cancel()
    let parsePipeline = self.parsePipeline
    Task {
      await parsePipeline.cancel()
    }
    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  public override func layout() {
    super.layout()
    materialView.frame = bounds
    paperBackgroundView.frame = bounds
    scrollView.frame = bounds
    let contentSize = scrollView.contentSize
    textView.frame.size.width = contentSize.width
    textView.minSize = NSSize(width: contentSize.width, height: contentSize.height)
    decorationAccessibilityContainer.frame = textView.bounds
    applyPendingViewportRestoration()
    scheduleAdornmentRefresh()
    positionVariableAutocompletePanel()
  }

  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }
    applyAppearance()
    window.makeFirstResponder(textView)
    scheduleAdornmentRefresh()
  }

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyAppearance()
  }

  public func textDidChange(_ notification: Notification) {
    snapshot = SourceSnapshot(version: snapshot.version + 1, text: textView.string)
    applyAppearance()
    scheduleProjectionParse()
    sourceDidChange?(textView.string, textView.hasMarkedText())
    reportViewportChange()
    scheduleAdornmentRefresh()
    if !isApplyingVariableAutocomplete {
      refreshVariableAutocomplete()
    }
  }

  public func textDidEndEditing(_ notification: Notification) {
    sourceDidChange?(textView.string, false)
  }

  public func applyExternalSource(_ source: String) {
    guard source != textView.string, !textView.hasMarkedText() else { return }
    let selectedRange = textView.selectedRange()
    textView.string = source
    snapshot = SourceSnapshot(version: snapshot.version + 1, text: source)
    projection = EditorProjection(sourceVersion: snapshot.version, decorations: [])
    scheduleProjectionParse()
    textView.setSelectedRange(
      snapshot.clamped(SourceSelection(range: SourceRange(selectedRange))).range.nsRange)
    textView.undoManager?.removeAllActions()
    applyAppearance()
    scheduleAdornmentRefresh()
    refreshVariableAutocomplete()
  }

  public func applyViewportRestoration(_ state: EditorViewportState, token: UInt64) {
    guard token != lastViewportRestorationToken else { return }
    lastViewportRestorationToken = token
    pendingViewportRestoration = state
    applyPendingViewportRestoration()
  }

  public func currentViewportState() -> EditorViewportState {
    EditorViewportState(
      selection: snapshot.clamped(
        SourceSelection(range: SourceRange(textView.selectedRange()))
      ),
      verticalScrollOffset: max(
        0,
        Int(scrollView.contentView.bounds.origin.y.rounded(.towardZero))
      )
    )
  }

  public func waitForPendingProjection() async {
    await parseRequestTask?.value
  }

  public func projectionPipelineDiagnostics() async -> ProjectionPipelineDiagnostics {
    await parsePipeline.diagnostics()
  }

  public var currentProjection: EditorProjection {
    projection
  }

  public var currentVariableAutocompleteContext: VariableAutocompleteContext? {
    variableAutocompleteContext
  }

  var slashCommandSource: String {
    snapshot.text
  }

  func attachSlashCommandTarget(_ target: EditorSlashCommandTarget) {
    slashCommandTarget = target
  }

  func detachSlashCommandTarget(_ target: EditorSlashCommandTarget) {
    guard slashCommandTarget === target else { return }
    slashCommandTarget = nil
    (textView as? ProjectionTextView)?.slashCommandsAreActive = false
  }

  func setSlashCommandActive(_ isActive: Bool) {
    (textView as? ProjectionTextView)?.slashCommandsAreActive = isActive
  }

  @discardableResult
  public func performSlashCommand(_ plan: SlashCommandEditPlan) -> Bool {
    guard !textView.hasMarkedText(),
      snapshot.text == plan.expectedSource,
      plan.replacementRange.location >= 0,
      NSMaxRange(plan.replacementRange) <= snapshot.utf16Count
    else { return false }
    textView.insertText(plan.replacement, replacementRange: plan.replacementRange)
    textView.setSelectedRange(plan.selectionAfterEdit)
    textView.scrollRangeToVisible(plan.selectionAfterEdit)
    reportViewportChange()
    return true
  }

  public func focusEditor() {
    window?.makeFirstResponder(textView)
  }

  @discardableResult
  public func performVariableAutocompleteSelection(at index: Int) -> Bool {
    guard !textView.hasMarkedText(),
      let context = variableAutocompleteContext,
      let plan = variableAutocompleteEngine.editPlan(
        in: snapshot.text,
        context: context,
        selecting: index
      ),
      plan.expectedSource == snapshot.text,
      plan.replacementRange.location >= 0,
      NSMaxRange(plan.replacementRange) <= snapshot.utf16Count
    else { return false }

    isApplyingVariableAutocomplete = true
    let applied = performUndoableVariableAutocompleteReplacement(
      range: plan.replacementRange,
      replacement: plan.replacement,
      selectionAfterEdit: plan.selectionAfterEdit
    )
    isApplyingVariableAutocomplete = false
    guard applied else { return false }
    clearVariableAutocomplete()
    return true
  }

  public func refreshVariableAutocomplete() {
    guard !isApplyingVariableAutocomplete, !textView.hasMarkedText() else {
      clearVariableAutocomplete()
      return
    }
    let selection = textView.selectedRange()
    if suppressedVariableAutocompleteVersion == snapshot.version,
      suppressedVariableAutocompleteSelection == selection
    {
      clearVariableAutocomplete()
      return
    }
    suppressedVariableAutocompleteVersion = nil
    suppressedVariableAutocompleteSelection = nil
    guard
      let context = variableAutocompleteEngine.context(
        in: snapshot.text,
        selection: selection,
        modeSettings: modeSettings
      )
    else {
      clearVariableAutocomplete()
      return
    }
    variableAutocompleteContext = context
    variableAutocompletePanel?.removeFromSuperview()
    let panel = VariableAutocompletePanelView(context: context) { [weak self] index in
      _ = self?.performVariableAutocompleteSelection(at: index)
    }
    variableAutocompletePanel = panel
    addSubview(panel, positioned: .above, relativeTo: scrollView)
    positionVariableAutocompletePanel()
  }

  public func contextualCopyText(for selection: NSRange) -> String {
    copyPolicy.copyText(
      from: snapshot,
      selection: SourceSelection(range: SourceRange(selection)),
      exportPolicy: exportProjectionPolicy
    )
  }

  @discardableResult
  public func toggleComments() -> Bool {
    guard !textView.hasMarkedText(),
      let result = LineCommentToggler().toggle(
        in: snapshot,
        selection: SourceSelection(range: SourceRange(textView.selectedRange()))
      )
    else { return false }
    textView.insertText(result.edit.replacement, replacementRange: result.edit.range.nsRange)
    textView.setSelectedRange(result.selection.range.nsRange)
    reportViewportChange()
    return true
  }

  public func performPaste(_ payload: PasteboardPayload, mode: PasteMode) throws {
    let selection = SourceSelection(range: SourceRange(textView.selectedRange()))
    let isCodeContext = EditorCodeContextPolicy().isCodeContext(
      in: snapshot,
      selection: selection,
      defaultLanguage: editorSettings.defaultCodeLanguage,
      modeSettings: modeSettings
    )
    let replacement = try PastePipeline().sourceText(
      from: payload,
      mode: mode,
      settings: pasteSettings,
      context: isCodeContext ? .code : .plain
    )
    textView.insertText(replacement, replacementRange: textView.selectedRange())
  }

  @discardableResult
  public func submitOCRInput(
    from pasteboard: NSPasteboard,
    source: EditorOCRInputSource,
    replacementRange: NSRange? = nil
  ) -> Bool {
    guard let ocrTarget else { return false }
    let reader = EditorOCRPasteboardReader()
    guard reader.hasImageCandidate(in: pasteboard) else { return false }
    do {
      guard let image = try reader.imageInput(from: pasteboard) else { return false }
      let range = replacementRange ?? textView.selectedRange()
      guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= snapshot.utf16Count else {
        ocrTarget.failCapture(with: .unreadableImage)
        return true
      }
      ocrTarget.submit(
        EditorOCRRequest(
          image: image,
          source: source,
          anchor: EditorOCRInsertionAnchor(
            sourceVersion: snapshot.version,
            replacementRange: SourceRange(range)
          )
        )
      )
      return true
    } catch let error as EditorOCRCaptureError {
      ocrTarget.failCapture(with: error)
      return true
    } catch {
      ocrTarget.failCapture(with: .unreadableImage)
      return true
    }
  }

  public func performOCRInsertion(
    _ recognizedText: String,
    at anchor: EditorOCRInsertionAnchor
  ) -> EditorOCRInsertionOutcome {
    guard snapshot.version == anchor.sourceVersion else { return .sourceChanged }
    guard
      performUndoableOCRInsertion(
        recognizedText,
        replacementRange: anchor.replacementRange.nsRange
      )
    else {
      return .editorUnavailable
    }
    return .inserted
  }

  public func performOCRInsertionAtCurrentSelection(_ recognizedText: String) -> Bool {
    performUndoableOCRInsertion(recognizedText, replacementRange: textView.selectedRange())
  }

  func attachOCRTarget(_ target: EditorOCRTarget) {
    ocrTarget = target
  }

  func detachOCRTarget(_ target: EditorOCRTarget) {
    guard ocrTarget === target else { return }
    ocrTarget = nil
  }

  private func performUndoableOCRInsertion(
    _ recognizedText: String,
    replacementRange: NSRange
  ) -> Bool {
    guard !recognizedText.isEmpty,
      !textView.hasMarkedText(),
      replacementRange.location >= 0,
      replacementRange.length >= 0,
      NSMaxRange(replacementRange) <= snapshot.utf16Count
    else { return false }
    textView.breakUndoCoalescing()
    textView.insertText(recognizedText, replacementRange: replacementRange)
    textView.breakUndoCoalescing()
    return true
  }

  public func armDirectionalEntry(token: UInt64) {
    guard token != 0, token != directionalEntryToken else { return }
    directionalEntryToken = token
    awaitsDirectionalEntry = true
  }

  private func handleDirectionalEntry(_ entry: EditorDirectionalEntry) -> Bool {
    guard awaitsDirectionalEntry else { return false }
    awaitsDirectionalEntry = false
    let location = entry == .start ? 0 : snapshot.utf16Count
    let range = NSRange(location: location, length: 0)
    textView.setSelectedRange(range)
    textView.scrollRangeToVisible(range)
    reportViewportChange()
    return true
  }

  private func requestSlashCommandPresentation() -> Bool {
    guard
      SlashCommandEngine().isEligible(
        in: snapshot.text,
        selection: textView.selectedRange(),
        settings: modeSettings
      )
    else { return false }
    return slashCommandTarget?.requestPresentation() ?? false
  }

  private func paste(_ payload: PasteboardPayload, mode: PasteMode) {
    do {
      try performPaste(payload, mode: mode)
    } catch let error as PastePipelineError {
      if let pasteErrorHandler {
        pasteErrorHandler(error)
      } else {
        presentPasteError(error)
      }
    } catch {
      presentPasteError(.unreadableTextRepresentation)
    }
  }

  private func presentPasteError(_ error: PastePipelineError) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Paste Failed"
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "OK")
    if let window {
      alert.beginSheetModal(for: window)
    } else {
      NSSound.beep()
    }
  }

  public func textViewDidChangeSelection(_ notification: Notification) {
    reportViewportChange()
    scheduleAdornmentRefresh()
    if !isApplyingVariableAutocomplete {
      refreshVariableAutocomplete()
    }
  }

  @objc private func scrollBoundsDidChange(_ notification: Notification) {
    paperBackgroundView.verticalScrollOffset = scrollView.contentView.bounds.origin.y
    reportViewportChange()
    positionVariableAutocompletePanel()
  }

  @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
    applyAppearance()
  }

  private func applyAppearance() {
    let interfaceAppearance: InterfaceAppearance =
      effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? .dark : .light
    let environment = AppearanceEnvironment(
      operatingSystemMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
      interfaceAppearance: interfaceAppearance,
      reducesTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
      increasesContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    )
    let presentation = AppearancePresentation.resolve(
      settings: appearanceSettings,
      environment: environment
    )
    currentAppearancePresentation = presentation

    materialView.isHidden = !presentation.usesTranslucentMaterial
    paperBackgroundView.settings = appearanceSettings
    paperBackgroundView.presentation = presentation
    paperBackgroundView.verticalScrollOffset = scrollView.contentView.bounds.origin.y

    let font = NSFont.systemFont(
      ofSize: CGFloat(appearanceSettings.effectiveTextSize),
      weight: .regular
    )
    let isListMode =
      ModeHeaderParser(settings: modeSettings).parse(in: snapshot.text)?.modeID == .list
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing =
      isListMode ? CGFloat(appearanceSettings.effectiveListSpacing.points) : 0
    switch editorSettings.layoutDirection {
    case .natural:
      paragraph.baseWritingDirection = .natural
      paragraph.alignment = .natural
    case .leftToRight:
      paragraph.baseWritingDirection = .leftToRight
      paragraph.alignment = .left
    case .rightToLeft:
      paragraph.baseWritingDirection = .rightToLeft
      paragraph.alignment = .right
    }

    textView.font = font
    textView.textColor = presentation.theme.primaryText.nsColor
    textView.insertionPointColor = presentation.theme.accent.nsColor
    textView.baseWritingDirection = paragraph.baseWritingDirection
    textView.alignment = paragraph.alignment
    textView.defaultParagraphStyle = paragraph
    textView.typingAttributes = [
      .font: font,
      .foregroundColor: presentation.theme.primaryText.nsColor,
      .paragraphStyle: paragraph,
    ]
    textView.selectedTextAttributes = [
      .backgroundColor: presentation.theme.selection.nsColor,
      .foregroundColor: presentation.theme.primaryText.nsColor,
    ]

    if let layoutManager = textView.layoutManager, snapshot.utf16Count > 0 {
      let fullRange = NSRange(location: 0, length: snapshot.utf16Count)
      layoutManager.removeTemporaryAttribute(.paragraphStyle, forCharacterRange: fullRange)
      layoutManager.addTemporaryAttribute(
        .paragraphStyle,
        value: paragraph,
        forCharacterRange: fullRange
      )
    }
    paperBackgroundView.lineHeight = textView.layoutManager?.defaultLineHeight(for: font) ?? 22

    layer?.borderWidth = presentation.drawsContrastBorder ? 1 : 0
    layer?.borderColor = presentation.theme.primaryText.nsColor.cgColor
    if let window {
      window.isOpaque = !presentation.usesTranslucentMaterial
      window.backgroundColor =
        presentation.usesTranslucentMaterial ? .clear : presentation.theme.canvas.nsColor
    }
    scheduleAdornmentRefresh()
  }

  private func handleVariableAutocompleteKey(_ key: EditorVariableAutocompleteKey) -> Bool {
    guard variableAutocompleteContext != nil else { return false }
    switch key {
    case .acceptFirst:
      return performVariableAutocompleteSelection(at: 0)
    case .acceptNumber(let number):
      return performVariableAutocompleteSelection(at: number - 1)
    case .dismiss:
      suppressedVariableAutocompleteVersion = snapshot.version
      suppressedVariableAutocompleteSelection = textView.selectedRange()
      clearVariableAutocomplete()
      return true
    }
  }

  private func clearVariableAutocomplete() {
    variableAutocompleteContext = nil
    variableAutocompletePanel?.removeFromSuperview()
    variableAutocompletePanel = nil
  }

  private func positionVariableAutocompletePanel() {
    guard let panel = variableAutocompletePanel, let window else { return }
    var actualRange = NSRange(location: NSNotFound, length: 0)
    let screenRect = textView.firstRect(
      forCharacterRange: textView.selectedRange(),
      actualRange: &actualRange
    )
    guard !screenRect.isEmpty else { return }
    let windowRect = window.convertFromScreen(screenRect)
    let caretRect = convert(windowRect, from: nil)
    let margin: CGFloat = 8
    let proposedBelow = caretRect.minY - panel.frame.height - 4
    let y =
      proposedBelow >= margin
      ? proposedBelow
      : min(bounds.height - panel.frame.height - margin, caretRect.maxY + 4)
    let x = min(
      max(margin, caretRect.minX),
      max(margin, bounds.width - panel.frame.width - margin)
    )
    panel.frame.origin = NSPoint(x: x, y: max(margin, y))
  }

  private func performUndoableVariableAutocompleteReplacement(
    range: NSRange,
    replacement: String,
    selectionAfterEdit: NSRange
  ) -> Bool {
    let sourceLength = textView.string.utf16.count
    guard range.location >= 0, NSMaxRange(range) <= sourceLength,
      selectionAfterEdit.location >= 0,
      NSMaxRange(selectionAfterEdit) <= sourceLength - range.length + replacement.utf16.count
    else { return false }

    let replacedSource = (textView.string as NSString).substring(with: range)
    let selectionBeforeEdit = textView.selectedRange()
    let undoManager = textView.undoManager
    let isReplayingUndo = undoManager?.isUndoing == true || undoManager?.isRedoing == true
    textView.breakUndoCoalescing()
    undoManager?.disableUndoRegistration()
    textView.insertText(replacement, replacementRange: range)
    undoManager?.enableUndoRegistration()
    textView.setSelectedRange(selectionAfterEdit)
    textView.scrollRangeToVisible(selectionAfterEdit)

    let inverseRange = NSRange(location: range.location, length: replacement.utf16.count)
    if !isReplayingUndo { undoManager?.beginUndoGrouping() }
    undoManager?.registerUndo(withTarget: self) { target in
      _ = target.performUndoableVariableAutocompleteReplacement(
        range: inverseRange,
        replacement: replacedSource,
        selectionAfterEdit: selectionBeforeEdit
      )
    }
    undoManager?.setActionName("Complete Variable")
    if !isReplayingUndo { undoManager?.endUndoGrouping() }
    textView.breakUndoCoalescing()
    reportViewportChange()
    return true
  }

  private func scheduleProjectionParse() {
    parseRequestTask?.cancel()
    let requestedSnapshot = snapshot
    let parsePipeline = self.parsePipeline
    parseRequestTask = Task { [weak self] in
      do {
        let parsedProjection = try await parsePipeline.projection(for: requestedSnapshot)
        try Task.checkCancellation()
        guard let self,
          self.snapshot.version == requestedSnapshot.version,
          ProjectionGate().accepts(parsedProjection, for: self.snapshot)
        else { return }
        self.projection = parsedProjection
        self.scheduleAdornmentRefresh()
      } catch is CancellationError {
        return
      } catch {
        return
      }
    }
  }

  private func replaceDefaultParser() {
    parseRequestTask?.cancel()
    let previousPipeline = parsePipeline
    parsePipeline = ProjectionParsePipeline(
      parser: ProductionProjectionParser(
        editorSettings: editorSettings,
        modeSettings: modeSettings,
        mathSettings: mathSettings,
        currencyContext: currencyContext
      )
    )
    projection = EditorProjection(sourceVersion: snapshot.version, decorations: [])
    Task {
      await previousPipeline.cancel()
    }
    scheduleProjectionParse()
    scheduleAdornmentRefresh()
  }

  private var exportProjectionPolicy: ExportProjectionPolicy {
    ExportProjectionPolicy(
      omitsChecklistTriggers: editorSettings.omitsChecklistTriggersOnExport,
      checklistTrigger: modeSettings.checklistTrigger,
      modeSettings: modeSettings
    )
  }

  private func applyPendingViewportRestoration() {
    guard let state = pendingViewportRestoration else { return }
    isApplyingViewportRestoration = true
    let selection = snapshot.clamped(state.selection)
    textView.setSelectedRange(selection.range.nsRange)
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    let maximumOffset = max(0, textView.bounds.height - scrollView.contentSize.height)
    let requestedOffset = min(CGFloat(state.verticalScrollOffset), maximumOffset)
    scrollView.contentView.scroll(
      to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: requestedOffset)
    )
    scrollView.reflectScrolledClipView(scrollView.contentView)
    pendingViewportRestoration = nil
    lastReportedViewportState = currentViewportState()
    isApplyingViewportRestoration = false
    scheduleAdornmentRefresh()
  }

  private func reportViewportChange() {
    guard !isApplyingViewportRestoration else { return }
    let state = currentViewportState()
    guard state != lastReportedViewportState else { return }
    lastReportedViewportState = state
    viewportDidChange?(state)
  }

  private func scheduleAdornmentRefresh() {
    guard !refreshScheduled else { return }
    refreshScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.refreshScheduled = false
      self.refreshAdornments()
    }
  }

  private func refreshAdornments() {
    refreshPresentationStyles()
    for adornment in adornments {
      adornment.removeFromSuperview()
    }
    adornments.removeAll(keepingCapacity: true)
    decorationAccessibilityContainer.setAccessibilityChildren([])

    guard ProjectionGate().accepts(projection, for: snapshot) else { return }
    let selectedRange = textView.selectedRange()
    for decoration in projection.decorations {
      switch decoration {
      case .style:
        continue
      case .checkbox(let range, let markerRange, let isChecked):
        addCheckbox(range: range, markerRange: markerRange, isChecked: isChecked)
      case .link(let range, let presentation):
        guard editorSettings.hyperlinkFeaturesEnabled else { continue }
        guard
          linkVisibilityPolicy.shouldPresent(
            sourceRange: range.nsRange,
            selection: selectedRange
          )
        else { continue }
        addLink(range: range, presentation: presentation)
      case .result(let anchor, let presentation):
        addResult(anchor: anchor, presentation: presentation)
      case .timer(let anchor, let presentation):
        if presentation.showsTutorial {
          addTimerTutorial(anchor: anchor, presentation: presentation)
        }
      }
    }
    if let timerSnapshot,
      let latestTimerDecoration = projection.decorations.reversed().first(where: {
        if case .timer = $0 { return true }
        return false
      }),
      case .timer(let anchor, _) = latestTimerDecoration
    {
      addTimer(anchor: anchor, snapshot: timerSnapshot)
    }
    for diagnostic in projection.diagnostics {
      addDiagnostic(diagnostic)
    }
    decorationAccessibilityContainer.setAccessibilityChildren(adornments)
  }

  public func hasPresentationAttributes(at utf16Offset: Int) -> Bool {
    guard utf16Offset >= 0, utf16Offset < snapshot.utf16Count,
      let layoutManager = textView.layoutManager
    else { return false }
    let attributes = layoutManager.temporaryAttributes(
      atCharacterIndex: utf16Offset,
      effectiveRange: nil
    )
    return Self.presentationAttributeKeys.contains { attributes[$0] != nil }
  }

  private func refreshPresentationStyles() {
    guard let layoutManager = textView.layoutManager else { return }
    let fullRange = NSRange(location: 0, length: snapshot.utf16Count)
    for key in Self.presentationAttributeKeys {
      layoutManager.removeTemporaryAttribute(key, forCharacterRange: fullRange)
    }
    guard ProjectionGate().accepts(projection, for: snapshot) else { return }
    for decoration in projection.decorations {
      guard case .style(let range, let style) = decoration,
        snapshot.contains(range),
        range.length > 0
      else { continue }
      layoutManager.addTemporaryAttributes(
        presentationAttributes(for: style),
        forCharacterRange: range.nsRange
      )
    }
  }

  private func presentationAttributes(for style: TextStyle) -> [NSAttributedString.Key: Any] {
    let baseSize = textView.font?.pointSize ?? 18
    switch style {
    case .heading(let level):
      let headingScale: [Int: CGFloat] = [1: 1.44, 2: 1.22, 3: 1.11]
      let size = baseSize * (headingScale[level] ?? 1)
      return [.font: NSFont.systemFont(ofSize: size, weight: .semibold)]
    case .bold:
      return [.font: NSFont.systemFont(ofSize: baseSize, weight: .semibold)]
    case .italic:
      return [
        .font: NSFontManager.shared.convert(
          NSFont.systemFont(ofSize: baseSize),
          toHaveTrait: .italicFontMask
        )
      ]
    case .strikethrough:
      return [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
    case .underline:
      return [.underlineStyle: NSUnderlineStyle.single.rawValue]
    case .inlineCode:
      return [
        .font: NSFont.monospacedSystemFont(ofSize: max(12, baseSize - 1), weight: .regular),
        .backgroundColor: NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(
          0.35),
      ]
    case .codeFence:
      return [
        .font: NSFont.monospacedSystemFont(ofSize: max(12, baseSize - 2), weight: .regular),
        .foregroundColor: NSColor.tertiaryLabelColor,
      ]
    case .codeBlock:
      return [
        .font: NSFont.monospacedSystemFont(ofSize: max(12, baseSize - 1), weight: .regular),
        .backgroundColor: NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(
          0.2),
      ]
    case .comment:
      return [
        .font: NSFontManager.shared.convert(
          NSFont.systemFont(ofSize: baseSize),
          toHaveTrait: .italicFontMask
        ),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
    case .modeHeader:
      return [
        .font: NSFont.monospacedSystemFont(ofSize: max(12, baseSize - 2), weight: .semibold),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
    case .syntax(let kind):
      return [.foregroundColor: syntaxColor(for: kind)]
    }
  }

  private func syntaxColor(for kind: CodeSyntaxTokenKind) -> NSColor {
    switch (editorSettings.codeHighlightTheme, kind) {
    case (.adaptive, .keyword):
      .systemPurple
    case (.adaptive, .string):
      .systemRed
    case (.adaptive, .comment):
      .secondaryLabelColor
    case (.adaptive, .number):
      .systemBlue
    case (.classic, .keyword):
      .systemIndigo
    case (.classic, .string):
      .systemGreen
    case (.classic, .comment):
      .systemGray
    case (.classic, .number):
      .systemOrange
    case (.midnight, .keyword):
      .systemTeal
    case (.midnight, .string):
      .systemPink
    case (.midnight, .comment):
      .systemGray
    case (.midnight, .number):
      .systemPurple
    }
  }

  private static let presentationAttributeKeys: [NSAttributedString.Key] = [
    .font,
    .foregroundColor,
    .backgroundColor,
    .underlineStyle,
    .strikethroughStyle,
  ]

  private func addCheckbox(
    range: SourceRange,
    markerRange: SourceRange?,
    isChecked: Bool
  ) {
    guard range.length > 0,
      let sourceRect = editorRect(
        for: NSRange(location: range.location.utf16Offset, length: 1)
      )
    else { return }
    let button = ProjectionAdornmentButton()
    button.frame = NSRect(
      x: checkboxGutterX(for: range, sourceRect: sourceRect),
      y: sourceRect.midY - 9,
      width: 18,
      height: 18
    )
    button.image = NSImage(
      systemSymbolName: isChecked ? "checkmark.square.fill" : "square",
      accessibilityDescription: isChecked ? "Checked" : "Unchecked"
    )
    button.imagePosition = .imageOnly
    button.contentTintColor = isChecked ? .controlAccentColor : .secondaryLabelColor
    button.setButtonType(.toggle)
    button.state = isChecked ? .on : .off
    button.sourceRange = range
    button.markerRange = markerRange
    button.kind = .checkbox
    button.target = self
    button.action = #selector(activateAdornment(_:))
    button.setAccessibilityLabel(isChecked ? "Uncheck item" : "Check item")
    button.setAccessibilityValue(isChecked ? "Checked" : "Unchecked")
    install(button)
  }

  private func checkboxGutterX(for range: SourceRange, sourceRect: NSRect) -> CGFloat {
    let usesRightGutter: Bool
    switch editorSettings.layoutDirection {
    case .leftToRight:
      usesRightGutter = false
    case .rightToLeft:
      usesRightGutter = true
    case .natural:
      let finalOffset = range.location.utf16Offset + range.length - 1
      if range.length > 1,
        let finalRect = editorRect(for: NSRange(location: finalOffset, length: 1)),
        abs(finalRect.midX - sourceRect.midX) > 1
      {
        usesRightGutter = sourceRect.midX > finalRect.midX
      } else {
        usesRightGutter = false
      }
    }

    return usesRightGutter ? max(2, textView.bounds.maxX - 20) : max(2, sourceRect.minX - 22)
  }

  private func addLink(range: SourceRange, presentation: LinkPresentation) {
    let effectiveExpandedIdentities =
      temporarilyExpandsLinks
      ? expandedLinkIdentities.union([presentation.identity])
      : expandedLinkIdentities
    guard let sourceRect = editorRect(for: range.nsRange),
      let displayText = linkDisplayPolicy.displayText(
        for: presentation,
        settings: editorSettings,
        expandedIdentities: effectiveExpandedIdentities
      )
    else { return }
    let button = ProjectionAdornmentButton()
    button.frame = sourceRect.insetBy(dx: -2, dy: 0)
    button.title = displayText
    button.alignment = .left
    button.font = textView.font
    button.contentTintColor = .linkColor
    button.copiedText = presentation.originalURL
    button.sourceRange = range
    button.linkPresentation = presentation
    button.kind = .link
    button.target = self
    button.action = #selector(activateAdornment(_:))
    button.toolTip = presentation.originalURL
    button.setAccessibilityLabel("Link \(presentation.originalURL)")
    let menu = NSMenu()
    let copyItem = NSMenuItem(
      title: "Copy Link",
      action: #selector(copyLink(_:)),
      keyEquivalent: ""
    )
    copyItem.target = self
    copyItem.representedObject = presentation.originalURL
    menu.addItem(copyItem)
    button.menu = menu
    install(button)
  }

  private func addResult(anchor: SourceOffset, presentation: CalculationPresentation) {
    let anchorOffset = min(anchor.utf16Offset, snapshot.utf16Count)
    guard anchorOffset > 0 else { return }
    let precedingSourceRange = NSRange(location: anchorOffset - 1, length: 1)
    guard let anchorRect = editorRect(for: precedingSourceRange) else { return }
    let button = ProjectionAdornmentButton()
    button.title = presentation.displayText
    button.font = .systemFont(ofSize: 15, weight: .semibold)
    button.contentTintColor = .controlAccentColor
    button.sizeToFit()
    button.frame.origin = NSPoint(x: anchorRect.maxX + 8, y: anchorRect.minY)
    button.copiedText = presentation.copiedText
    button.kind = .copy
    button.target = self
    button.action = #selector(activateAdornment(_:))
    if let expressionText = presentation.expressionText {
      button.setAccessibilityLabel(
        "Calculation \(expressionText). Result \(presentation.displayText). Copy result"
      )
    } else {
      button.setAccessibilityLabel("Calculation result \(presentation.displayText). Copy result")
    }
    install(button)
  }

  private func addTimer(anchor: SourceOffset, snapshot: TimerSnapshot) {
    let anchorOffset = min(anchor.utf16Offset, self.snapshot.utf16Count)
    guard anchorOffset > 0,
      let anchorRect = editorRect(
        for: NSRange(location: anchorOffset - 1, length: 1)
      )
    else { return }
    let button = ProjectionAdornmentButton()
    button.title = snapshot.displayText
    button.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    let isControllable = snapshot.isRunning || snapshot.isPaused
    button.contentTintColor = isControllable ? .controlAccentColor : .secondaryLabelColor
    button.sizeToFit()
    button.frame.size.width = max(82, button.frame.width + 12)
    button.frame.size.height = max(20, button.frame.height)
    button.frame.origin = NSPoint(x: anchorRect.maxX + 8, y: anchorRect.midY - 10)
    button.kind = .timer
    button.target = self
    button.action = #selector(activateAdornment(_:))
    button.isEnabled = isControllable
    button.setAccessibilityLabel(snapshot.accessibilityLabel)
    button.setAccessibilityIdentifier("Timer control")
    if isControllable {
      button.toolTip = snapshot.isRunning ? "Pause timer" : "Resume timer"
      button.setAccessibilityHelp("Click to pause or resume. Double-click to stop.")
      button.setAccessibilityCustomActions([
        NSAccessibilityCustomAction(
          name: "Pause or resume timer",
          target: self,
          selector: #selector(performTimerPauseOrResumeAccessibilityAction)
        ),
        NSAccessibilityCustomAction(
          name: "Stop timer",
          target: self,
          selector: #selector(performTimerStopAccessibilityAction)
        ),
      ])
    } else {
      button.toolTip = snapshot.timer.state == .completed ? "Timer completed" : "Timer stopped"
      button.setAccessibilityHelp("Use the timer restart command to run this timer again.")
      button.setAccessibilityCustomActions([])
    }
    install(button)
  }

  private func addTimerTutorial(anchor: SourceOffset, presentation: TimerPresentation) {
    let anchorOffset = min(anchor.utf16Offset, snapshot.utf16Count)
    guard anchorOffset > 0,
      let anchorRect = editorRect(for: NSRange(location: anchorOffset - 1, length: 1))
    else { return }
    let button = ProjectionAdornmentButton()
    button.frame = NSRect(x: anchorRect.maxX + 8, y: anchorRect.midY - 9, width: 18, height: 18)
    button.image = NSImage(
      systemSymbolName: "questionmark.circle",
      accessibilityDescription: "Timer commands"
    )
    button.imagePosition = .imageOnly
    button.contentTintColor = .secondaryLabelColor
    button.kind = .timerTutorial
    button.timerAlias = presentation.matchedAlias
    button.target = self
    button.action = #selector(activateAdornment(_:))
    button.toolTip = "Timer commands"
    button.setAccessibilityLabel("Timer command tutorial")
    button.setAccessibilityIdentifier("Timer command tutorial")
    install(button)
    guard shownTimerTutorialVersion != snapshot.version else { return }
    shownTimerTutorialVersion = snapshot.version
    DispatchQueue.main.async { [weak self, weak button] in
      guard let self, let button, button.window != nil else { return }
      self.showTimerTutorial(button)
    }
  }

  private func addDiagnostic(_ diagnostic: ProjectionDiagnostic) {
    let range = diagnostic.sourceRange?.nsRange ?? NSRange(location: 0, length: 0)
    let boundedLocation = min(range.location, max(0, snapshot.utf16Count - 1))
    let boundedLength = snapshot.utf16Count > 0 ? max(1, min(range.length, 1)) : 0
    guard boundedLength > 0,
      let sourceRect = editorRect(
        for: NSRange(location: boundedLocation, length: boundedLength)
      )
    else { return }

    let button = ProjectionAdornmentButton()
    button.frame = NSRect(x: sourceRect.maxX + 4, y: sourceRect.minY, width: 18, height: 18)
    button.image = NSImage(
      systemSymbolName: "exclamationmark.triangle.fill",
      accessibilityDescription: diagnostic.message
    )
    button.imagePosition = .imageOnly
    button.contentTintColor = diagnostic.severity == .error ? .systemRed : .systemOrange
    button.toolTip = diagnostic.message
    button.setAccessibilityLabel(
      "\(diagnostic.severity.rawValue.capitalized): \(diagnostic.message)")
    button.setAccessibilityHelp(diagnostic.code)
    install(button)
  }

  private func editorRect(for range: NSRange) -> NSRect? {
    var actualRange = NSRange(location: NSNotFound, length: 0)
    let screenRect = textView.firstRect(forCharacterRange: range, actualRange: &actualRange)
    guard screenRect.isFinite, screenRect.height > 0 else { return nil }
    guard let window else { return nil }
    let windowRect = window.convertFromScreen(screenRect)
    let localRect = textView.convert(windowRect, from: nil)
    guard localRect.intersects(textView.visibleRect.insetBy(dx: -80, dy: -80)) else { return nil }
    return localRect
  }

  private func install(_ view: ProjectionAdornmentButton) {
    view.isBordered = false
    view.focusRingType = .default
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(view.kind == .checkbox ? .checkBox : .button)
    view.wantsLayer = true
    view.layer?.backgroundColor = currentAppearancePresentation.theme.canvas.nsColor.cgColor
    view.layer?.cornerRadius = 3
    view.frame = decorationAccessibilityContainer.convert(view.frame, from: textView)
    decorationAccessibilityContainer.addSubview(view)
    adornments.append(view)
  }

  @objc private func activateAdornment(_ sender: ProjectionAdornmentButton) {
    switch sender.kind {
    case .checkbox:
      guard let range = sender.sourceRange else { return }
      _ = performListItemToggle(itemRange: range)
    case .copy:
      guard let copiedText = sender.copiedText else { return }
      let selection = textView.selectedRange()
      writeToPasteboard(
        selection.length > 0 ? contextualCopyText(for: selection) : copiedText
      )
    case .link:
      guard let presentation = sender.linkPresentation else { return }
      let eventModifiers = NSApp.currentEvent?.modifierFlags ?? []
      var modifiers: LinkInteractionModifiers = []
      if eventModifiers.contains(.command) {
        modifiers.insert(.command)
      }
      if eventModifiers.contains(.shift) {
        modifiers.insert(.shift)
      }
      _ = performLinkInteraction(presentation, modifiers: modifiers)
    case .timer:
      handleTimerClick()
    case .timerTutorial:
      showTimerTutorial(sender)
    case .none:
      break
    }
  }

  public func performTimerInteraction(_ interaction: EditorTimerInteraction) {
    timerInteractionHandler?(interaction)
  }

  @objc func performTimerPauseOrResumeAccessibilityAction() -> Bool {
    performTimerInteraction(.singleClick)
    return true
  }

  @objc func performTimerStopAccessibilityAction() -> Bool {
    performTimerInteraction(.stop)
    return true
  }

  private func handleTimerClick() {
    let clickCount = NSApp.currentEvent?.clickCount ?? 1
    if clickCount >= 2 {
      pendingTimerSingleClickTask?.cancel()
      pendingTimerSingleClickTask = nil
      performTimerInteraction(.stop)
      return
    }
    pendingTimerSingleClickTask?.cancel()
    pendingTimerSingleClickTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
      guard !Task.isCancelled, let self else { return }
      self.pendingTimerSingleClickTask = nil
      self.performTimerInteraction(.singleClick)
    }
  }

  private func handleTimerEscape() -> Bool {
    guard stopsTimerOnEscape else { return false }
    pendingTimerSingleClickTask?.cancel()
    pendingTimerSingleClickTask = nil
    performTimerInteraction(.stop)
    return true
  }

  private func handleEscape() -> Bool {
    if autoPasteIsActive {
      autoPasteStopHandler?()
      return true
    }
    return handleTimerEscape()
  }

  private func commitCommandBeforeCaret() {
    let source = snapshot.text as NSString
    let caret = textView.selectedRange().location
    guard caret >= 2, source.length > 0 else { return }
    let probe = min(source.length - 1, caret - 2)
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    source.getLineStart(
      &lineStart,
      end: &lineEnd,
      contentsEnd: &contentsEnd,
      for: NSRange(location: probe, length: 0)
    )
    let range = NSRange(location: lineStart, length: contentsEnd - lineStart)
    let line = source.substring(with: range)
    if let command = AutoPasteCommandParser().parse(line) {
      autoPasteCommandDidCommit?(command, snapshot.text)
      return
    }
    guard
      case .command(let match) = TimerCommandParser(settings: modeSettings).evaluateLine(
        line,
        sourceRange: range,
        isFirstSourceLine: lineStart == 0
      )
    else { return }
    timerCommandDidCommit?(match.command, snapshot.text)
  }

  private func showTimerTutorial(_ sender: ProjectionAdornmentButton) {
    sender.timerTutorialPopover?.close()
    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 360, height: 272)
    popover.contentViewController = TimerTutorialViewController(alias: sender.timerAlias ?? "timer")
    sender.timerTutorialPopover = popover
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
  }

  @discardableResult
  public func performListItemToggle(itemRange: SourceRange) -> Bool {
    guard !textView.hasMarkedText(),
      let plan = ListModeTogglePlanner().plan(
        in: snapshot.text,
        itemRange: itemRange.nsRange,
        selection: textView.selectedRange(),
        settings: modeSettings
      ),
      plan.expectedSource == snapshot.text
    else { return false }
    return performUndoableListReplacement(
      range: plan.replacementRange,
      replacement: plan.replacement,
      selectionAfterEdit: plan.selectionAfterEdit
    )
  }

  private func performUndoableListReplacement(
    range: NSRange,
    replacement: String,
    selectionAfterEdit: NSRange
  ) -> Bool {
    let sourceLength = textView.string.utf16.count
    guard range.location >= 0, NSMaxRange(range) <= sourceLength,
      selectionAfterEdit.location >= 0,
      NSMaxRange(selectionAfterEdit) <= sourceLength - range.length + replacement.utf16.count
    else { return false }

    let replacedSource = (textView.string as NSString).substring(with: range)
    let selectionBeforeEdit = textView.selectedRange()
    let undoManager = textView.undoManager
    textView.breakUndoCoalescing()
    undoManager?.disableUndoRegistration()
    textView.insertText(replacement, replacementRange: range)
    undoManager?.enableUndoRegistration()
    textView.setSelectedRange(selectionAfterEdit)
    textView.scrollRangeToVisible(selectionAfterEdit)

    let inverseRange = NSRange(location: range.location, length: replacement.utf16.count)
    undoManager?.registerUndo(withTarget: self) { target in
      _ = target.performUndoableListReplacement(
        range: inverseRange,
        replacement: replacedSource,
        selectionAfterEdit: selectionBeforeEdit
      )
    }
    undoManager?.setActionName("Toggle List Item")
    reportViewportChange()
    return true
  }

  @discardableResult
  public func performLinkInteraction(
    _ presentation: LinkPresentation,
    modifiers: LinkInteractionModifiers
  ) -> LinkInteractionAction {
    let action = linkInteractionPolicy.action(
      for: presentation,
      modifiers: modifiers,
      settings: editorSettings
    )
    switch action {
    case .open(let url):
      _ = linkOpenHandler?(url) ?? NSWorkspace.shared.open(url)
    case .toggleExpanded(let identity):
      if expandedLinkIdentities.contains(identity) {
        expandedLinkIdentities.remove(identity)
      } else {
        expandedLinkIdentities.insert(identity)
      }
      linkExpansionDidToggle?(identity)
    case .ignore:
      break
    }
    return action
  }

  @objc private func copyLink(_ sender: NSMenuItem) {
    guard let originalURL = sender.representedObject as? String else { return }
    let selection = textView.selectedRange()
    writeToPasteboard(
      selection.length > 0 ? contextualCopyText(for: selection) : originalURL
    )
  }

  private func writeToPasteboard(_ text: String) {
    pasteboard.clearContents()
    if pasteboard.setString(text, forType: .string) {
      pasteboardDidWrite?()
    }
  }
}

@MainActor
private final class ProjectionTextView: NSTextView {
  var copyHandler: ((NSRange) -> String?)?
  var pasteboardWriteHandler: (() -> Void)?
  var layoutHandler: (() -> Void)?
  var directionalEntryHandler: ((EditorDirectionalEntry) -> Bool)?
  var cancelDirectionalEntryHandler: (() -> Void)?
  var navigationHandler: ((NoteNavigationDirection) -> Void)?
  var pasteHandler: ((PasteboardPayload, PasteMode) -> Void)?
  var ocrPasteboardHandler: ((NSPasteboard, EditorOCRInputSource, NSRange?) -> Bool)?
  var toggleCommentHandler: (() -> Bool)?
  var slashCommandTriggerHandler: (() -> Bool)?
  var slashCommandKeyHandler: ((EditorSlashCommandKey) -> Bool)?
  var slashCommandsAreActive = false
  var variableAutocompleteKeyHandler: ((EditorVariableAutocompleteKey) -> Bool)?
  var timerCommandCommitHandler: (() -> Void)?
  var timerEscapeHandler: (() -> Bool)?

  private var gestureInterpreter = HorizontalNavigationGestureInterpreter()
  private let detachedUndoManager = UndoManager()

  override var undoManager: UndoManager? {
    window?.undoManager ?? detachedUndoManager
  }

  override func copy(_ sender: Any?) {
    guard let copiedText = copyHandler?(selectedRange()) else {
      super.copy(sender)
      return
    }
    NSPasteboard.general.clearContents()
    if NSPasteboard.general.setString(copiedText, forType: .string) {
      pasteboardWriteHandler?()
    }
  }

  override func paste(_ sender: Any?) {
    if ocrPasteboardHandler?(.general, .paste, nil) == true {
      return
    }
    guard let pasteHandler else {
      super.paste(sender)
      return
    }
    pasteHandler(Self.payload(from: .general), .normal)
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    if ocrPasteboardHandler != nil,
      EditorOCRPasteboardReader().hasImageCandidate(in: sender.draggingPasteboard)
    {
      return .copy
    }
    return super.draggingEntered(sender)
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    if ocrPasteboardHandler != nil,
      EditorOCRPasteboardReader().hasImageCandidate(in: sender.draggingPasteboard)
    {
      return .copy
    }
    return super.draggingUpdated(sender)
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    if ocrPasteboardHandler != nil,
      EditorOCRPasteboardReader().hasImageCandidate(in: sender.draggingPasteboard)
    {
      let point = convert(sender.draggingLocation, from: nil)
      let location = characterIndexForInsertion(at: point)
      return ocrPasteboardHandler?(
        sender.draggingPasteboard,
        .dragAndDrop,
        NSRange(location: location, length: 0)
      ) == true
    }
    return super.performDragOperation(sender)
  }

  @objc func pasteRaw(_ sender: Any?) {
    guard let pasteHandler else {
      NSSound.beep()
      return
    }
    pasteHandler(Self.payload(from: .general), .raw)
  }

  @objc func toggleComment(_ sender: Any?) {
    guard toggleCommentHandler?() == true else {
      NSSound.beep()
      return
    }
  }

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(copy(_:)) {
      return copyHandler != nil
    }
    if item.action == #selector(paste(_:)) || item.action == #selector(pasteRaw(_:)) {
      return pasteHandler != nil
    }
    if item.action == #selector(toggleComment(_:)) {
      return toggleCommentHandler != nil
    }
    return super.validateUserInterfaceItem(item)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    if modifiers == .command,
      event.charactersIgnoringModifiers == "/",
      toggleCommentHandler?() == true
    {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func layout() {
    super.layout()
    layoutHandler?()
  }

  override func keyDown(with event: NSEvent) {
    let commandModifiers = event.modifierFlags.intersection([.command, .control, .option])
    if commandModifiers.isEmpty {
      if let variableKey = variableAutocompleteKey(for: event),
        variableAutocompleteKeyHandler?(variableKey) == true
      {
        return
      }
      if slashCommandsAreActive {
        if let slashKey = slashCommandKey(for: event) {
          _ = slashCommandKeyHandler?(slashKey)
        } else {
          NSSound.beep()
        }
        return
      }
      if event.charactersIgnoringModifiers == "/",
        slashCommandTriggerHandler?() == true
      {
        return
      }
      if event.keyCode == 53, timerEscapeHandler?() == true {
        return
      }
    }
    if commandModifiers.isEmpty, let entry = directionalEntry(for: event.keyCode),
      directionalEntryHandler?(entry) == true
    {
      return
    }
    cancelDirectionalEntryHandler?()
    super.keyDown(with: event)
  }

  override func insertNewline(_ sender: Any?) {
    super.insertNewline(sender)
    timerCommandCommitHandler?()
  }

  override func scrollWheel(with event: NSEvent) {
    if event.phase == .began {
      gestureInterpreter.reset()
    }
    let completesGesture = event.phase == .ended || event.phase == .cancelled || event.phase.isEmpty
    if let direction = gestureInterpreter.update(
      deltaX: event.scrollingDeltaX,
      deltaY: event.scrollingDeltaY,
      isComplete: completesGesture
    ) {
      navigationHandler?(direction)
      return
    }
    super.scrollWheel(with: event)
  }

  private func directionalEntry(for keyCode: UInt16) -> EditorDirectionalEntry? {
    switch keyCode {
    case 124, 125:
      .start
    case 123, 126:
      .end
    default:
      nil
    }
  }

  private func slashCommandKey(for event: NSEvent) -> EditorSlashCommandKey? {
    switch event.keyCode {
    case 126:
      return .moveUp
    case 125, 48:
      return .moveDown
    case 36, 76:
      return .select
    case 53:
      return .dismiss
    case 51, 117:
      return .deleteBackward
    default:
      break
    }

    if let characters = event.charactersIgnoringModifiers,
      characters.count == 1,
      let character = characters.first,
      let number = character.wholeNumberValue,
      (1...9).contains(number)
    {
      return .selectNumber(number)
    }
    guard let characters = event.characters,
      !characters.isEmpty,
      characters.unicodeScalars.allSatisfy({
        $0.properties.generalCategory != .control
      })
    else { return nil }
    return .append(characters)
  }

  private func variableAutocompleteKey(for event: NSEvent) -> EditorVariableAutocompleteKey? {
    guard !event.modifierFlags.contains(.shift) else { return nil }
    switch event.keyCode {
    case 48:
      return .acceptFirst
    case 53:
      return .dismiss
    default:
      break
    }
    guard let characters = event.charactersIgnoringModifiers,
      characters.count == 1,
      let character = characters.first,
      let number = character.wholeNumberValue,
      (1...9).contains(number)
    else { return nil }
    return .acceptNumber(number)
  }

  private static func payload(from pasteboard: NSPasteboard) -> PasteboardPayload {
    PasteboardPayload(
      plainText: pasteboard.string(forType: .string),
      html: pasteboard.data(forType: .html),
      richText: pasteboard.data(forType: .rtf)
    )
  }
}

@MainActor
private final class ProjectionAdornmentButton: NSButton {
  enum Kind: Equatable {
    case checkbox
    case copy
    case link
    case timer
    case timerTutorial
    case none
  }

  var sourceRange: SourceRange?
  var markerRange: SourceRange?
  var copiedText: String?
  var linkPresentation: LinkPresentation?
  var timerAlias: String?
  var timerTutorialPopover: NSPopover?
  var kind: Kind = .none
}

@MainActor
private final class TimerTutorialViewController: NSViewController {
  private let alias: String

  init(alias: String) {
    self.alias = alias
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let commands = [
      "\(alias) - stopwatch",
      "\(alias) 3.5 or 3:30 - countdown",
      "\(alias) 5: Title - titled countdown",
      "\(alias) 25 5 - work and break",
      "\(alias) pomo - 25 / 5",
      "\(alias) p - pause or resume",
      "\(alias) r - restart",
      "\(alias) s or 0 - stop",
    ]
    let heading = NSTextField(labelWithString: "Timer commands")
    heading.font = .systemFont(ofSize: 15, weight: .semibold)
    let labels = commands.map { command -> NSTextField in
      let label = NSTextField(labelWithString: command)
      label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
      label.textColor = .secondaryLabelColor
      label.lineBreakMode = .byTruncatingTail
      return label
    }
    let stack = NSStackView(views: [heading] + labels)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    stack.setAccessibilityElement(true)
    stack.setAccessibilityRole(.group)
    stack.setAccessibilityLabel("Timer command tutorial")
    view = stack
  }
}

@MainActor
public final class ProjectionDecorationAccessibilityContainer: NSView {
  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Editor decorations")
    setAccessibilityIdentifier("Editor decorations")
  }

  public convenience init() {
    self.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  public override func hitTest(_ point: NSPoint) -> NSView? {
    for subview in subviews.reversed() {
      let convertedPoint = subview.convert(point, from: self)
      if let hitView = subview.hitTest(convertedPoint) {
        return hitView
      }
    }
    return nil
  }
}

extension NSRect {
  fileprivate var isFinite: Bool {
    origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
  }
}
