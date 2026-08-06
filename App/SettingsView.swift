import AppKit
import ForNowCore
import ForNowEditor
import ForNowModes
import ForNowWindowing
import SwiftUI

struct SettingsView: View {
  let environment: AppEnvironment

  @ObservedObject private var noteSession: NoteSessionModel
  @ObservedObject private var environmentModel: AppEnvironment

  init(environment: AppEnvironment) {
    self.environment = environment
    _noteSession = ObservedObject(wrappedValue: environment.noteSession)
    _environmentModel = ObservedObject(wrappedValue: environment)
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
      }

      Section("Paste") {
        Toggle("Remove leading whitespace", isOn: pasteBinding(\.stripsLeadingWhitespace))
        Toggle("Remove list numbers", isOn: pasteBinding(\.stripsListNumbers))
        Toggle("Remove bullets", isOn: pasteBinding(\.stripsBullets))
        Toggle("Remove Markdown formatting", isOn: pasteBinding(\.stripsMarkdown))
        Toggle("Remove empty lines", isOn: pasteBinding(\.stripsEmptyLines))
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
      }

      ModeSettingsSection(environment: environment)

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
      }

      Section("Deletion") {
        Button("Reset Delete Warning") {
          Task { try? await noteSession.resetDeleteWarning() }
        }
        .disabled(!noteSession.settings.suppressesDeleteWarning)
      }
    }
    .formStyle(.grouped)
    .frame(width: 640, height: 720)
    .onAppear { environment.settingsDidAppear() }
    .onDisappear { environment.settingsDidDisappear() }
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
