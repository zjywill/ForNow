import AppKit
import ForNowCore
import ForNowDesign
import ForNowEditor
import ForNowIntegrations
import ForNowModes
import ForNowWindowing
import SwiftUI

struct SettingsView: View {
  let environment: AppEnvironment

  @ObservedObject private var noteSession: NoteSessionModel
  @ObservedObject private var environmentModel: AppEnvironment
  @ObservedObject private var timerModel: TimerModel
  @ObservedObject private var ocrModel: OCRWorkflowModel
  @ObservedObject private var autoPasteModel: AutoPasteModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var newCustomRateSource = CurrencyCode(rawValue: "USD")
  @State private var newCustomRateTarget = CurrencyCode(rawValue: "EUR")
  @State private var newCustomRateValue = "1"
  @State private var confirmsMismatchedTranslucency = false
  @State private var accessibilityDisplayRevision = false
  @State private var bulkDeletionCutoff: Date

  init(environment: AppEnvironment) {
    self.environment = environment
    _noteSession = ObservedObject(wrappedValue: environment.noteSession)
    _environmentModel = ObservedObject(wrappedValue: environment)
    _timerModel = ObservedObject(wrappedValue: environment.timerModel)
    _ocrModel = ObservedObject(wrappedValue: environment.ocrModel)
    _autoPasteModel = ObservedObject(wrappedValue: environment.autoPasteModel)
    _bulkDeletionCutoff = State(
      initialValue: Calendar.autoupdatingCurrent.startOfDay(for: environment.clock.now())
    )
  }

