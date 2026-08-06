import ForNowModes
import SwiftUI

struct ModeSettingsSection: View {
  let environment: AppEnvironment

  @ObservedObject private var environmentModel: AppEnvironment
  @State private var keywordInterpretationEnabled: Bool
  @State private var aliasesByMode: [ModeID: String]
  @State private var mainAliasByMode: [ModeID: String]
  @State private var checklistTrigger: String
  @State private var errorMessage: String?
  @State private var isSaving = false

  init(environment: AppEnvironment) {
    self.environment = environment
    _environmentModel = ObservedObject(wrappedValue: environment)
    let settings = environment.modeSettings
    _keywordInterpretationEnabled = State(
      initialValue: settings.keywordInterpretationEnabled
    )
    _aliasesByMode = State(
      initialValue: Dictionary(
        uniqueKeysWithValues: settings.definitions.map {
          ($0.modeID, $0.aliases.joined(separator: ", "))
        }
      )
    )
    _mainAliasByMode = State(
      initialValue: Dictionary(
        uniqueKeysWithValues: settings.definitions.map { ($0.modeID, $0.mainAlias) }
      )
    )
    _checklistTrigger = State(initialValue: settings.checklistTrigger)
  }

  var body: some View {
    Section("Keywords") {
      Toggle("Enable keyword interpretation", isOn: $keywordInterpretationEnabled)

      LabeledContent("Checked marker") {
        TextField("Marker", text: $checklistTrigger)
          .frame(width: 120)
          .accessibilityLabel("List checked marker")
      }

      ForEach(ModeID.allCases, id: \.self) { modeID in
        LabeledContent(modeID.displayName) {
          HStack(spacing: 8) {
            TextField("Aliases", text: aliasBinding(for: modeID))
              .frame(minWidth: 210)
              .accessibilityLabel("\(modeID.displayName) aliases")

            Picker("Main alias", selection: mainAliasBinding(for: modeID)) {
              ForEach(parsedAliases(for: modeID), id: \.self) { alias in
                Text(alias).tag(alias)
              }
            }
            .labelsHidden()
            .frame(width: 120)
            .accessibilityLabel("\(modeID.displayName) main alias")
          }
        }
      }

      HStack {
        Button("Restore Defaults") {
          loadDraft(ModeSettings())
          save()
        }
        Spacer()
        Button("Save Keywords") {
          save()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isSaving)
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel("Keyword settings error: \(errorMessage)")
      }
    }
    .onChange(of: environmentModel.modeSettings) { _, settings in
      guard !isSaving else { return }
      loadDraft(settings)
    }
  }

  private func aliasBinding(for modeID: ModeID) -> Binding<String> {
    Binding(
      get: { aliasesByMode[modeID] ?? "" },
      set: { value in
        aliasesByMode[modeID] = value
        let aliases = parsedAliases(for: modeID)
        if let current = mainAliasByMode[modeID], aliases.contains(current) {
          return
        }
        mainAliasByMode[modeID] = aliases.first ?? ""
      }
    )
  }

  private func mainAliasBinding(for modeID: ModeID) -> Binding<String> {
    Binding(
      get: {
        let aliases = parsedAliases(for: modeID)
        let selected = mainAliasByMode[modeID] ?? ""
        return aliases.contains(selected) ? selected : (aliases.first ?? "")
      },
      set: { mainAliasByMode[modeID] = $0 }
    )
  }

  private func parsedAliases(for modeID: ModeID) -> [String] {
    (aliasesByMode[modeID] ?? "")
      .split(separator: ",", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private func makeSettings() -> ModeSettings {
    ModeSettings(
      keywordInterpretationEnabled: keywordInterpretationEnabled,
      definitions: ModeID.allCases.map { modeID in
        let aliases = parsedAliases(for: modeID)
        return ModeAliasDefinition(
          modeID: modeID,
          aliases: aliases,
          mainAlias: mainAliasByMode[modeID] ?? aliases.first ?? ""
        )
      },
      checklistTrigger: checklistTrigger
    )
  }

  private func save() {
    guard !isSaving else { return }
    isSaving = true
    errorMessage = nil
    let settings = makeSettings()
    Task {
      defer { isSaving = false }
      do {
        try await environment.updateModeSettings(settings)
        loadDraft(settings)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func loadDraft(_ settings: ModeSettings) {
    keywordInterpretationEnabled = settings.keywordInterpretationEnabled
    aliasesByMode = Dictionary(
      uniqueKeysWithValues: settings.definitions.map {
        ($0.modeID, $0.aliases.joined(separator: ", "))
      }
    )
    mainAliasByMode = Dictionary(
      uniqueKeysWithValues: settings.definitions.map { ($0.modeID, $0.mainAlias) }
    )
    checklistTrigger = settings.checklistTrigger
    errorMessage = nil
  }
}