  var body: some View {
    Form {
      Section("Window") {
        Picker("Presentation", selection: presentationMode) {
          Text("Standard").tag(WindowPresentationMode.standard)
          Text("Pseudo Menu").tag(WindowPresentationMode.menuBarPanel)
          Text("Traditional Dropdown").tag(WindowPresentationMode.dropdownPanel)
        }

        Picker("App presence", selection: presenceMode) {
          Text("Dock").tag(ApplicationPresenceMode.dock)
          Text("Menu Bar").tag(ApplicationPresenceMode.menuBar)
          Text("Both").tag(ApplicationPresenceMode.both)
          Text("Neither").tag(ApplicationPresenceMode.neither)
        }

        Toggle("Keep window above other apps", isOn: isPinned)
        Toggle("Hide when ForNow becomes inactive", isOn: autoHideEnabled)

        if environmentModel.windowConfiguration.mode == .dropdownPanel {
          Stepper(
            "Dropdown width: \(Int(environmentModel.windowConfiguration.dropdownDimensions.width))",
            value: dropdownWidth,
            in: 360...1_200,
            step: 20
          )
          Stepper(
            "Dropdown height: \(Int(environmentModel.windowConfiguration.dropdownDimensions.height))",
            value: dropdownHeight,
            in: 280...1_000,
            step: 20
          )
        }

        HStack {
          Text("Global shortcut")
          Spacer()
          ShortcutRecorder(
            candidate: environmentModel.currentGlobalShortcut,
            onCandidate: environment.applyGlobalShortcut
          )
          .frame(width: 120, height: 24)
        }

        if !environmentModel.shortcutRegistrationResult.isAccepted {
          Text(environmentModel.shortcutRegistrationResult.message)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Section("Notes") {
        Toggle("Create a new note on launch", isOn: createsNewNoteOnLaunch)
        Picker("Create a new note after reopening", selection: reopenPolicy) {
          Text("Always").tag(ReopenNewNotePolicy.always)
          Text("3 minutes").tag(ReopenNewNotePolicy.afterThreeMinutes)
          Text("30 minutes").tag(ReopenNewNotePolicy.afterThirtyMinutes)
          Text("1 hour").tag(ReopenNewNotePolicy.afterOneHour)
          Text("1 day").tag(ReopenNewNotePolicy.afterOneDay)
          Text("Never").tag(ReopenNewNotePolicy.never)
        }
        Toggle("Show note count", isOn: showsNoteCount)
        Picker("Automatically delete notes", selection: expirationChoice) {
          Text("Today").tag(NoteExpirationChoice.today)
          Text("After one week").tag(NoteExpirationChoice.oneWeek)
          Text("After one month").tag(NoteExpirationChoice.oneMonth)
          Text("After one year").tag(NoteExpirationChoice.oneYear)
          Text("Never").tag(NoteExpirationChoice.never)
        }
        .accessibilityIdentifier("Note expiration choice")

        if let expirationErrorMessage = environmentModel.expirationErrorMessage {
          Text(expirationErrorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Section("Paste") {
        Toggle("Remove leading whitespace", isOn: pasteBinding(\.stripsLeadingWhitespace))
        Toggle("Remove list numbers", isOn: pasteBinding(\.stripsListNumbers))
        Toggle("Remove bullets", isOn: pasteBinding(\.stripsBullets))
        Toggle("Remove Markdown formatting", isOn: pasteBinding(\.stripsMarkdown))
        Toggle("Remove empty lines", isOn: pasteBinding(\.stripsEmptyLines))
      }

      Section("AutoPaste") {
        TextField("Prefix", text: autoPasteBinding(\.prefix))
        TextField("Suffix", text: autoPasteBinding(\.suffix))
        Picker("Default separator", selection: autoPasteBinding(\.separatorPreset)) {
          ForEach(AutoPasteSeparatorPreset.allCases, id: \.self) { preset in
            Text(preset.displayName).tag(preset)
          }
        }
        Picker("Links", selection: autoPasteBinding(\.linkTreatment)) {
          ForEach(AutoPasteLinkTreatment.allCases, id: \.self) { treatment in
            Text(treatment.displayName).tag(treatment)
          }
        }
        Picker("Timestamp", selection: autoPasteBinding(\.timestampPolicy)) {
          ForEach(AutoPasteTimestampPolicy.allCases, id: \.self) { policy in
            Text(policy.displayName).tag(policy)
          }
        }
        if autoPasteModel.hasSettingsPersistenceFailure {
          Text("AutoPaste settings could not be saved.")
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Section("Text Recognition") {
        Picker("Language", selection: ocrLanguagePreference) {
          ForEach(OCRLanguagePreference.allCases, id: \.self) { preference in
            Text(preference.displayName).tag(preference)
          }
        }
        if ocrModel.hasSettingsPersistenceFailure {
          Text("Recognition language could not be saved.")
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Section("Editor") {
        Toggle(
          "Automatically shorten links",
          isOn: editorBinding(\.automaticallyShortensLinks)
        )
        Toggle(
          "Enable hyperlink features",
          isOn: editorBinding(\.hyperlinkFeaturesEnabled)
        )
        Toggle(
          "Omit checked markers from clean copy",
          isOn: editorBinding(\.omitsChecklistTriggersOnExport)
        )
        Picker(
          "Default code language",
          selection: editorBinding(\.defaultCodeLanguage)
        ) {
          ForEach(CodeLanguage.allCases, id: \.self) { language in
            Text(language.displayName).tag(language)
          }
        }
        Picker(
          "Code highlighting theme",
          selection: editorBinding(\.codeHighlightTheme)
        ) {
          ForEach(CodeHighlightTheme.allCases, id: \.self) { theme in
            Text(theme.displayName).tag(theme)
          }
        }
        Picker(
          "Text layout direction",
          selection: editorBinding(\.layoutDirection)
        ) {
          ForEach(EditorLayoutDirection.allCases, id: \.self) { direction in
            Text(direction.displayName).tag(direction)
          }
        }
      }

      ExportSettingsSection(environment: environment)

      Section("Appearance") {
        Picker("Light mode theme", selection: appearanceBinding(\.lightThemeID)) {
          ForEach(BuiltInThemeID.allCases, id: \.self) { themeID in
            Text("\(themeID.displayName) (\(themeID.intendedAppearance.displayName))")
              .tag(themeID)
          }
        }
        Picker("Dark mode theme", selection: appearanceBinding(\.darkThemeID)) {
          ForEach(BuiltInThemeID.allCases, id: \.self) { themeID in
            Text("\(themeID.displayName) (\(themeID.intendedAppearance.displayName))")
              .tag(themeID)
          }
        }
        Picker("Paper", selection: appearanceBinding(\.paperStyle)) {
          ForEach(PaperStyle.allCases, id: \.self) { style in
            Text(style.displayName).tag(style)
          }
        }
        Picker("Paper visibility", selection: appearanceBinding(\.paperOpacity)) {
          ForEach(PaperOpacity.allCases, id: \.self) { opacity in
            Text(opacity.displayName).tag(opacity)
          }
        }
        Picker(
          "List spacing on lined paper",
          selection: appearanceBinding(\.linedPaperListSpacing)
        ) {
          ForEach(ListSpacing.allCases, id: \.self) { spacing in
            Text(spacing.displayName).tag(spacing)
          }
        }
        Picker(
          "List spacing on blank or grid paper",
          selection: appearanceBinding(\.blankPaperListSpacing)
        ) {
          ForEach(ListSpacing.allCases, id: \.self) { spacing in
            Text(spacing.displayName).tag(spacing)
          }
        }
        Picker("Text size", selection: appearanceBinding(\.textSize)) {
          ForEach(EditorTextSize.allCases, id: \.self) { size in
            Text(size.displayName).tag(size)
          }
        }
        .pickerStyle(.segmented)
        Toggle("Double text size", isOn: appearanceBinding(\.doublesTextSize))

        Toggle("Translucent background", isOn: translucentMode)
          .disabled(!appearancePresentation.translucentModeIsAvailable)

        LabeledContent("Background opacity") {
          HStack(spacing: 10) {
            Slider(value: backgroundOpacity, in: 0...90, step: 1)
              .frame(width: 180)
            Text("\(environmentModel.appearanceSettings.backgroundOpacity)%")
              .monospacedDigit()
              .frame(width: 42, alignment: .trailing)
          }
        }
        .disabled(!environmentModel.appearanceSettings.translucentModeEnabled)

        if !appearancePresentation.translucentModeIsAvailable {
          Text("Translucent background requires macOS 15 or newer.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
          environmentModel.appearanceSettings.translucentModeEnabled
        {
          Text("Reduced Transparency is active; a solid background is in use.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if appearancePresentation.showsThemeMismatchWarning,
          environmentModel.appearanceSettings.translucentModeEnabled
        {
          Label(
            "The selected theme does not match the current system appearance.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      ModeSettingsSection(environment: environment)
      QuickActionSettingsSection(environment: environment)

      Section("Math") {
        Stepper(
          "Result digits: \(environmentModel.mathSettings.significantDigits)",
          value: mathBinding(\.significantDigits),
          in: 0...7
        )
        Toggle(
          "Separate thousands",
          isOn: mathBinding(\.separatesThousands)
        )
        Picker("Primary currency", selection: mathBinding(\.primaryCurrency)) {
          ForEach(currencyDefinitions) { currency in
            Text("\(currency.code.rawValue) - \(currency.name)").tag(currency.code)
          }
        }
        Picker("Secondary currency", selection: mathBinding(\.secondaryCurrency)) {
          ForEach(currencyDefinitions) { currency in
            Text("\(currency.code.rawValue) - \(currency.name)").tag(currency.code)
          }
        }
        TextField(
          "Primary symbol",
          text: mathBinding(\.primaryCurrencySymbol)
        )
        Toggle(
          "Refresh currency rates daily",
          isOn: mathBinding(\.automaticCurrencyRefreshEnabled)
        )
        HStack {
          Text(currencyRateStatusText)
            .foregroundStyle(.secondary)
          Spacer()
          if environmentModel.currencyRateRefreshState == .refreshing {
            ProgressView()
              .controlSize(.small)
          }
          Button {
            Task { await environment.refreshCurrencyRatesManually() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(environmentModel.currencyRateRefreshState == .refreshing)
          .help("Refresh Currency Rates")
          .accessibilityLabel("Refresh Currency Rates")
        }

        ForEach(environmentModel.mathSettings.customCurrencyRates) { rate in
          HStack {
            Text("\(rate.source.rawValue) to \(rate.target.rawValue)")
              .frame(width: 96, alignment: .leading)
            TextField("Rate", text: customRateBinding(rate))
              .textFieldStyle(.roundedBorder)
            Button {
              deleteCustomRate(rate)
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Custom Rate")
            .accessibilityLabel("Delete Custom Rate")
          }
        }

        HStack {
          Picker("From", selection: $newCustomRateSource) {
            ForEach(currencyDefinitions) { currency in
              Text(currency.code.rawValue).tag(currency.code)
            }
          }
          .labelsHidden()
          Text("to")
          Picker("To", selection: $newCustomRateTarget) {
            ForEach(currencyDefinitions) { currency in
              Text(currency.code.rawValue).tag(currency.code)
            }
          }
          .labelsHidden()
          TextField("Rate", text: $newCustomRateValue)
            .textFieldStyle(.roundedBorder)
          Button {
            addCustomRate()
          } label: {
            Image(systemName: "plus")
          }
          .buttonStyle(.borderless)
          .disabled(parsedNewCustomRate == nil)
          .help("Add Custom Rate")
          .accessibilityLabel("Add Custom Rate")
        }
      }

      Section("Timer") {
        Toggle("Pause timer when quitting", isOn: timerBinding(\.pausesOnQuit))
        Toggle("Show time in menu bar", isOn: timerBinding(\.showsTimeInMenuBar))

        LabeledContent("Countdown") {
          VStack(alignment: .leading, spacing: 6) {
            Toggle("Notification", isOn: timerBinding(\.showsCountdownNotifications))
            Toggle("Full-screen takeover", isOn: timerBinding(\.showsCountdownTakeover))
            Toggle("Sound", isOn: timerBinding(\.playsCountdownSound))
          }
        }

        LabeledContent("Pomodoro break") {
          VStack(alignment: .leading, spacing: 6) {
            Toggle(
              "Notification",
              isOn: timerBinding(\.showsPomodoroBreakNotifications)
            )
            Toggle(
              "Full-screen takeover",
              isOn: timerBinding(\.showsPomodoroBreakTakeover)
            )
            Toggle("Sound", isOn: timerBinding(\.playsPomodoroBreakSound))
          }
        }

        LabeledContent("Sound volume") {
          HStack(spacing: 10) {
            Slider(value: timerVolume, in: 0...100, step: 1)
              .frame(width: 180)
            Text("\(timerModel.settings.soundVolume)%")
              .monospacedDigit()
              .frame(width: 42, alignment: .trailing)
          }
        }
      }

      Section("Deletion") {
        Button("Reset Delete Warning") {
          Task { try? await noteSession.resetDeleteWarning() }
        }
        .disabled(!noteSession.settings.suppressesDeleteWarning)

        DatePicker(
          "Delete notes modified before",
          selection: $bulkDeletionCutoff,
          displayedComponents: .date
        )
        .accessibilityIdentifier("Bulk deletion cutoff")

        Button {
          Task {
            let cutoff = Calendar.autoupdatingCurrent.startOfDay(for: bulkDeletionCutoff)
            _ = try? await environment.previewBulkDeletion(before: cutoff)
          }
        } label: {
          Label("Preview Notes", systemImage: "eye")
        }
        .disabled(environmentModel.isBulkDeletionWorking)
        .accessibilityIdentifier("Preview bulk deletion")

        if let preview = environmentModel.bulkDeletionPreview {
          Text("\(preview.count) \(noteLabel(preview.count)) match the selected cutoff.")
            .font(.callout)
            .accessibilityIdentifier("Bulk deletion preview count")
          Text("This action cannot be undone.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("Bulk deletion irreversible warning")

          Button(role: .destructive) {
            Task { _ = try? await environment.requestBulkDeletionConfirmation() }
          } label: {
            Label("Delete \(preview.count) Permanently", systemImage: "trash")
          }
          .disabled(preview.count == 0 || environmentModel.isBulkDeletionWorking)
          .accessibilityIdentifier("Confirm bulk deletion")
        }

        if let receipt = environmentModel.lastBulkDeletionReceipt {
          Text(
            "Deleted \(receipt.deletedCount) \(noteLabel(receipt.deletedCount)); safety backup created."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("Bulk deletion result")
        }

        if let errorMessage = environmentModel.bulkDeletionErrorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityIdentifier("Bulk deletion error")
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 640, height: 820)
    .onAppear { environment.settingsDidAppear() }
    .onDisappear { environment.settingsDidDisappear() }
    .onReceive(
      NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
      )
    ) { _ in
      accessibilityDisplayRevision.toggle()
    }
    .onChange(of: bulkDeletionCutoff) {
      environment.cancelBulkDeletion()
    }
    .alert("Theme Appearance Mismatch", isPresented: $confirmsMismatchedTranslucency) {
      Button("Cancel", role: .cancel) {}
      Button("Enable Translucency") {
        var settings = environmentModel.appearanceSettings
        settings.translucentModeEnabled = true
        Task { try? await environment.updateAppearanceSettings(settings) }
      }
    } message: {
      Text(
        "The selected theme targets a different system appearance. Preview contrast before continuing."
      )
    }
  }

  private var createsNewNoteOnLaunch: Binding<Bool> {
    lifecycleBinding(\.createsNewNoteOnLaunch)
  }

  private var reopenPolicy: Binding<ReopenNewNotePolicy> {
    lifecycleBinding(\.reopenNewNotePolicy)
  }

  private var showsNoteCount: Binding<Bool> {
    lifecycleBinding(\.showsNoteCount)
  }

  private var expirationChoice: Binding<NoteExpirationChoice> {
    Binding(
      get: { noteSession.settings.noteExpirationChoice },
      set: { choice in
        Task { try? await environment.updateExpirationChoice(choice) }
      }
    )
  }

  private func noteLabel(_ count: Int) -> String {
    count == 1 ? "note" : "notes"
  }

  private var presentationMode: Binding<WindowPresentationMode> {
    windowBinding(\.mode)
  }

  private var presenceMode: Binding<ApplicationPresenceMode> {
    windowBinding(\.presence)
  }

  private var isPinned: Binding<Bool> {
    windowBinding(\.isPinned)
  }

  private var autoHideEnabled: Binding<Bool> {
    windowBinding(\.autoHideEnabled)
  }

  private var dropdownWidth: Binding<Double> {
    Binding(
      get: { Double(environmentModel.windowConfiguration.dropdownDimensions.width) },
      set: { value in
        var configuration = environmentModel.windowConfiguration
        configuration.dropdownDimensions.width = CGFloat(value)
        Task { try? await environment.updateWindowConfiguration(configuration) }
      }
    )
  }

  private var dropdownHeight: Binding<Double> {
    Binding(
      get: { Double(environmentModel.windowConfiguration.dropdownDimensions.height) },
      set: { value in
        var configuration = environmentModel.windowConfiguration
        configuration.dropdownDimensions.height = CGFloat(value)
        Task { try? await environment.updateWindowConfiguration(configuration) }
      }
    )
  }

  private func lifecycleBinding<Value>(_ keyPath: WritableKeyPath<LifecycleSettings, Value>)
    -> Binding<Value>
  {
    Binding(
      get: { noteSession.settings[keyPath: keyPath] },
      set: { value in
        var settings = noteSession.settings
        settings[keyPath: keyPath] = value
        Task { try? await noteSession.updateSettings(settings) }
      }
    )
  }

  private func windowBinding<Value>(_ keyPath: WritableKeyPath<WindowConfiguration, Value>)
    -> Binding<Value>
  {
    Binding(
      get: { environmentModel.windowConfiguration[keyPath: keyPath] },
      set: { value in
        var configuration = environmentModel.windowConfiguration
        configuration[keyPath: keyPath] = value
        Task { try? await environment.updateWindowConfiguration(configuration) }
      }
    )
  }

  private func pasteBinding(_ keyPath: WritableKeyPath<PasteSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { environmentModel.pasteSettings[keyPath: keyPath] },
      set: { value in
        var settings = environmentModel.pasteSettings
        settings[keyPath: keyPath] = value
        Task { try? await environment.updatePasteSettings(settings) }
      }
    )
  }

  private func editorBinding<Value>(_ keyPath: WritableKeyPath<EditorSettings, Value>)
    -> Binding<Value>
  {
    Binding(
      get: { environmentModel.editorSettings[keyPath: keyPath] },
      set: { value in
        var settings = environmentModel.editorSettings
        settings[keyPath: keyPath] = value
        Task { try? await environment.updateEditorSettings(settings) }
      }
    )
  }

  private func appearanceBinding<Value>(
    _ keyPath: WritableKeyPath<AppearanceSettings, Value>
  ) -> Binding<Value> {
    Binding(
      get: { environmentModel.appearanceSettings[keyPath: keyPath] },
      set: { value in
        var settings = environmentModel.appearanceSettings
        settings[keyPath: keyPath] = value
        Task { try? await environment.updateAppearanceSettings(settings) }
      }
    )
  }

  private var translucentMode: Binding<Bool> {
    Binding(
      get: { environmentModel.appearanceSettings.translucentModeEnabled },
      set: { enabled in
        var settings = environmentModel.appearanceSettings
        if enabled, settings.hasThemeMismatch(for: interfaceAppearance) {
          confirmsMismatchedTranslucency = true
          return
        }
        settings.translucentModeEnabled = enabled
        Task { try? await environment.updateAppearanceSettings(settings) }
      }
    )
  }

  private var backgroundOpacity: Binding<Double> {
    Binding(
      get: { Double(environmentModel.appearanceSettings.backgroundOpacity) },
      set: { value in
        var settings = environmentModel.appearanceSettings
        settings.backgroundOpacity = Int(value.rounded())
        Task { try? await environment.updateAppearanceSettings(settings) }
      }
    )
  }

  private var interfaceAppearance: InterfaceAppearance {
    colorScheme == .dark ? .dark : .light
  }

  private var appearancePresentation: AppearancePresentation {
    _ = accessibilityDisplayRevision
    return AppearancePresentation.resolve(
      settings: environmentModel.appearanceSettings,
      environment: AppearanceEnvironment(
        operatingSystemMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        interfaceAppearance: interfaceAppearance,
        reducesTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
        increasesContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
      )
    )
  }

  private func autoPasteBinding<Value>(
    _ keyPath: WritableKeyPath<AutoPasteSettings, Value>
  ) -> Binding<Value> {
    Binding(
      get: { autoPasteModel.settings[keyPath: keyPath] },
      set: { value in
        var settings = autoPasteModel.settings
        settings[keyPath: keyPath] = value
        Task { try? await environment.updateAutoPasteSettings(settings) }
      }
    )
  }

  private func mathBinding<Value>(_ keyPath: WritableKeyPath<MathSettings, Value>)
    -> Binding<Value>
  {
    Binding(
      get: { environmentModel.mathSettings[keyPath: keyPath] },
      set: { value in
        var settings = environmentModel.mathSettings
        settings[keyPath: keyPath] = value
        Task { try? await environment.updateMathSettings(settings) }
      }
    )
  }

  private func timerBinding<Value>(_ keyPath: WritableKeyPath<TimerSettings, Value>)
    -> Binding<Value>
  {
    Binding(
      get: { timerModel.settings[keyPath: keyPath] },
      set: { value in
        var settings = timerModel.settings
        settings[keyPath: keyPath] = value
        Task { try? await environment.updateTimerSettings(settings) }
      }
    )
  }

  private var ocrLanguagePreference: Binding<OCRLanguagePreference> {
    Binding(
      get: { ocrModel.settings.languagePreference },
      set: { preference in
        var settings = ocrModel.settings
        settings.languagePreference = preference
        Task { try? await environment.updateOCRSettings(settings) }
      }
    )
  }

  private var timerVolume: Binding<Double> {
    Binding(
      get: { Double(timerModel.settings.soundVolume) },
      set: { value in
        var settings = timerModel.settings
        settings.soundVolume = Int(value.rounded())
        Task { try? await environment.updateTimerSettings(settings) }
      }
    )
  }

  private var currencyDefinitions: [CurrencyDefinition] {
    ConversionCatalogs.bundled.currencies.currencies
  }

  private var currencyRateStatusText: String {
    switch environmentModel.currencyRateRefreshState {
    case .idle:
      "No cached rates"
    case .refreshing:
      "Refreshing rates"
    case .failed:
      environmentModel.rateSnapshot == nil ? "Refresh failed" : "Using cached rates"
    case .current:
      environmentModel.rateSnapshot == nil ? "No cached rates" : "Rates available"
    }
  }

  private var parsedNewCustomRate: Decimal? {
    guard
      newCustomRateSource != newCustomRateTarget,
      let value = Decimal(
        string: newCustomRateValue,
        locale: Locale(identifier: "en_US_POSIX")
      ),
      NSDecimalNumber(decimal: value).compare(NSDecimalNumber.zero) == .orderedDescending
    else { return nil }
    return value
  }

  private func customRateBinding(_ rate: CustomCurrencyRate) -> Binding<String> {
    Binding(
      get: { NSDecimalNumber(decimal: rate.rate).stringValue },
      set: { source in
        guard
          let value = Decimal(string: source, locale: Locale(identifier: "en_US_POSIX")),
          NSDecimalNumber(decimal: value).compare(NSDecimalNumber.zero) == .orderedDescending,
          let index = environmentModel.mathSettings.customCurrencyRates.firstIndex(where: {
            $0.id == rate.id
          })
        else { return }
        var settings = environmentModel.mathSettings
        settings.customCurrencyRates[index].rate = value
        settings.customCurrencyRates[index].updatedAt = environment.clock.now()
        Task { try? await environment.updateMathSettings(settings) }
      }
    )
  }

  private func addCustomRate() {
    guard let value = parsedNewCustomRate else { return }
    let rate = CustomCurrencyRate(
      source: newCustomRateSource,
      target: newCustomRateTarget,
      rate: value,
      updatedAt: environment.clock.now()
    )
    var settings = environmentModel.mathSettings
    if let index = settings.customCurrencyRates.firstIndex(where: { $0.id == rate.id }) {
      settings.customCurrencyRates[index] = rate
    } else {
      settings.customCurrencyRates.append(rate)
    }
    Task { try? await environment.updateMathSettings(settings) }
  }

  private func deleteCustomRate(_ rate: CustomCurrencyRate) {
    var settings = environmentModel.mathSettings
    settings.customCurrencyRates.removeAll { $0.id == rate.id }
    Task { try? await environment.updateMathSettings(settings) }
  }
}

private struct ShortcutRecorder: NSViewRepresentable {
  let candidate: GlobalShortcutCandidate
  let onCandidate: (GlobalShortcutCandidate) -> ShortcutRegistrationResult

  func makeNSView(context: Context) -> ValidatedShortcutRecorderCocoa {
    let recorder = ValidatedShortcutRecorderCocoa(currentCandidate: candidate)
    recorder.candidateHandler = onCandidate
    return recorder
  }

  func updateNSView(_ nsView: ValidatedShortcutRecorderCocoa, context: Context) {
    nsView.candidateHandler = onCandidate
    if nsView.currentCandidate != candidate {
      nsView.currentCandidate = candidate
    }
  }
}
